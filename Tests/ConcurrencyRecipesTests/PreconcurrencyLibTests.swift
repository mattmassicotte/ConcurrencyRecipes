import XCTest
import PreconcurrencyLib
//@preconcurrency import PreconcurrencyLib

final class PreconcurrencyLibTests: XCTestCase {
	func testAcceptEscapingBlock() {
		let ns = NonSendableClass()

		acceptEscapingBlock {
			print("hello")

			// no warning because this block isn't sendable
			ns.accessMutableState()
		}
	}

	func testUnannotatedEscapingSendableBlock() {
		let ns = NonSendableClass()

		unannotatedEscapingSendableBlock {
			print("hello")

			// warning, block is now Sendable
			ns.accessMutableState()
		}
	}

	func testAnnotatedEscapingSendableBlock() {
		let ns = NonSendableClass()

		annotatedEscapingSendableBlock {
			print("hello")

			// warning, block is now Sendable
			ns.accessMutableState()
		}

		DispatchQueue.global().async {
			ns.accessMutableState()
		}
	}

	func testAccessNonSendableClass() {
		let ns = NonSendableClass()

		DispatchQueue.global().async {
			ns.accessMutableState()
		}
	}

	func testAnnotatedAccessNonSendableClass() {
		let ns = AnnotatedNonSendableClass()

		DispatchQueue.global().async {
			ns.accessMutableState()
		}
	}
}

extension PreconcurrencyLibTests {
	static let nonSendableConstant = NonSendableClass()
	static let annotatedNonSendableConstant = AnnotatedNonSendableClass()
	static let sendableContant = SendableClass()

	nonisolated(unsafe) static let unsafeSendableContant = SendableClass()
	nonisolated(unsafe) static let unsafeNonSendableConstant = NonSendableClass()
}

@MainActor
final class AdoptNonIsolatedProtocol: NonIsolatedProtocol {
	func work() async {

	}

	nonisolated func nonSendableCallback(callback: @escaping @Sendable () -> Void) {
		Task {
			await self.work()
			callback()
		}
	}

	nonisolated func annotatedNonSendableCallback(callback: @escaping @Sendable () -> Void) {
		Task {
			await self.work()

			await MainActor.run {
				callback()
			}
		}
	}
}
