# Async Contexts

Virtually all programs needs to make at least one transition from a synchronous context to an asynchronous one.

## Ad-Hoc

You need to call some async function from a synchronous one.

```swift
func work() async throws {
}
```

### Solution #1: Plain Unstructured Task

```swift
// Hazard 1: Ordering
Task {
    // Hazard 2: thrown errors are invisible
    try await work()
}
```

### Solution #2: Typed Unstructured Task

Adding explicit return/error types to the `Task` will make it impossible to accidentally ignore thrown errors.

```swift
// Hazard 1: Ordering
Task<Void, Never> {
    try await work()
}
```

## Background Work

You need to kick off some work from the main thread, complete it in the background, and then update some state back on the main thread.

```swift
beforeWorkBegins()

DispatchQueue.global.async {
    let possibleResult = expensiveWork(arguments)
    
    DispatchQueue.main.async {
        afterWorkIsDone(possibleResult)
    }
}
```

### Solution #1: the work can be made async

Assumptions: both `beforeWorkBegins` and `afterWorkIsDone` are `MainActor`-isolated, and we are starting on the main thread

```swift
// hazard 1: timing. Does this call happen here, or within the Task?
beforeWorkBegins()

// hazard 2: ordering
Task {
    // MainActor-ness has been inherited from the creating context.

    // hazard 3: lack of caller control
    // hazard 3: sendability (for both `result and `arguments`)
    let result = await asyncExpensiveWork(arguments)

    // post-await we are now back on the original, MainActor context
    afterWorkIsDone(result)
}
```

### Solution #2: the work must be synchronous

```swift

// Work must start here, because we're going to explicitly hop off the MainActor
beforeWorkBegins()

// hazard 1: ordering
Task.detached {
    // hazard 2: blocking
    // hazard 3: sendability (arguments)
    let possibleResult = expensiveWork(arguments)
    
    // hazard 4: sendability (possibleResult)
    await MainActor.run {
        afterWorkIsDone(possibleResult)
    }
}
```

## Order-Dependent Work

You need to call some async function from a synchronous one **and** ordering must be preserved.

```swift
func work() async throws {
}
```

### Solution #1: use AsyncStream as a queue

```swift
// define a sequence that models the work (can be less-general than a function)
typealias WorkItem = @Sendable () async throws -> Void

let (stream, continuation) = AsyncStream<WorkItem>.makeStream()

// begin enumerating the sequence with a single Task
// hazard 1: this Task will run at a fixed priority
Task {
    // the sequence guarantees order
    for await workItem in stream {
        try? await workItem()
    }
}

// the continuation provides access to an async context
// Hazard 2: per-work item cancellation is unsupported
continuation.yield({
    // Hazard 3: thrown errors are invisible
    try await work()
})
```
