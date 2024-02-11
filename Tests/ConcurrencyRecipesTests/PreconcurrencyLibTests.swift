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

class YourClass {
	static let nonSendableConstant = NonSendableClass()
}

func useTheType(isolatedTo actor: any Actor) {
	let value = NonSendableClass()

	Task {
		_ = actor
		value.accessMutableState()
	}
}
