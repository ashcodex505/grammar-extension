import Foundation

/// Parses user-owned replacement lists into a preview. Parsing never mutates the live database;
/// callers show `issues` and resolve conflicts before committing the valid rules atomically.
nonisolated enum CorrectionImportParser {
    struct Issue: Equatable, Sendable, Identifiable {
        enum Severity: String, Sendable {
            case warning
            case error
        }

        let id: UUID
        let line: Int?
        let severity: Severity
        let message: String

        init(line: Int?, severity: Severity, message: String) {
            id = UUID()
            self.line = line
            self.severity = severity
            self.message = message
        }
    }

    struct Preview: Equatable, Sendable {
        var rules: [PersonalCorrectionRule]
        var issues: [Issue]
        var vocabulary: [PersonalVocabularyEntry]
        var learnedCorrections: [LearnedCorrection]

        init(
            rules: [PersonalCorrectionRule],
            issues: [Issue],
            vocabulary: [PersonalVocabularyEntry] = [],
            learnedCorrections: [LearnedCorrection] = []
        ) {
            self.rules = rules
            self.issues = issues
            self.vocabulary = vocabulary
            self.learnedCorrections = learnedCorrections
        }

        var errorCount: Int { issues.count(where: { $0.severity == .error }) }
        var warningCount: Int { issues.count(where: { $0.severity == .warning }) }
    }

    enum Format: Sendable {
        case automatic
        case plainText
        case csv
        case tsv
        case json
    }

    static func parse(
        data: Data,
        format: Format = .automatic,
        source: PersonalCorrectionRule.Source = .imported
    ) -> Preview {
        let resolved = resolvedFormat(data: data, requested: format)
        switch resolved {
        case .json:
            return parseJSON(data, source: source)
        case .csv:
            return parseDelimited(data, delimiter: ",", source: source)
        case .tsv:
            return parseDelimited(data, delimiter: "\t", source: source)
        case .plainText, .automatic:
            guard let text = String(data: data, encoding: .utf8) else {
                return Preview(
                    rules: [],
                    issues: [Issue(line: nil, severity: .error, message: "The file is not valid UTF-8 text.")]
                )
            }
            return parsePlainText(text, source: source)
        }
    }

    static func parsePlainText(
        _ text: String,
        source: PersonalCorrectionRule.Source = .imported
    ) -> Preview {
        var rules: [PersonalCorrectionRule] = []
        var issues: [Issue] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line.removeFirst(2)
            }
            if line.lowercased().hasPrefix("others:") {
                line = String(line.dropFirst("others:".count))
            }

            let fragments = splitCommaSeparatedPairs(line)
            var parsedAny = false
            for fragment in fragments {
                guard let pair = parsePair(fragment) else { continue }
                parsedAny = true
                appendRule(
                    trigger: pair.trigger,
                    replacement: pair.replacement,
                    line: lineNumber,
                    source: source,
                    rules: &rules,
                    issues: &issues
                )
            }

            if !parsedAny {
                issues.append(Issue(
                    line: lineNumber,
                    severity: .warning,
                    message: "Skipped this line because it is not a replacement pair such as ‘teh -> the’."
                ))
            }
        }

        appendDuplicateIssues(rules: rules, issues: &issues)
        return Preview(rules: rules, issues: issues)
    }

    private static func resolvedFormat(data: Data, requested: Format) -> Format {
        guard requested == .automatic else { return requested }
        guard let first = String(data: data.prefix(128), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return .plainText
        }
        if first == "{" || first == "[" { return .json }
        let head = String(data: data.prefix(512), encoding: .utf8) ?? ""
        if head.contains("\t") { return .tsv }
        if head.lowercased().contains("trigger,") || head.lowercased().contains("replace,") {
            return .csv
        }
        return .plainText
    }

    private static func parseJSON(
        _ data: Data,
        source: PersonalCorrectionRule.Source
    ) -> Preview {
        let decoder = PersonalCorrectionJSONCoding.makeDecoder()
        if let database = try? decoder.decode(PersonalCorrectionDatabase.self, from: data) {
            var preview = validated(database.rules.map { rule in
                var imported = rule
                imported.source = source
                imported.updatedAt = Date()
                return imported
            })
            preview.vocabulary = database.vocabulary.filter { !$0.word.isEmpty }
            preview.learnedCorrections = database.learnedCorrections.filter {
                !$0.source.isEmpty && !$0.destination.isEmpty
            }
            return preview
        }
        if let rules = try? decoder.decode([PersonalCorrectionRule].self, from: data) {
            return validated(rules.map { rule in
                var imported = rule
                imported.source = source
                imported.updatedAt = Date()
                return imported
            })
        }
        if let dictionary = try? decoder.decode([String: String].self, from: data) {
            return validated(dictionary.sorted(by: { $0.key < $1.key }).map {
                PersonalCorrectionRule(trigger: $0.key, replacement: $0.value, source: source)
            })
        }
        return Preview(
            rules: [],
            issues: [Issue(
                line: nil,
                severity: .error,
                message: "JSON must be an exported correction database, an array of rules, or a string-to-string object."
            )]
        )
    }

    private static func parseDelimited(
        _ data: Data,
        delimiter: Character,
        source: PersonalCorrectionRule.Source
    ) -> Preview {
        guard let text = String(data: data, encoding: .utf8) else {
            return Preview(
                rules: [],
                issues: [Issue(line: nil, severity: .error, message: "The file is not valid UTF-8 text.")]
            )
        }
        var rules: [PersonalCorrectionRule] = []
        var issues: [Issue] = []
        for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let fields = delimitedFields(in: line, delimiter: delimiter)
            if offset == 0,
               fields.first?.lowercased().contains("trigger") == true {
                continue
            }
            guard fields.count >= 2 else {
                issues.append(Issue(
                    line: offset + 1,
                    severity: .warning,
                    message: "Skipped this row because it needs trigger and replacement columns."
                ))
                continue
            }
            appendRule(
                trigger: fields[0],
                replacement: fields[1],
                line: offset + 1,
                source: source,
                rules: &rules,
                issues: &issues
            )
        }
        appendDuplicateIssues(rules: rules, issues: &issues)
        return Preview(rules: rules, issues: issues)
    }

    private static func validated(_ input: [PersonalCorrectionRule]) -> Preview {
        var rules: [PersonalCorrectionRule] = []
        var issues: [Issue] = []
        for rule in input {
            appendRule(
                trigger: rule.trigger,
                replacement: rule.replacement,
                line: nil,
                source: rule.source,
                template: rule,
                rules: &rules,
                issues: &issues
            )
        }
        appendDuplicateIssues(rules: rules, issues: &issues)
        return Preview(rules: rules, issues: issues)
    }

    private static func appendRule(
        trigger rawTrigger: String,
        replacement rawReplacement: String,
        line: Int?,
        source: PersonalCorrectionRule.Source,
        template: PersonalCorrectionRule? = nil,
        rules: inout [PersonalCorrectionRule],
        issues: inout [Issue]
    ) {
        let trigger = PersonalCorrectionRule.normalizedDisplayText(rawTrigger)
        let replacement = PersonalCorrectionRule.normalizedDisplayText(rawReplacement)
        guard !trigger.isEmpty, !replacement.isEmpty else {
            issues.append(Issue(line: line, severity: .warning, message: "Skipped an empty trigger or replacement."))
            return
        }
        guard trigger != replacement else {
            issues.append(Issue(line: line, severity: .warning, message: "Skipped an identical trigger and replacement."))
            return
        }
        guard replacement.contains(where: { $0.isLetter || $0.isNumber || $0.isSymbol }) else {
            issues.append(Issue(
                line: line,
                severity: .warning,
                message: "Skipped this pair because the replacement is punctuation alone."
            ))
            return
        }
        guard trigger.count <= 200, replacement.count <= 500 else {
            issues.append(Issue(line: line, severity: .warning, message: "Skipped a pair exceeding the safe import length."))
            return
        }
        guard !trigger.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !replacement.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            issues.append(Issue(line: line, severity: .warning, message: "Skipped a pair containing control characters."))
            return
        }

        var rule = template ?? PersonalCorrectionRule(trigger: trigger, replacement: replacement, source: source)
        rule.trigger = trigger
        rule.replacement = replacement
        rule.source = source
        rules.append(rule)

        if trigger.count <= 2 || commonValidWords.contains(trigger.lowercased()) {
            issues.append(Issue(
                line: line,
                severity: .warning,
                message: "‘\(trigger)’ is short or commonly valid; review this rule before enabling automatic replacement."
            ))
        }
        if replacement.last?.isPunctuation == true {
            issues.append(Issue(
                line: line,
                severity: .warning,
                message: "‘\(replacement)’ ends in punctuation; confirm that punctuation is part of the replacement."
            ))
        }
    }

    private static func appendDuplicateIssues(
        rules: [PersonalCorrectionRule],
        issues: inout [Issue]
    ) {
        var destinations: [String: Set<String>] = [:]
        for rule in rules {
            destinations[rule.normalizedTrigger, default: []].insert(rule.replacement)
        }
        for (trigger, replacements) in destinations where replacements.count > 1 {
            issues.append(Issue(
                line: nil,
                severity: .error,
                message: "‘\(trigger)’ maps to multiple replacements: \(replacements.sorted().joined(separator: ", "))."
            ))
        }
    }

    private static func parsePair(_ input: String) -> (trigger: String, replacement: String)? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["->", "→"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        guard let colon = value.firstIndex(of: ":") else { return nil }
        return (String(value[..<colon]), String(value[value.index(after: colon)...]))
    }

    private static func splitCommaSeparatedPairs(_ input: String) -> [String] {
        guard input.contains(",") else { return [input] }
        let fragments = input.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return fragments.contains(where: { parsePair($0) != nil }) ? fragments : [input]
    }

    private static func delimitedFields(in line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == delimiter, !quoted {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static let commonValidWords: Set<String> = [
        "am", "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is", "it",
        "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we", "form"
    ]
}
