# Structured Concurrency

Once you are in an async context, you can make use of structured concurrency.

## Lazy Async Value

You'd like to lazily compute an async value and cache the result.

### Anti-Solution: Ignoring actor reentrancy

I wanted to post this just to specifically highlight that this does not work correctly, but could be tempting.

```swift
actor MyActor {
    private var expensiveValue: Int?

    private func makeValue() async -> Int {
        0 // we'll pretend this is really expensive
    }

    public var value: Int {
        get async {
            if let value = expensiveValue {
                return value
            }

            // hazard 1: Actor Reentrancy
            let value = await makeValue()

            self.expensiveValue = value

            return value
        }
    }
}
```

### Solution #1: Use an unstructured Task 

Move the async calculation into a Task, and cache that instead. This is straightforward, but because it uses unstructured concurrency, it no longer supports priority propagation or cancellation.

```swift
actor MyActor {
    private var expensiveValueTask: Task<Int, Never>?

    private func makeValue() async -> Int {
        0 // we'll pretend this is really expensive
    }

    public var value: Int {
        get async {
            // note there are no awaits between the read and write of expensiveValueTask
            if let task = expensiveValueTask {
                return await task.value
            }

            let task = Task { await makeValue() }

            self.expensiveValueTask = task

            return await task.value
        }
    }
}
```

### Solution #2: Track Continuations

Staying in the the structured concurrency world is more complex, but supports priority propagation.

It is **essential** you understand the special properties of `withCheckedContinuation` that make this technique possible. That function is annotated with `@_unsafeInheritExecutor`. This provides the guarantee we need that **despite** the `await`, there will never be a suspension before the closure's body is executed. This is why we can safely access and mutate the `pendingContinuations` array without risk of races due to reentrancy.

```swift
actor MyActor {
    private var expensiveValue: Int?
    private var pendingContinuations = [CheckedContinuation<Int, Never>]()
    
    private func makeValue() async -> Int {
        0 // we'll pretend this is really expensive
    }
    
    private func resumeAllPending(with value: Int) {
        for continuation in pendingContinuations {
            continuation.resume(returning: value)
        }
        
        pendingContinuations.removeAll()
    }
    
    public var value: Int {
        get async {
            let hasWaiters = pendingContinuations.isEmpty == false
            
            switch (expensiveValue, hasWaiters) {
            case (let value?, false):
                // we have a value and no waiters, so we can just return
                return value
            case (let value?, true):
                // while easy to handle, this situation represents an error in our continuation management and should never actually happen
                fatalError()
            case (nil, true):
                // we have no value (yet!), but we do have waiters. When this continuation is finally resumed, it will have the value we produce
                
                // make sure you unstand the special behavior of withCheckedContinuation that makes this safe!
                return await withCheckedContinuation { continuation in
                    pendingContinuations.append(continuation)
                }
            case (nil, false):
                // this is the first request
                
                let value = await makeValue()
                
                // at this point, other continuations may have been created. We must resume all of them *and* clear the list.
                resumeAllPending(with: value)
                
                return value
            }
        }
    }
}
```

### Solution #3: Track Continuations with Cancellation Support

Here is a generic cache solution with also supports cancellation. It's complicated! It uses the `withTaskCancellationHandler`, which has similar properties to `withCheckedContinuation`.

```swift
actor AsyncCache<Value> where Value: Sendable {
    typealias ValueContinuation = CheckedContinuation<Value, Error>
    typealias ValueResult = Result<Value, Error>

    enum State {
        case empty
        case pending([UUID: ValueContinuation])
        case filled(ValueResult)
    }

    private var state = State.empty
    private let valueProvider: () async throws -> Value

    init(valueProvider: @escaping () async throws -> Value) {
        self.valueProvider = valueProvider
    }

    private func makeValue() async throws -> Value {
        try await valueProvider()
    }
    
    private func cancelContinuation(with id: UUID) {
        guard case var .pending(dictionary) = state else { return }

        dictionary[id]?.resume(throwing: CancellationError())
        dictionary[id] = nil

        self.state = .pending(dictionary)
    }

    private func fill(with result: ValueResult) {
        guard case let .pending(dictionary) = state else { fatalError() }

        for continuation in dictionary.values {
            continuation.resume(with: result)
        }

        self.state = .filled(result)
    }

    private func trackContinuation(_ continuation: ValueContinuation, with id: UUID) {
        guard case var .pending(dictionary) = state else { fatalError() }

        precondition(dictionary[id] == nil)
        dictionary[id] = continuation

        self.state = .pending(dictionary)
    }

    public var value: Value {
        get async throws {
            switch state {
            case let .filled(value):
                return try value.get()
            case .pending:
                // we have no value (yet!), but we do have waiters. When this continuation is finally resumed, it will have the value we produce

                let id = UUID() // produce a unique identifier for this particular request

                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        // this has to go through a function call because the compiler seems unhappy if I reference pendingContinuations directly
                        trackContinuation(continuation, with: id)
                    }
                } onCancel: {
                    // we must move back to this actor here to access its state, referencing the unique continuation id
                    Task { await self.cancelContinuation(with: id) }
                }
            case .empty:
                // this is the first request with no other pending continuations. It's critical that we make a synchronous state transition to ensure new callers are routed correctly.
                self.state = .pending([:])

                do {
                    let value = try await makeValue()

                    fill(with: .success(value))

                    return value
                } catch {
                    fill(with: .failure(error))

                    throw error
                }
            }
        }
    }
}

```
