import Foundation

/// One user-owned replacement rule. Unlike a spelling suggestion, a rule is an explicit contract:
/// when its trigger matches at a committed text boundary, Cotabby uses the configured replacement
/// even if macOS considers the trigger a valid word (for example `form` -> `from`).
nonisolated struct PersonalCorrectionRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Action: String, Codable, CaseIterable, Sendable {
        case automatic
        case offer
    }

    enum CaseMode: String, Codable, CaseIterable, Sendable {
        /// Preserve the replacement exactly as entered. This is required for contractions and brand
        /// names such as `im` -> `I'm` and `cottaby` -> `Cotabby`.
        case exact
        /// Transfer all-uppercase or leading-capital casing from the trigger to the replacement.
        case transfer
    }

    enum Source: String, Codable, Sendable {
        case manual
        case imported
        case bundledStarter
        case learned
        case macOSTextReplacement
    }

    struct Scope: Codable, Equatable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case global
            case application
        }

        var kind: Kind
        var value: String?

        static let global = Scope(kind: .global, value: nil)

        static func application(_ bundleIdentifier: String) -> Scope {
            Scope(kind: .application, value: bundleIdentifier)
        }

        func matches(bundleIdentifier: String?) -> Bool {
            switch kind {
            case .global:
                return true
            case .application:
                return value == bundleIdentifier
            }
        }
    }

    var id: UUID
    var trigger: String
    var replacement: String
    var languageCode: String?
    var scope: Scope
    var isCaseSensitive: Bool
    var caseMode: CaseMode
    var action: Action
    var source: Source
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        trigger: String,
        replacement: String,
        languageCode: String? = nil,
        scope: Scope = .global,
        isCaseSensitive: Bool = false,
        caseMode: CaseMode = .exact,
        action: Action = .automatic,
        source: Source = .manual,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.trigger = Self.normalizedDisplayText(trigger)
        self.replacement = Self.normalizedDisplayText(replacement)
        self.languageCode = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.scope = scope
        self.isCaseSensitive = isCaseSensitive
        self.caseMode = caseMode
        self.action = action
        self.source = source
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Stable lookup key used by the in-memory suffix index and import conflict detection.
    var normalizedTrigger: String {
        Self.lookupKey(for: trigger, caseSensitive: isCaseSensitive)
    }

    var tokenCount: Int {
        trigger.split(whereSeparator: \.isWhitespace).count
    }

    static func lookupKey(for value: String, caseSensitive: Bool) -> String {
        let normalized = normalizedDisplayText(value).precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.lowercased()
    }

    static func normalizedDisplayText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// A word Cotabby must accept without correction. This is intentionally separate from replacement
/// rules: learning that `Cotabby` is valid does not imply any particular misspelling should map to it.
nonisolated struct PersonalVocabularyEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var word: String
    var languageCode: String?
    var scope: PersonalCorrectionRule.Scope
    var isCaseSensitive: Bool
    var syncWithMacOSDictionary: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        word: String,
        languageCode: String? = nil,
        scope: PersonalCorrectionRule.Scope = .global,
        isCaseSensitive: Bool = false,
        syncWithMacOSDictionary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.word = PersonalCorrectionRule.normalizedDisplayText(word)
        self.languageCode = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.scope = scope
        self.isCaseSensitive = isCaseSensitive
        self.syncWithMacOSDictionary = syncWithMacOSDictionary
        self.createdAt = createdAt
    }

    var normalizedWord: String {
        PersonalCorrectionRule.lookupKey(for: word, caseSensitive: isCaseSensitive)
    }
}

/// Aggregate feedback for one correction pair. Counts are intentionally content-minimal: Cotabby
/// learns preferences without persisting the sentence that surrounded the correction.
nonisolated struct LearnedCorrection: Codable, Equatable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case observed
        case suggestionOnly
        case trusted
        case blocked
    }

    var source: String
    var destination: String
    var languageCode: String?
    var applicationBundleIdentifier: String?
    var acceptedCount: Int
    var revertedCount: Int
    var dismissedCount: Int
    var state: State
    var firstSeenAt: Date
    var lastSeenAt: Date
}

/// Versioned durable payload. Keeping persistence shape explicit makes migrations testable and lets
/// import/export use the same human-owned data without exposing implementation-specific caches.
nonisolated struct PersonalCorrectionDatabase: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var rules: [PersonalCorrectionRule]
    var vocabulary: [PersonalVocabularyEntry]
    var learnedCorrections: [LearnedCorrection]

    init(
        version: Int = currentVersion,
        rules: [PersonalCorrectionRule] = [],
        vocabulary: [PersonalVocabularyEntry] = [],
        learnedCorrections: [LearnedCorrection] = []
    ) {
        self.version = version
        self.rules = rules
        self.vocabulary = vocabulary
        self.learnedCorrections = learnedCorrections
    }
}

nonisolated private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
