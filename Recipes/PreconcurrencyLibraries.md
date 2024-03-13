# Using Libraries not Designed for Concurrency

You are using a Swift library that wasn't correctly built for Swift concurrency and things are going wrong.

## Capturing Non-Sendable Types

You need to pass a type from this library to a `@Sendable` closure. Just remember, nothing will make this magically safe and you still should be confident you are not introducing data races.

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

This is an easy one. You can just import the library with `@preconcurrency`.

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

This addresses the issue because it forces all accesses to be isolated to a single actor.

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

This is a more-flexible version of #2. Note that is doesn't work as of Swift 5.10, but hopefully will [soon](https://forums.swift.org/t/isolation-assumptions/69514)!.

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

## Protocol Function with Callback

You have a protocol that uses callbacks. These callbacks are not correctly marked with global actors or `@Sendable`.

```Swift
import TheLibrary

class YourClass: LibraryProtocol {
    func protocolFunction(callback: @escaping () -> Void)
        Task {
            // doing your async work here

            // WARNING: Capture of 'callback' with non-sendable type '() -> Void' in a `@Sendable` closure
            callback()
        }
}
```

## Solution #1: `@preconcurrency` + `@Sendable`

If you import the library with `@preconcurrency`, you can adjust your conformance to match the `@Sendable` reality of the function.

```Swift
@preconcurrency import TheLibrary

class YourClass: LibraryProtocol {
    // the callback is documented to actually be ok to call on any thread, so it must be @Sendable. With preconcurrency, this Sendable mismatch is ok.
    func protocolFunction(callback: @escaping @Sendable () -> Void)
        Task {
            // doing your async work here

            callback()
        }
}
```

## Solution #2: `@preconcurrency` + `@Sendable` + `MainActor.run`

Almost the same as #1, but the callback must be run on the main actor. In this case, it is not possible to add `@MainActor` to the conformance, and you have to instead make the isolation manual.

```Swift
@preconcurrency import TheLibrary

class YourClass: LibraryProtocol {
    // the callback is documented to actually be ok to call on any thread, so it must be @Sendable. With preconcurrency, this mismatch is still considered a match.
    func protocolFunction(callback: @escaping @Sendable () -> Void)
        Task {
            // doing your async work here

            // ensure you are back on the MainActor here
            await MainActor.run {
                callback()
            }
        }
}
```

## Converting a completion callback to async

You want to convert a function that uses a callback to async. This is particularly common when interoperating with Objective-C code, and the compiler will even generate async versions of certain patterns automically. But isolation and Sendability can still be a problem.

```swift
func doWork(argument: ArgValue, _ completionHandler: @escaping (ResultValue) -> Void)
```

## Solution #1: plain wrapper

If the arguments (`ArgValue`) and return value (`ResultValue`) are `Sendable`, this is very straightforward. Remember, though, that just putting async on a function without any isolation makes it non-isolated. You must make sure that's compatible with how the function you are wrapping works.

```swift
func doWork() async -> ResultValue {
    await withCheckedContinuation { continuation in
        doWork { value in
            continuation.resume(returning: value)
        }
    }
}
```

## Solution #2: wrapper with non-Sendable return value

A non-Sendable return value can potentially be a showstopper. But, if you do not need the entire object, or can transform it in some way before returning it, you can pull this off.

```swift
func doWork() async -> ResultValue {
    await withCheckedContinuation { continuation in
        doWork { nonSendableValue in
            // within this block, it's safe to synchronously access the non-Sendable value
            let sendableThing = nonSendableValue.partYouReallyNeed
            
            continuation.resume(returning: sendableThing)
        }
    }
}
```
