import Foundation

/// Immutable, keystroke-safe lookup snapshot compiled from the durable correction database.
/// Persistence can replace this value while the hot path performs bounded string comparisons—
/// never file I/O.
nonisolated struct PersonalCorrectionIndex: Equatable, Sendable {
    struct Match: Equatable, Sendable {
        let rule: PersonalCorrectionRule
        /// Exact spelling observed in the host field, retained for stale replacement validation.
        let matchedText: String
        let replacementText: String
    }

    static let empty = PersonalCorrectionIndex(database: PersonalCorrectionDatabase())

    private let rulesByLastCharacter: [Character: [PersonalCorrectionRule]]
    private let insensitiveVocabulary: Set<ScopedLookupKey>
    private let sensitiveVocabulary: Set<ScopedLookupKey>

    init(database: PersonalCorrectionDatabase) {
        let enabledRules = database.rules
            .filter { $0.isEnabled && !$0.trigger.isEmpty && !$0.replacement.isEmpty }
            .sorted {
                if $0.trigger.count != $1.trigger.count { return $0.trigger.count > $1.trigger.count }
                return $0.updatedAt > $1.updatedAt
            }
        rulesByLastCharacter = Dictionary(grouping: enabledRules) { rule in
            rule.normalizedTrigger.last ?? Character(" ")
        }

        insensitiveVocabulary = Set(database.vocabulary.compactMap { entry in
            guard !entry.isCaseSensitive, !entry.word.isEmpty else { return nil }
            return ScopedLookupKey(value: entry.normalizedWord, scope: entry.scope)
        })
        sensitiveVocabulary = Set(database.vocabulary.compactMap { entry in
            guard entry.isCaseSensitive, !entry.word.isEmpty else { return nil }
            return ScopedLookupKey(value: entry.normalizedWord, scope: entry.scope)
        })
    }

    /// Finds the longest explicit rule immediately before a newly typed Space. Restricting mutation
    /// to a committed boundary avoids changing a word while the user is still forming it.
    func committedMatch(precedingText: String, bundleIdentifier: String?) -> Match? {
        guard precedingText.last == " " else { return nil }
        let textWithoutDelimiter = precedingText.dropLast()
        guard let last = textWithoutDelimiter.last else { return nil }
        let insensitiveLast = String(last).lowercased().first ?? last
        let candidates = (rulesByLastCharacter[last] ?? [])
            + (insensitiveLast == last ? [] : (rulesByLastCharacter[insensitiveLast] ?? []))

        for rule in candidates where rule.scope.matches(bundleIdentifier: bundleIdentifier) {
            guard let observed = matchingSuffix(of: textWithoutDelimiter, for: rule) else { continue }
            let replacement = rule.caseMode == .transfer
                ? TypoCaseTransfer.applying(caseOf: observed, to: rule.replacement)
                : rule.replacement
            return Match(rule: rule, matchedText: observed, replacementText: replacement)
        }
        return nil
    }

    func acceptsVocabulary(_ word: String, bundleIdentifier: String?) -> Bool {
        let globalInsensitive = ScopedLookupKey(value: word.lowercased(), scope: .global)
        let globalSensitive = ScopedLookupKey(value: word, scope: .global)
        if insensitiveVocabulary.contains(globalInsensitive) || sensitiveVocabulary.contains(globalSensitive) {
            return true
        }
        guard let bundleIdentifier else { return false }
        let scope = PersonalCorrectionRule.Scope.application(bundleIdentifier)
        return insensitiveVocabulary.contains(ScopedLookupKey(value: word.lowercased(), scope: scope))
            || sensitiveVocabulary.contains(ScopedLookupKey(value: word, scope: scope))
    }

    private func matchingSuffix(of text: Substring, for rule: PersonalCorrectionRule) -> String? {
        guard text.count >= rule.trigger.count else { return nil }
        let start = text.index(text.endIndex, offsetBy: -rule.trigger.count)
        let observed = String(text[start...])
        let matches = rule.isCaseSensitive
            ? observed == rule.trigger
            : observed.compare(rule.trigger, options: [.caseInsensitive], locale: .current) == .orderedSame
        guard matches else { return nil }

        // A suffix match must begin at a token boundary. This prevents `im` firing inside `time`.
        if start > text.startIndex {
            let characterBefore = text[text.index(before: start)]
            guard !characterBefore.isLetter, !characterBefore.isNumber else { return nil }
        }
        return observed
    }
}

nonisolated private struct ScopedLookupKey: Hashable, Sendable {
    let value: String
    let scope: PersonalCorrectionRule.Scope
}
