# Sendability

Passing data around across isolation domains means you the types to conform to [Sendable](https://developer.apple.com/documentation/swift/sendable).

## Non-Sendable Arguments

You need to pass some non-Sendable arguments into a function in a different isolution domain.

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
