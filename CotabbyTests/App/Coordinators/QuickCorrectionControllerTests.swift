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

    @MainActor
    func testUpsertUpdatesAnExistingRuleWithoutCreatingADuplicate() {
        let store = PersonalCorrectionStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("corrections.json")
        )
        let model = PersonalCorrectionModel(store: store)
        model.upsertRule(PersonalCorrectionRule(trigger: "teh", replacement: "the"))
        let originalID = model.database.rules.first?.id

        model.upsertRule(PersonalCorrectionRule(trigger: "TEH", replacement: "The"))

        XCTAssertEqual(model.database.rules.count, 1)
        XCTAssertEqual(model.database.rules.first?.id, originalID)
        XCTAssertEqual(model.database.rules.first?.replacement, "The")
    }
}
