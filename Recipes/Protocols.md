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

### Solutions #3: Create a wrapper around the protocol
If the protocol you want to confirm to is not under your control, and the protocol is non-isolated, you can create a non-concurrent wrapper around the protocol and then create an async protocol for your actor. For example, URLSession delegates that are not async.
E.g:

```swift
// This could also be an actor instead of a class.
@MainActor
class MyClass {
    var myClassProperty = "pew"
    let someObject: Object

    init() {
        someObject = Object()
        someObject.delegate = self // <----- We want to use the object delegate calls
    }
}

extension MyClass: ObjectNonConcurrentDelegate { // <------- Not the best way ❗
    // ERROR!: You would need to mark the method nonisolated like Solution #1.
    // But sometimes we would need to access our class properites, which means we would
    // be accessing our actor from outside the actor system and this could lead to
    // data races and threading issues, which is what we want to avoid
    // when we use actors in the first place!
    nonisolated func someMethod() {
        myClassProperty = "blob"
    }
}

// Wrapper Solution 👇🏼
protocol MyWrapperConcurrentDelegate {
    func someConcurrentMethod() async
}

class MyObjectWrapper: ObjectNonConcurrentDelegate {

    weak var concurrentDelegate: MyWrapperConcurrentDelegate?
    let someObject: Object

    init() {
        someObject = Object()
        someObject.delegate = self
    }

    func someMethod() {
        // Async Context hazards
        /// see AsyncContext Recipe
        Task {
            concurrentProtocol?.someConcurrentMethod()
        }
    }
}

@MainActor
class MyClass {
    var myClassProperty = "pew"
    let wrapperObject: MyObjectWrapper

    init() {
        wrapperObject = MyObjectWrapper()
        wrapperObject.concurrentDelegate = self
    }
}

extension MyClass: MyWrapperConcurrentDelegate {
    func someConcurrentMethod() async {
        // Safe to access our property because we are now
        // in a concurrent context!
        myClassProperty = "blob"
    }
}
```
This solution might not be the best, but it's the safest I have found to ensure thread safety in the actor and avoid data races from nonisolated methods.
