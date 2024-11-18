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

## Non-isolated NSObjectProtocol-inheriting Protocol

This is similar to the above problem, but with the significant constraint that the type conforming to the protocol must inherit from `NSObject`. You can use all of the same solutions, with the exception of an actor type, which cannot inherit from anything.

```swift
actor MyActor {}

// ERROR: ... 'MyActor' should inherit 'NSObject' instead ...
extension MyActor: URLSessionDelegate {
}
```

## Solution #1: Functional Proxy

This solution works for objects that strongly retain their delegates. `URLSession` does, but I'm sure there are many examples types that do not.

```swift
// first, make a simple type that conforms to the NSObjet-based protocol
final class URLSessionDelegateProxy: NSObject {
    var eventsFinished: () -> Void = { }
}

extension URLSessionDelegateProxy: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        eventsFinished()
    }
}

// Use the proxy as a stand-in
actor MyActor {
    private let session: URLSession

    init() {
        let proxy = URLSessionDelegateProxy()

        self.session = URLSession(configuration: .default, delegate: proxy, delegateQueue: nil)

        // once self has been fully, initialized, assign the callbacks
        proxy.eventsFinished = {
            Task { await self.eventsFinished() }
        }
    }
    
    private func eventsFinished() {
    }
}
```

## Solution #2: Event Sequence

Solution #1 doesn't work any more for `URLSessionDelegate`, because it now requires a `Sendable` type. If you do not have to return values any values, this can work.

```swift
final class URLSessionDelegateProxy: NSObject {
    enum Event: Sendable {
        case didFinishEvents
    }

    private let streamPair = AsyncStream<Event>.makeStream()

    public var eventStream: AsyncStream<Event> {
        streamPair.0
    }
}

extension URLSessionDelegateProxy: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        streamPair.1.yield(.didFinishEvents)
    }
}

// Use the proxy as a stand-in
actor MyActor {
    private let session: URLSession

    init() {
        let proxy = URLSessionDelegateProxy()

        self.session = URLSession(configuration: .default, delegate: proxy, delegateQueue: nil)

        // once self has been fully, initialized, consume the events
        Task { [weak self] in
        for await event in proxy.eventStream {
            // don't forget to be careful with self's lifetime here
            guard let self else { break }

            switch event {
            case .didFinishEvents:
                await self.finishedEvents()
            }
        }
    }
    
    private func eventsFinished() {
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

## Static Variables

You want to conform to a protocol that requires a **non-isolated** static let property. This can be really tricky to handle. This comes up a lot with SwiftUI's `EnvironmentKey` and `PreferenceKey`.

```swift
// for reference, here's how EnvironmentKey is defined
public protocol EnvironmentKey {
    associatedtype Value

    static var defaultValue: Self.Value { get }
}

class NonSendable {
}

struct MyKey: EnvironmentKey {
    // WARNING: Static property 'defaultValue' is not concurrency-safe because it is not
    // either conforming to 'Sendable' or isolated to a global actor; this is an error in Swift 6
    static let defaultValue = NonSendable()
}
```

### Solution #1: MainActor + non-isolated init

This solution took me a while to even fully understand. Adding `MainActor` establishes isolation, making the type Sendable. But, that also means the now `MainActor`-isolated init cannot be used at the definition site. Remember, `defaultValue` is non-isolated. If your type doesn't need to reference other `MainActor`-isolated types in its init, which is surprisingly common, this will work well.

```swift
@MainActor
class NonSendable {
    nonisolated init() {
    }
}

struct MyKey: EnvironmentKey {
    // This is now ok because:
    // a) our type is globally-isolated (and that means Sendable)
    // b) the init can be called from a non-isolated context
    static let defaultValue = NonSendable()
}
```

### Solution #2: MainActor + non-isolated init + default values

A non-isolated `init` can be hard to create when the type involves non-Sendable properties. Sometimes you can work around this by using default property values.

```swift
@MainActor
class NonSendable {
    // this is MainActor-only
    private var value = AnotherNonSendable()

    nonisolated init() {
        // ok because self's isolated properties are not accessed
    }
}
```

### Solution #3: Define a read-only accessor

Instead of trying to share a single non-Sendable value, create a new one on each access. This can work really well if the value is not accessed frequently and distinct instances make sense for your usage.

```swift
struct MyKey: EnvironmentKey {
    static var defaultValue: NonSendable { NonSendable() }
}
```

### Solution #4: nonisolated(unsafe) Optional

If you happen to be storing an optional value, you can safely cheat **if** you want to initialize the value to nil. But, you have to be careful here. It is very unusual for instances of a type to differ in thread-safety. This is just a very special case.

```swift
struct MyKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: NonSendable? = nil
}
```
