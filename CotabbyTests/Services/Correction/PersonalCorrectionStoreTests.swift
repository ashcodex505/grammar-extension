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
}
