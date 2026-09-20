import XCTest
@testable import Cotabby

final class PersonalCorrectionIndexTests: XCTestCase {
    func testMatchesSingleCharacterAndPhraseRulesOnlyAfterSpace() {
        let index = PersonalCorrectionIndex(database: PersonalCorrectionDatabase(rules: [
            PersonalCorrectionRule(trigger: "u", replacement: "you"),
            PersonalCorrectionRule(trigger: "get chat", replacement: "this chat")
        ]))

        XCTAssertEqual(index.committedMatch(precedingText: "hello u ", bundleIdentifier: nil)?.replacementText, "you")
        XCTAssertEqual(
            index.committedMatch(precedingText: "please get chat ", bundleIdentifier: nil)?.replacementText,
            "this chat"
        )
        XCTAssertNil(index.committedMatch(precedingText: "hello u", bundleIdentifier: nil))
    }

    func testUsesLongestRuleAndHonorsBoundary() {
        let index = PersonalCorrectionIndex(database: PersonalCorrectionDatabase(rules: [
            PersonalCorrectionRule(trigger: "chat", replacement: "conversation"),
            PersonalCorrectionRule(trigger: "get chat", replacement: "this chat"),
            PersonalCorrectionRule(trigger: "im", replacement: "I'm")
        ]))

        XCTAssertEqual(index.committedMatch(precedingText: "get chat ", bundleIdentifier: nil)?.matchedText, "get chat")
        XCTAssertNil(index.committedMatch(precedingText: "time ", bundleIdentifier: nil))
    }

    func testVocabularyRespectsCaseAndApplicationScope() {
        let index = PersonalCorrectionIndex(database: PersonalCorrectionDatabase(vocabulary: [
            PersonalVocabularyEntry(word: "Cotabby"),
            PersonalVocabularyEntry(
                word: "WidgetX",
                scope: .application("com.example.Editor"),
                isCaseSensitive: true
            )
        ]))

        XCTAssertTrue(index.acceptsVocabulary("cotabby", bundleIdentifier: nil))
        XCTAssertTrue(index.acceptsVocabulary("WidgetX", bundleIdentifier: "com.example.Editor"))
        XCTAssertFalse(index.acceptsVocabulary("widgetx", bundleIdentifier: "com.example.Editor"))
        XCTAssertFalse(index.acceptsVocabulary("WidgetX", bundleIdentifier: "com.example.Other"))
    }
}
