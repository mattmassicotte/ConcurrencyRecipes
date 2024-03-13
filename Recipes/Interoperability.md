# Interoperability

Using Swift concurrency with other concurrency systems.

## DispatchQueue.async

This is kind of a meme on Apple platforms, and it can be a hack. But sometimes you really do need to just let the runloop turn. Just be sure you have a good rationale for why it is necessary.

```swift
// work before the runloop has turned...

DispatchQueue.main.async {
    // ... and need to do stuff after it has finished...
}

// ... because state out of your control isn't yet right here
```

### Solution #1: Use a continuation

To make this work in an async context, you can use a continuation.

```swift
// work before the runloop has turned...

await withCheckedContinuation { continuation in
    DispatchQueue.main.async {
        continuation.resume()
    }
}

// at this point, you are **guaranteed** that the main runloop has turned at least once
```
