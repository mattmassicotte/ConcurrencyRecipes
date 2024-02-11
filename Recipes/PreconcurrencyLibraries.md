# Using Libraries not Designed for Concurrency

You are using a Swift library that wasn't correctly built for Swift concurrency and things are going wrong.

## Capturing Non-Sendable Types

You need to pass a type from this library to a `@Sendable` closure.

```Swift
import TheLibrary

func useTheType() {
    let value = TypeFromTheLibrary()

    Task {
        value.doStuff() // WARNING: Capture of 'value' with non-sendable...
    }
}
```

## Solution #1: `@preconcurrency`

This is an easy one. You can just import the library with ``@preconcurrency`. Just remember, this does not make this magically safe and you still should be confident you are not introducing data races.

```Swift
@preconcurrency import TheLibrary

func useTheType() {
    let value = TypeFromTheLibrary()

    Task {
        value.doStuff()
    }
}
```

## Solution #2: use static isolation

```Swift
import TheLibrary

@MainActor
func useTheType() {
    let value = TypeFromTheLibrary()

    Task {
        value.doStuff()
    }
}
```

## Solution #3: use dynamic isolation

Note that is doesn't work as of Swift 5.10, but hopefully will [soon](https://forums.swift.org/t/isolation-assumptions/69514)!.

```Swift
import TheLibrary

func useTheType(isolatedTo actor: any Actor) {
    let value = TypeFromTheLibrary()

    Task {
        value.doStuff()
    }
}
```

## Initializing Static Variables

You need to use a type from this library to initialize a static variable.

```Swift
import TheLibrary

class YourClass {
    static let value = TypeFromTheLibrary() // WARNING: Static property 'value' is not concurrency-safe...
}
```

## Solution #1: `nonisolated(unsafe)`

This construct was introduced specifically to handle this situation. It's worth noting that `@preconcurrency import` does affect this behavior: it will suppress any **errors** related to isolation checking by turning them into warnings.

```Swift
import TheLibrary

class YourClass {
    nonisolated(unsafe) static let value = TypeFromTheLibrary()
}
```
