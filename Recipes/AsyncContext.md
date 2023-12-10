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
func doWork() {}
    // We assume we're on the main thread here
    beforeWorkBegins()

    DispatchQueue.global.async {
        let possibleResult = expensiveWork(arguments)
        
        DispatchQueue.main.async {
            afterWorkIsDone(possibleResult)
        }
    }
}
```

### Solution #1: Someone wrote an `async` wrapper for `expensiveWork()`

If there is an `async` wrapper for `expensiveWork()`, the "background work" recipe is simpler in the world of structured concurrency. This recipe assumes that both `arguments` and `result` are `Sendable` (safe to cross isolation domains). Note this was true in the dispatch-queue based world, too!

```swift
@MainActor
func doWork() async {
    beforeWorkBegins()
    let result = await asyncExpensiveWork(arguments)
    afterWorkIsDone()
}
```

### Solution #2: Write your own async wrapper for `expensiveWork()`

Suppose there isn't an `async` version of `expensiveWork()`, so you can't directly use Solution #1. 

One option: Write your own wrapper, then proceed with Solution #1!

```swift
func asyncExpensiveWork(arguments: Arguments) async -> Result {
    await withCheckedContinuation { continuation in
        DispatchQueue.global.async {
            let result = expensiveWork(arguments)
            continuation.resume(returning: result)
        }
    }
}
```

Yes, this just sneaks `DispatchQueue.global.async()` into the Swift Structured Concurrency world. However, this seems appropriate: You won't tie up one of the threads in the cooperative thread pool to execute `expensiveWork()`. Another advantage of this approach: It's now baked into the implementation of `asyncExpensiveWork()` that the expensive stuff happens on a background thread. You can't accidentally run the code in the main actor context.

**Sidenote** To Swift, `func foo()` and `func foo() async` are different and the compiler knows which one to use depending on if the callsite is a synchronous or asynchronous context. This means your async wrappers can have the same naming as their synchronous counterparts:

```swift
func expensiveWork(arguments: Arguments) async -> Result {
    await withCheckedContinuation { continuation in
        DispatchQueue.global.async {
            let result = expensiveWork(arguments)
            continuation.resume(returning: result)
        }
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
