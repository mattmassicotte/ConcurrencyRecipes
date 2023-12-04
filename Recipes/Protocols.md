# Protocols

Protocols are widely used in Swift APIs, but can present unique challenges with concurrency.

## Non-isolated Protocol

You have a non-isolatd protocol, but need to add conformance to an actor-isolated type.

```swift
protocol MyProtocol {
    func doThing(arugment: ArgumentType) -> ResultType
}

@MainActor
class MyClass {
}

extension: MyClass: MyProtocol {
    func doThing(arugment: ArgumentType) -> ResultType {
    }
}
```

### Solution #1: nonisolated conformance

```swift
extension: MyClass: MyProtocol {
    nonisolated func doThing(arugment: ArgumentType) -> ResultType {
        // at this point, you likely need to interact with self, so you must satisfy the compiler
        // hazard 1: Availability
        MainActor.assumeIsolated {
            // here you can safely access `self`
        }
    }
}
```
