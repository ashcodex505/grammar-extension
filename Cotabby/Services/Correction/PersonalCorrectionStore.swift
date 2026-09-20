import Foundation

/// Serializes the user-owned correction database to Application Support. The store is an actor so
/// file I/O and read-modify-write transactions cannot race; the typing path never calls it directly
/// and instead consumes an immutable in-memory index published by `PersonalCorrectionModel`.
nonisolated actor PersonalCorrectionStore {
    enum StoreError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case let .unsupportedVersion(version):
                return "Correction database version \(version) is newer than this version of Cotabby supports."
            }
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func hasStoredDatabase() -> Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func load() throws -> PersonalCorrectionDatabase {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PersonalCorrectionDatabase()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let database = try decoder.decode(PersonalCorrectionDatabase.self, from: data)
        guard database.version <= PersonalCorrectionDatabase.currentVersion else {
            throw StoreError.unsupportedVersion(database.version)
        }
        return database
    }

    func save(_ database: PersonalCorrectionDatabase) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: [.atomic])
    }

    func exportData(_ database: PersonalCorrectionDatabase) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(database)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.cotabby.app"
        return root
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("PersonalCorrections.json", isDirectory: false)
    }
}
