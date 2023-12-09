# Structured Concurrency

Once you are in an async context, you can make use of structured concurrency.

## Lazy Async Value

You'd like to lazily compute an async value and cache the result.

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