import XCTest
@testable import Cotabby

final class CorrectionImportParserTests: XCTestCase {
    func testParsesMarkdownAndCommaSeparatedPairs() {
        let input = """
        # Fixes
        - ot -> to
        - im -> I'm
        - Others: nad:and,adn:and,hte:the
        """

        let preview = CorrectionImportParser.parsePlainText(input)

        XCTAssertEqual(preview.rules.map(\.trigger), ["ot", "im", "nad", "adn", "hte"])
        XCTAssertEqual(preview.rules.map(\.replacement), ["to", "I'm", "and", "and", "the"])
        XCTAssertEqual(preview.errorCount, 0)
        XCTAssertGreaterThan(preview.warningCount, 0)
    }

    func testReportsMalformedAndConflictingPairs() {
        let input = """
        form:from
        form:foam
        for i in j: ??
        """

        let preview = CorrectionImportParser.parsePlainText(input)

        XCTAssertEqual(preview.rules.count, 2)
        XCTAssertTrue(preview.issues.contains(where: { $0.message.contains("multiple replacements") }))
        XCTAssertTrue(preview.issues.contains(where: { $0.message.contains("punctuation alone") }))
    }

    func testParsesQuotedCSV() {
        let data = Data("trigger,replacement\n\"get chat\",\"this chat\"\n\"teh\",\"the\"\n".utf8)
        let preview = CorrectionImportParser.parse(data: data, format: .csv)

        XCTAssertEqual(preview.rules.count, 2)
        XCTAssertEqual(preview.rules[0].trigger, "get chat")
        XCTAssertEqual(preview.rules[0].replacement, "this chat")
    }

    func testParsesDictionaryJSON() throws {
        let data = try JSONEncoder().encode(["teh": "the", "nad": "and"])
        let preview = CorrectionImportParser.parse(data: data, format: .json)

        XCTAssertEqual(Set(preview.rules.map(\.trigger)), ["teh", "nad"])
        XCTAssertEqual(preview.errorCount, 0)
    }

    func testExportedDatabaseImportRestoresVocabularyAndLearning() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let database = PersonalCorrectionDatabase(
            rules: [PersonalCorrectionRule(trigger: "teh", replacement: "the")],
            vocabulary: [PersonalVocabularyEntry(word: "Cotabby")],
            learnedCorrections: [LearnedCorrection(
                source: "adn",
                destination: "and",
                languageCode: "en",
                applicationBundleIdentifier: nil,
                acceptedCount: 3,
                revertedCount: 0,
                dismissedCount: 0,
                state: .trusted,
                firstSeenAt: date,
                lastSeenAt: date
            )]
        )
        let encoder = PersonalCorrectionJSONCoding.makeEncoder()

        let preview = CorrectionImportParser.parse(
            data: try encoder.encode(database),
            format: .json
        )

        XCTAssertEqual(preview.rules.map(\.trigger), ["teh"])
        XCTAssertEqual(preview.vocabulary.map(\.word), ["Cotabby"])
        XCTAssertEqual(preview.learnedCorrections.map(\.source), ["adn"])
    }
}
