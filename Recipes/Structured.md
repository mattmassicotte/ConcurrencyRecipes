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
    typealias ValueContinuation = CheckedContinuation<Int, Never>

    enum State {
        case empty
        case pending([ValueContinuation])
        case filled(Int)
    }

    private var state = State.empty

    private func makeValue() async -> Int {
        0 // we'll pretend this is really expensive
    }

    private func fill(with result: Int) {
        guard case let .pending(array) = state else { fatalError() }

        for continuation in array {
            continuation.resume(returning: result)
        }

        self.state = .filled(result)
    }

    private func trackContinuation(_ continuation: ValueContinuation) {
        guard case var .pending(array) = state else { fatalError() }

        array.append(continuation)

        self.state = .pending(array)
    }

    public var value: Int {
        get async {
            switch state {
            case let .filled(value):
                return value
            case .pending:
                // we have no value (yet!), but we do have waiters. When this continuation is finally resumed, it will have the value we produce

                return await withCheckedContinuation { continuation in
                    trackContinuation(continuation)
                }
            case .empty:
                // this is the first request with no other pending continuations. It's critical that we make a synchronous state transition to ensure new callers are routed correctly.
                self.state = .pending([])

                let value = await makeValue()

                fill(with: value)

                return value
            }
        }
    }
}
```

### Solution #3: Track Continuations with Cancellation Support

Here is a generic cache solution with also supports cancellation. It's complicated! It uses the `withTaskCancellationHandler`, which has similar properties to `withCheckedContinuation`.

It is important to note that this implementation makes the very first request special, as it is actually filling in the cache. Cancelling the first request will have the effect of cancelling all other requests.

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

### Solution #4: Hybrid Approach

This is a hybrid structured/unstructured implemenation. It ensures that the cancellation behavior is the same across all requests, even the first. The downside to this is priority propagation will not work for the initial cache fill. This means that should a higher priority task end up needing the result, its priority will not be boosted.

```swift
actor AsyncCache<Value> where Value: Sendable {
    typealias ValueContinuation = CheckedContinuation<Value, Error>
    typealias ValueResult = Result<Value, Error>

    enum State {
        case empty
        case pending(Task<Void, Never>, [UUID: ValueContinuation])
        case filled(ValueResult)
    }

    private var state = State.empty
    private let valueProvider: () async throws -> Value
    private let fillOnCancel: Bool

    init(fillOnCancel: Bool = true, valueProvider: @escaping () async throws -> Value) {
        self.valueProvider = valueProvider
        self.fillOnCancel = fillOnCancel
    }

    private func makeValue() async throws -> Value {
        try await valueProvider()
    }

    private func cancelContinuation(with id: UUID) {
        guard case .pending(let task, var dictionary) = state else { return }

        dictionary[id]?.resume(throwing: CancellationError())
        dictionary[id] = nil

        guard dictionary.isEmpty else {
            self.state = .pending(task, dictionary)
            return
        }

        // if we have cancelled all continuations, should we cancel the underlying work?
        if fillOnCancel == false {
            task.cancel()
            self.state = .empty
            return
        }
    }

    private func fill(with result: ValueResult) {
        switch state {
        case .empty:
            // This should only occur if we have cancelled and do not want to fill the cache regardless. This is technically wasted work, but may be desirable for some uses.
            precondition(fillOnCancel == false)
        case let .pending(_, dictionary):
            for continuation in dictionary.values {
                continuation.resume(with: result)
            }

            self.state = .filled(result)
        case .filled:
            fatalError()
        }
    }

    private func trackContinuation(_ continuation: ValueContinuation, with id: UUID) {
        guard case .pending(let task, var dictionary) = state else { fatalError() }

        precondition(dictionary[id] == nil)
        dictionary[id] = continuation

        self.state = .pending(task, dictionary)
    }

    public var value: Value {
        get async throws {
            switch state {
            case let .filled(value):
                return try value.get()
            case .pending:
                break
            case .empty:
                // Begin an unstructured task to fill the cache. This gives all requests including first the same cancellation semantics.
                let task = Task {
                    do {
                        let value = try await makeValue()

                        fill(with: .success(value))
                    } catch {
                        fill(with: .failure(error))
                    }
                }

                // this is the first request with no other pending continuations. It's critical that we make a synchronous state transition to ensure new callers are routed correctly.
                self.state = .pending(task, [:])
            }

            let id = UUID() // produce a unique identifier for this request

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    // this has to go through a function call because the compiler seems unhappy if I reference pendingContinuations directly
                    trackContinuation(continuation, with: id)
                }
            } onCancel: {
                // we must move back to this actor here to access its state, referencing the unique continuation id
                Task { await self.cancelContinuation(with: id) }
            }
        }
    }
}
```