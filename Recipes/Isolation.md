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

## Custom Global Actors

There are situations where you need to manage a whole bunch of global state all together. In a case like that, a custom global actor can be useful.

## Making an Actor

What I've done here is mak a custom actor that isolates all accesses via a single thread with a runloop established. This is handy for interfacing with legacy runloop-only APIs. But fair warning: I have not tested this very much.

```swift
/// I *think* this is actually only using safe methods on `RunLoop`.
final class ThreadExecutor: SerialExecutor, @unchecked Sendable {
    let thread: Thread
    let runloop: RunLoop
    
    init(name: String) {
        self.runloop = RunLoop()
        
        self.thread = Thread(block: { [runloop] in
            runloop.run()
        })
        
        thread.name = name
    }
    
    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let unownedExecutor = asUnownedSerialExecutor()
        
        runloop.perform {
            unownedJob.runSynchronously(on: unownedExecutor)
        }
    }
}

@globalActor
public actor CustomGlobalActor {
    public static let shared = CustomGlobalActor()
    
    private nonisolated let executor: ThreadExecutor
    
    init() {
        self.executor = ThreadExecutor(name: String(describing: Self.self))
    }
    
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    
    /// This is really annoying, but it isn't possible to express a global actor assumeIsolated generically.
    public static func assumeIsolated<T>(_ operation: @CustomGlobalActor () throws -> T, file: StaticString = #fileID, line: UInt = #line) rethrows -> T {
        Self.shared.assertIsolated()
        
        return try withoutActuallyEscaping(operation) { fn in
            try unsafeBitCast(fn, to: (() throws -> T).self)()
        }
    }
    }
```
