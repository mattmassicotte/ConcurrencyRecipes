# Async Contexts

Virtually all programs needs to make at least one transition from a synchronous context to an asynchronous one.

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

### Soultion #2: the work must be synchronous

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
