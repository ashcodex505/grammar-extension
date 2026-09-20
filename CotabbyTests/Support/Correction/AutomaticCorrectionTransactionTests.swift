import XCTest
@testable import Cotabby

final class AutomaticCorrectionTransactionTests: XCTestCase {
    func testBuildsUndoPlanOnlyForMatchingFieldAndSuffix() {
        let context = CotabbyTestFixtures.focusedInputSnapshot(
            bundleIdentifier: "com.example.Editor",
            elementIdentifier: "field-1",
            precedingText: "hello the ",
            focusChangeSequence: 7
        )
        let transaction = AutomaticCorrectionTransaction(
            originalText: "teh",
            replacementText: "the",
            bundleIdentifier: "com.example.Editor",
            elementIdentifier: "field-1",
            focusChangeSequence: 7
        )

        XCTAssertEqual(
            transaction.undoPlan(for: context),
            TypoCorrectionReplacement(deletingUTF16Count: 4, replacementText: "teh")
        )
    }

    func testRejectsStaleSuffix() {
        let context = CotabbyTestFixtures.focusedInputSnapshot(
            bundleIdentifier: "com.example.Editor",
            elementIdentifier: "field-1",
            precedingText: "hello the next",
            focusChangeSequence: 7
        )
        let transaction = AutomaticCorrectionTransaction(
            originalText: "teh",
            replacementText: "the",
            bundleIdentifier: "com.example.Editor",
            elementIdentifier: "field-1",
            focusChangeSequence: 7
        )

        XCTAssertNil(transaction.undoPlan(for: context))
    }
}
