import XCTest
@testable import Cotabby

final class QuickCorrectionControllerTests: XCTestCase {
    func testDraftNormalizesSelectedPhrasesAndReplacement() {
        let draft = QuickCorrectionDraft(selectedText: "  get   chat\nnow  ")

        XCTAssertEqual(draft?.trigger, "get chat now")
        XCTAssertEqual(draft?.normalizedReplacement("  this   chat  now "), "this chat now")
    }

    func testDraftRejectsEmptyAndOversizedValues() {
        XCTAssertNil(QuickCorrectionDraft(selectedText: " \n "))
        XCTAssertNil(QuickCorrectionDraft(
            selectedText: String(repeating: "a", count: QuickCorrectionDraft.maximumCharacterCount + 1)
        ))

        let draft = QuickCorrectionDraft(selectedText: "teh")
        XCTAssertNil(draft?.normalizedReplacement("   "))
        XCTAssertNil(draft?.normalizedReplacement(
            String(repeating: "b", count: QuickCorrectionDraft.maximumCharacterCount + 1)
        ))
    }

}
