import XCTest
@testable import Cotabby

final class PersonalCorrectionIndexTests: XCTestCase {
    func testStarterRulesContainTheProvidedCorrectionsWithoutDuplicateTriggers() {
        let rules = PersonalCorrectionDefaults.rules
        let replacements = Dictionary(uniqueKeysWithValues: rules.map { ($0.trigger, $0.replacement) })

        XCTAssertEqual(replacements.count, rules.count)
        XCTAssertEqual(replacements["ot"], "to")
        XCTAssertEqual(replacements["im"], "I'm")
        XCTAssertEqual(replacements["cottaby"], "Cotabby")
        XCTAssertEqual(replacements["get chat"], "this chat")
        XCTAssertEqual(replacements["thx"], "thanks.")
        XCTAssertTrue(rules.allSatisfy { $0.source == .bundledStarter })
    }

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

    func testApplicationRuleWinsOverGlobalRuleForSameTrigger() {
        let index = PersonalCorrectionIndex(database: PersonalCorrectionDatabase(rules: [
            PersonalCorrectionRule(trigger: "teh", replacement: "the"),
            PersonalCorrectionRule(
                trigger: "teh",
                replacement: "technical",
                scope: .application("com.example.Editor")
            )
        ]))

        XCTAssertEqual(
            index.committedMatch(
                precedingText: "teh ",
                bundleIdentifier: "com.example.Editor"
            )?.replacementText,
            "technical"
        )
        XCTAssertEqual(index.committedMatch(precedingText: "teh ", bundleIdentifier: nil)?.replacementText, "the")
    }

    func testLearnedStateControlsOfferAutomaticAndBlockedPairs() {
        let date = Date(timeIntervalSince1970: 1)
        let index = PersonalCorrectionIndex(database: PersonalCorrectionDatabase(learnedCorrections: [
            LearnedCorrection(
                source: "adn",
                destination: "and",
                languageCode: nil,
                applicationBundleIdentifier: "com.example.Editor",
                acceptedCount: 2,
                revertedCount: 0,
                dismissedCount: 0,
                state: .suggestionOnly,
                firstSeenAt: date,
                lastSeenAt: date
            ),
            LearnedCorrection(
                source: "hte",
                destination: "the",
                languageCode: nil,
                applicationBundleIdentifier: "com.example.Editor",
                acceptedCount: 3,
                revertedCount: 0,
                dismissedCount: 0,
                state: .trusted,
                firstSeenAt: date,
                lastSeenAt: date
            ),
            LearnedCorrection(
                source: "form",
                destination: "from",
                languageCode: nil,
                applicationBundleIdentifier: "com.example.Editor",
                acceptedCount: 1,
                revertedCount: 2,
                dismissedCount: 0,
                state: .blocked,
                firstSeenAt: date,
                lastSeenAt: date
            )
        ]))

        XCTAssertEqual(
            index.committedLearnedMatch(
                precedingText: "adn ",
                bundleIdentifier: "com.example.Editor"
            )?.action,
            .offer
        )
        XCTAssertEqual(
            index.committedLearnedMatch(
                precedingText: "hte ",
                bundleIdentifier: "com.example.Editor"
            )?.action,
            .automatic
        )
        XCTAssertTrue(index.blocks(
            source: "Form",
            destination: "From",
            bundleIdentifier: "com.example.Editor"
        ))
        XCTAssertFalse(index.blocks(source: "form", destination: "from", bundleIdentifier: nil))
    }
}
