# Protocols

Protocols are widely used in Swift APIs, but can present unique challenges with concurrency.

## Non-isolated Protocol

You have a non-isolated protocol, but need to add conformance to an actor-isolated type.

```swift
protocol MyProtocol {
    func doThing(argument: ArgumentType) -> ResultType
}

@MainActor
class MyClass {
}

extension: MyClass: MyProtocol {
    func doThing(argument: ArgumentType) -> ResultType {
    }
}
```

### Solution #1: non-isolated conformance

```swift
extension: MyClass: MyProtocol {
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

If the protocol is under your control, you can make it actor-compatible
by making all functions async.

```swift
protocol MyProtocol {
    func doThing(argument: String) async -> Int
}

actor MyClass: MyProtocol {
    func doThing(argument: String) -> Int {
        return 42
    }
}
```
