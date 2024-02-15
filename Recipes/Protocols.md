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

### Solution #4: don't use a protocol

This is not a joke! If you are in control of both the protocol and all of its usage, functions may be able to serve the same purpose. A good example of this is a delegate pattern.

```swift
// example protocol/consumer pair
protocol MyClassDelegate: AnyObject {
    func doThings()
}

class MyClass {
    weak var delegate: MyClassDelegate?
}

// problematic usage:
@MainActor
class MyUsage {
    let myClass: MyClass
    
    init() {
        self.myClass = MyClass()
        
        myClass.delegate = self
    }
}

extension MyUsage: MyClassDelegate {
    // this needs to be non-isolated
    nonisolated func doThings() {
    }
}
```

Contrast this with a function-based implementation. This provides very flexible isolation - can work with a `MainActor` type but also a plain actor.

```swift
class MyClass {
    var doThings: () -> Void = {}
}

actor MyUsage {
    let myClass: MyClass

    init() {
        self.myClass = MyClass()

        myClass.doThings = { [unowned self] in
            // accessing self is fine here because `doThings` is not Sendable
            print(self)
        }
    }
}
```

## Non-isolated Init Requirement

You need to satisfy an initializer requirement in a non-isolated protocol with an isolated type. This is a particularly tricky special-case of the problem above if you need to initialize instance variables.

All credit to [Holly Borla](https://forums.swift.org/t/complete-checking-with-an-incorrectly-annotated-init-conformance/69955/6) for the solutions here.

```swift
protocol MyProtocol {
    init()
}

@MainActor
class MyClass: MyProtocol {
    let value: NonSendable
    
    // WARNING: Main actor-isolated initializer 'init()' cannot be used to satisfy nonisolated protocol requirement
    init() {
        self.value = NonSendable()
    }
}
```

### Solution #1: non-isolated conformance + SE-0414

The solution below **will** work once [Region-Based Isolation](https://github.com/apple/swift-evolution/blob/main/proposals/0414-region-based-isolation.md) is available. But, right now it will still produce a warning.

```swift
@MainActor
class MyClass: MyProtocol {
    let value: NonSendable
    
    required nonisolated init() {
        // WARNING: Main actor-isolated property 'value' can not be mutated from a non-isolated context
        self.value = NonSendable()
    }
}
```

### Solution #2: unchecked Sendable transfer

This solution resorts to an `@unchecked Sendable` wrapper to transfer the value across domains. You can see why Region-Based Isolation is so nice, as this solution is pretty ugly.

```swift
struct Transferred<T>: @unchecked Sendable {
  let value: T
}

@MainActor
class MyClass: MyProtocol {
    private let _value: Transferred<NonSendable>
    var value: NonSendable { _value.value }
    
    required nonisolated init() {
        self._value = Transferred(value: NonSendable())
    }
}
```

### Solution #3: property wrapper

This is a nicer and more-reusable version of #2. By setting up an `@unchecked Sendable` as a property wrapper you can reduce some of the boilerplate.

```swift
@propertyWrapper
struct InitializerTransferred<Value>: @unchecked Sendable {
    let wrappedValue: Value

    init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

@MainActor
class MyClass: MyProtocol {
    @InitializerTransferred private(set) var value: NonSendable
    
    required nonisolated init() {
        sself._value = InitializerTransferred(NonSendable())
    }
}
```
