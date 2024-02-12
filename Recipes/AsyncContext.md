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

This is an extremely common pattern in Swift code: You need to kick off some work from the main thread, complete it in the background, and then update some state back on the main thread. For example, you might need to add a spinner and disable some buttons in the "before" stage, do an expensive computation in the "background" stage, then update the UI again in the "after" stage. Using DispatchQueues, you could write the code like this:

```swift
final class DemoViewController: UIViewController {
    func doWork() {
        // We assume we're on the main thread here
        beforeWorkBegins()

        DispatchQueue.global.async {
            let possibleResult = expensiveWork(arguments)
            
            DispatchQueue.main.async {
                afterWorkIsDone(possibleResult)
            }
        }
    }
}
```

This DispatchQueue pattern provides the following properties:

1. **Ordering**: You know `beforeWorkBegins()` runs before `expensiveWorks()` which runs before `afterWorkIsDone()`.
2. **Thread-safety**: You know `beforeWorkBegins()` and `afterWorkIsDone()` run on the main thread and `expensiveWork()` runs on a background thread.
3. **"Immediacy"**: There is no "waiting" before running `beforeWorkBegins()`.

There are different recipes for recreating this pattern in Swift Concurrency and preserving these properties depending upon:

1. Does an asynchronous wrapper exist for `expensiveWork()`?
2. Does the _immediacy_ property need to be preserved for a synchronous or asynchronous context?

### Solution #1: Asynchronous wrapper exists & "synchronous immediacy"

This recipe assumes there is an asynchronous wrapper for `expensiveWork()` and ensures that `beforeWorkBegins()` runs without any waiting in the caller's synchronous context. 

```swift
final class DemoViewController: UIViewController {
    func doWork() {
        // hazard 1: timing. 
        //
        // If you moved this to inside the `Task`, you'd introduce a "wait" before 
        // executing `beforeWorkBegins()`, losing the "immediacy" property.
        beforeWorkBegins()

        // hazard 2: ordering
        //
        // While this recipe guarantees that `beforeWorkBegins()` happens before
        // `asyncExpensiveWork()`, if there are any **other** Tasks that are
        // created by the caller, there is no ordering guarantees among the tasks.
        // This differs from the DispatchQueue.global.async() world, where blocks
        // are started in the order in which they are submitted to the queue.
        Task {
            // MainActor-ness has been inherited from the creating context.
            // hazard 3: lack of caller control
            // hazard 3: sendability (for both `result and `arguments`)
            let result = await asyncExpensiveWork(arguments)
            // post-await we are now back on the original, MainActor context
            afterWorkIsDone(result)
        }
    }
}
```

### Solution #2: Asynchronous wrapper exists & "asynchronous immediacy"

If all of the callers of `doWork()` are already in asynchronous contexts, or if the callers can easily be made asynchronous (beware the "async virality" hazard), you can use this recipe:

```swift
final class DemoViewController: UIViewController {
    // hazard 1: async virality. Can you reasonably change all callsites to `async`?
    func doWork() async {
        beforeWorkBegins()
        let result = await asyncExpensiveWork(arguments)
        afterWorkIsDone(result)
    }
}
```

This recipe preserves immediacy of `beforeWorkBegins()` for any asynchronous callers and avoids introducing additional unstructured `Task` operations.

### Solution #3: No async wrapper exists for `expensiveWork()`

If there is no `async` wrapper for `expensiveWork()`, you cannot directly use Solutions 1 or 2. 

One option you have: Write your own `async` wrapper, then proceed with Solution 1 or 2!

```swift
func asyncExpensiveWork(arguments: Arguments) async -> Result {
    await withCheckedContinuation { continuation in
        // Hazard: Are you using the appropriate quality of service queue?
        DispatchQueue.global.async {
            let result = expensiveWork(arguments)
            continuation.resume(returning: result)
        }
    }
}
```

Yes, this just sneaks `DispatchQueue.global.async()` into the Swift Concurrency world. However, this seems appropriate: You won't tie up one of the threads in the cooperative thread pool to execute `expensiveWork()`. Another advantage of this approach: It's now baked into the implementation of `asyncExpensiveWork()` that the expensive stuff happens on a background thread. You can't accidentally run the code in the main actor context.

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

### Solution #4: No async wrapper exists and you don't want to write one

```swift
final class DemoViewController: UIViewController {
    func doWork() {
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
