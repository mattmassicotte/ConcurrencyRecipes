# Protocols

Protocols are widely used in Swift APIs, but can present unique challenges with concurrency.

## Non-isolated Protocol

You have a non-isolated protocol, but need to add conformance to an MainActor-isolated type.

```swift
protocol MyProtocol {
    func doThing(argument: ArgumentType) -> ResultType
}

@MainActor
class MyClass {
}

extension MyClass: MyProtocol {
    func doThing(argument: ArgumentType) -> ResultType {
    }
}
```

### Solution #1: non-isolated conformance

```swift
extension MyClass: MyProtocol {
    nonisolated func doThing(argument: ArgumentType) -> ResultType {
        // at this point, you likely need to interact with self, so you must satisfy the compiler
        // hazard 1: Availability
        MainActor.assumeIsolated {
            // here you can safely access `self`
        }
    }
}
```

### Solution #2: make the protocol async

If the protocol is under your control, you can make it compatible by making all functions async.

```swift
protocol MyProtocol {
    // hazard 1: Async Virality (for other conformances)
    func doThing(argument: String) async -> Int
}

@MainActor
class MyClass: MyProtocol {
    // hazard 2: Async Virality (for callers)
    func doThing(argument: String) async -> Int {
        return 42
    }
}
```

### Solution #3: non-isolated actor conformance

You can also use a variant of solution #1 to add conformance to an non-Main actor. This does come with limitations. Particular caution should be used if this protocol comes from Objective-C. It is common for Objective-C code to be incorrectly or insufficiently annotated, and that can result in violations of the Swift concurrency invariants. In other words, deadlocks and isolation failure (which will produce crashes, you **hope**).

```swift
protocol NotAsyncFriendly {
    func informational()

    func takesSendableArguments(_ value: Int)

    func takesNonSendableArguments(_ value: NonSendableType)

    func expectsReturnValues() -> Int
}

actor MyActor {
    func doIsolatedThings(with value: Int) {
        ...
    }
}

extension MyActor: NotAsyncFriendly {
    // purely informational calls are the easiest
    nonisolated func informational() {
        // hazard: ordering
        // the order in which these informational messages are delivered may be important, but is now lost
        Task {
            await self.doIsolatedThings(with: 0)
        }
    }

    nonisolated func takesSendableArguments(_ value: Int) {
        // hazard: ordering
        Task {
            // we can safely capture and/or make use of value here because it is Sendable
            await self.doIsolatedThings(with: value)
        }
    }
    
    nonisolated func takesNonSendableArguments(_ value: NonSendableType) {
        // hazard: sendability

        // any action taken would have to either not need the actor's isolated state or `value`.
        // That's possible, but starting to get tricky.
    }

    nonisolated func expectsReturnValues() -> Int {
        // hazard: sendability

        // Because this function expects a synchronous return value, the actor's isolated state
        // must not be needed to generate the return. This is also possible, but is another indication
        // that an actor might be the wrong option.
        
        return 42
    }
}
```
