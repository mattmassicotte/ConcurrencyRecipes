import Foundation

public func acceptEscapingBlock(_ block: @escaping () -> Void) {
	DispatchQueue.global().async {
		block()
	}
}

public func unannotatedEscapingSendableBlock(_ block: @escaping @Sendable () -> Void) {
	DispatchQueue.global().async {
		block()
	}
}

@preconcurrency
public func annotatedEscapingSendableBlock(_ block: @escaping @Sendable () -> Void) {
	DispatchQueue.global().async {
		block()
	}
}

public class NonSendableClass {
	var mutableState: Int = 0

	public init() {
	}

	public func accessMutableState() {
		print("state:", mutableState)
	}
}

@preconcurrency
public class AnnotatedNonSendableClass {
	var mutableState: Int = 0

	public init() {
	}

	public func accessMutableState() {
		print("state:", mutableState)
	}
}

public final class SendableClass: Sendable {
	public init() {
	}
}

public protocol NonIsolatedProtocol {
	func nonSendableCallback(callback: @escaping () -> Void)

//	@preconcurrency
	func annotatedNonSendableCallback(callback: @escaping @Sendable () -> Void)
}
