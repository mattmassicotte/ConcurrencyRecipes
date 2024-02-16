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

You need to isolation things differently depending on usage.

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