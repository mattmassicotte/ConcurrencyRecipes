# SwiftUI

SwiftUI has a lot of built-in support for concurrency.

## Non-MainActor Isolation

SwiftUI's [`View`](https://developer.apple.com/documentation/swiftui/view) type does not enforce whole-type isolation. Instead, just the `body` property is `MainActor`-isolated. This can make `View` subtypes very tricky to use. Races and incorrect isolation are common.

### Solution #1: Just use MainActor

Just slap an `@MainActor` on there to make things much easier.

```swift
@MainActor
struct MyView: View {
    var body: some View {
        Text("Body")
    }
}
```

### Solution #2: Override View

This is a little more radical of a solution, but can save lots of typing. Swift makes it possible to override entire types within a module. So, you'd have to do this in any module directly, but it certainly does reduce the amount of boilerplate. I'd be a little careful with this one, but it is also ok to add redundant global actor annotations, so at least it is trivial to remove.

```swift
// do this once
@MainActor
protocol View: SwiftUI.View {
    @ViewBuilder
    var body: Self.Body { get }
}

// inherit MainActor isolation within the same module
struct MyView: View {
    var body: some View {
        Text("Body")
    }
}
```
