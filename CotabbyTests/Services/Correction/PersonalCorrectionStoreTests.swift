import XCTest
@testable import Cotabby

final class PersonalCorrectionStoreTests: XCTestCase {
    func testRoundTripsDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("corrections.json")
        let store = PersonalCorrectionStore(fileURL: url)
        let database = PersonalCorrectionDatabase(
            rules: [PersonalCorrectionRule(trigger: "teh", replacement: "the")],
            vocabulary: [PersonalVocabularyEntry(word: "Cotabby")]
        )

        try await store.save(database)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, database)
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadsLegacyISO8601Dates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("corrections.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {
          "learnedCorrections" : [],
          "rules" : [{
            "action" : "automatic",
            "caseMode" : "exact",
            "createdAt" : "2026-09-19T12:00:00Z",
            "id" : "00000000-0000-0000-0000-000000000001",
            "isCaseSensitive" : false,
            "isEnabled" : true,
            "replacement" : "the",
            "scope" : { "kind" : "global" },
            "source" : "manual",
            "trigger" : "teh",
            "updatedAt" : "2026-09-19T12:00:00Z"
          }],
          "version" : 1,
          "vocabulary" : []
        }
        """
        try Data(legacy.utf8).write(to: url)

        let loaded = try await PersonalCorrectionStore(fileURL: url).load()

        XCTAssertEqual(loaded.rules.first?.trigger, "teh")
        try? FileManager.default.removeItem(at: directory)
    }
}
