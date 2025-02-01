# Isolation

Passing data around across isolation domains means you need the types to conform to [Sendable](https://developer.apple.com/documentation/swift/sendable).

## Non-Sendable Arguments

You need to pass some non-Sendable arguments into a function in a different isolation domain.

```swift
func myAsyncFunction(_ nonSendable: NonSendable) async {
}

let nonSendable = NonSendable()

// this produces a warning
await myAsyncFunction(nonSendable)
```

### Solution #1: create data in a closure

Assumption: the definition is under your control.

```swift
func myAsyncFunction(_ nonSendable: @Sendable () -> NonSendable) async {
}

await myAsyncFunction({ NonSendable() })
```

## Variable Actor Isolation

You need to isolate things differently depending on usage.

```swift
func takesClosure(_ block: () -> Void) {
}

takesClosure {
    accessMainActorOnlyThing()
}
```

### Solution #1: assumeIsolated

We've seen this one before when working with protocols.

```swift
func takesClosure(_ block: () -> Void) {
}

takesClosure {
    MainActor.assumeIsolated {
        accessMainActorOnlyThing()
    }
}
```

### Solution #2: actor-specific version

If you find yourself doing this a lot or you are just not into the nesting, you can make wrapper.

```swift
func takesMainActorClosure(_ block: @MainActor () -> Void) {
    takesClosure {
        MainActor.assumeIsolated {
            block()
        }
    }
}

takesMainActorClosure {
    accessMainActorOnlyThing()
}
```

### Solution #3: isolated parameter

```swift
func takesClosure(isolatedTo actor: isolated any Actor, block: () -> Void) {
}
```

## Custom Global Actors

There are situations where you need to manage a whole bunch of global state all together. In a case like that, a custom global actor can be useful.

## Making an Actor

```swift
@globalActor
public actor CustomGlobalActor {
    public static let shared = CustomGlobalActor()

    // I wanted to do something like MainActor.assumeIsolated, but it turns out every global actor has to implement that manually. This is because
    // it isn't possible to express a global actor assumeIsolated generically. So I just copied the sigature from MainActor.
    public static func assumeIsolated<T>(_ operation: @CustomGlobalActor () throws -> T, file: StaticString = #fileID, line: UInt = #line) rethrows -> T {
        // verify that we really are in the right isolation domain
        Self.shared.assertIsolated()

        // use some tricky casting to remove the global actor so we can execute the closure
        return try withoutActuallyEscaping(operation) { fn in
            try unsafeBitCast(fn, to: (() throws -> T).self)()
        }
    }
}
```

## Async Methods on Non-Sendable Types

Non-`Sendable` types  **can** participate in concurrency. But, because `self` cannot cross isolation domains, it's easy to accidentally make the type unusable from an isolated context.

```swift
class NonSendableType {
    func asyncFunction() async {
    }
}

@MainActor
class MyMainActorClass {
    // this value is isolated to the MainActor
    let value = NonSendableType()

    func useType() async {
        // here value is being transferred from the MainActor to a non-isolated
        // context. That's not allowed.
        // ERROR: Sending 'self.value' risks causing data races
        await value.asyncFunction()
    }
}
```

### Solution #1: isolated parameter

```swift
class NonSendableType {
    func asyncFunction(isolation: isolated (any Actor)? = #isolation) async {
    }
}

@MainActor
class MyMainActorClass {
    // this value is isolated to the MainActor
    let value = NonSendableType()

    func useType() async {
        // the compiler now knows that isolation does not change for
        // this call, which makes it possible.
        await value.asyncFunction()
    }
}
```
