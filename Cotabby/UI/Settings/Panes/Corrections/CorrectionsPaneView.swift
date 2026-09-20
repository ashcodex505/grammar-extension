import AppKit
import SwiftUI

/// Complete correction-management surface. Generic dictionary correction settings remain backed by
/// `SuggestionSettingsModel`; user-owned rules, accepted vocabulary, imports, and feedback history
/// flow through `PersonalCorrectionModel`. Keeping this view presentation-only lets the same model
/// serve the keystroke pipeline without UI dependencies.
struct CorrectionsPaneView: View {
    @ObservedObject var suggestionSettings: SuggestionSettingsModel
    @ObservedObject var personalCorrections: PersonalCorrectionModel

    @State private var newTrigger = ""
    @State private var newReplacement = ""
    @State private var newVocabularyWord = ""
    @State private var syncVocabularyWithMacOS = false
    @State private var importPreview: CorrectionImportParser.Preview?
    @State private var isShowingImportPreview = false
    @State private var operationMessage: String?

    var body: some View {
        SettingsPaneScaffold {
            Section("Automatic Spelling") {
                Toggle(isOn: suppressCompletionsOnTypoBinding) {
                    SettingsRowLabel(
                        title: "Detect Typos",
                        description: "Pauses normal completions when the current word looks misspelled.",
                        systemImage: "text.badge.checkmark"
                    )
                }
                .settingsItem(.hideSuggestionsOnTypo)

                if suggestionSettings.suppressCompletionsOnTypo {
                    Toggle(isOn: offerTypoCorrectionsBinding) {
                        SettingsRowLabel(
                            title: "Offer Corrections",
                            description: "Shows a green replacement that you apply with the accept key.",
                            systemImage: "checkmark.bubble"
                        )
                    }
                    .settingsItem(.offerTypoCorrections)

                    Toggle(isOn: automaticallyFixTyposBinding) {
                        SettingsRowLabel(
                            title: "Automatically Fix After Space",
                            description: "Replaces a high-confidence misspelling after Space. "
                                + "Press Backspace immediately to restore the original spelling.",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .settingsItem(.automaticallyFixTypos)
                }
            }

            if suggestionSettings.suppressCompletionsOnTypo,
               suggestionSettings.offerTypoCorrections || suggestionSettings.automaticallyFixTypos {
                Section("Spelling Dictionaries") {
                    SpellingDictionaryPicker(suggestionSettings: suggestionSettings)
                        .settingsItem(.spellingDictionaries)
                }
            }

            Section("Personal Replacements") {
                Text(
                    "These rules run before spell checking, so they can fix valid words, single letters, "
                        + "contractions, and phrases. The longest matching rule wins."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Misspelling or phrase", text: $newTrigger)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Replacement", text: $newReplacement)
                    Button("Add", action: addRule)
                        .disabled(normalizedNewTrigger.isEmpty || normalizedNewReplacement.isEmpty)
                }

                if personalCorrections.database.rules.isEmpty {
                    Text("No personal replacements yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(personalCorrections.database.rules) { rule in
                        correctionRuleRow(rule)
                    }
                }
            }

            Section("Personal Vocabulary") {
                Text(
                    "Accepted words are left alone. This is the right place for names, product terms, "
                        + "technical vocabulary, and deliberate spellings."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Word to accept", text: $newVocabularyWord)
                    Toggle("Also teach macOS", isOn: $syncVocabularyWithMacOS)
                        .toggleStyle(.checkbox)
                    Button("Learn", action: addVocabulary)
                        .disabled(normalizedVocabularyWord.isEmpty)
                }

                ForEach(personalCorrections.database.vocabulary) { entry in
                    HStack {
                        Image(systemName: "character.book.closed")
                            .foregroundStyle(.secondary)
                        Text(entry.word)
                        Spacer()
                        if entry.syncWithMacOSDictionary {
                            Text("macOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            personalCorrections.removeVocabulary(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Forget \(entry.word)")
                    }
                }
            }

            Section("Import & Export") {
                Text(
                    "Import CSV, TSV, JSON, or text such as ‘teh -> the’ and ‘teh:the’. "
                        + "Cotabby previews warnings and conflicts before changing your rules."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Import File…", action: chooseImportFile)
                    Button("Import macOS Replacements", action: importMacOSReplacements)
                    Button("Export Backup…", action: chooseExportLocation)
                        .disabled(!personalCorrections.isLoaded)
                }

                if let operationMessage {
                    Text(operationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = personalCorrections.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Local Learning") {
                Text(
                    "Cotabby records correction pairs and accept/revert counts—not surrounding sentences. "
                        + "Repeated acceptance raises confidence; immediate Backspace reversals lower it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if personalCorrections.database.learnedCorrections.isEmpty {
                    Text("No correction feedback recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(personalCorrections.database.learnedCorrections.enumerated()),
                        id: \.offset
                    ) { _, learned in
                        HStack {
                            Text(learned.source)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(learned.destination)
                            Spacer()
                            Text("\(learned.acceptedCount) kept · \(learned.revertedCount) reverted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(learned.state.rawValue)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Button("Clear Learning History", role: .destructive) {
                        personalCorrections.clearLearnedCorrections()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingImportPreview) {
            if let importPreview {
                CorrectionImportPreviewView(preview: importPreview) {
                    personalCorrections.commitImport(importPreview)
                    operationMessage = "Imported \(importPreview.rules.count) replacement rules."
                    isShowingImportPreview = false
                } onCancel: {
                    isShowingImportPreview = false
                }
            }
        }
    }

    @ViewBuilder
    private func correctionRuleRow(_ rule: PersonalCorrectionRule) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: ruleBinding(rule.id, keyPath: \.isEnabled))
                .labelsHidden()
                .accessibilityLabel("Enable \(rule.trigger) replacement")
            Text(rule.trigger)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(rule.replacement)
                .lineLimit(1)
            Spacer()
            Picker("Action", selection: ruleActionBinding(rule.id)) {
                Text("Automatic").tag(PersonalCorrectionRule.Action.automatic)
                Text("Offer").tag(PersonalCorrectionRule.Action.offer)
            }
            .labelsHidden()
            .frame(width: 110)
            Button(role: .destructive) {
                personalCorrections.removeRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(rule.trigger) replacement")
        }
    }

    private var normalizedNewTrigger: String {
        PersonalCorrectionRule.normalizedDisplayText(newTrigger)
    }

    private var normalizedNewReplacement: String {
        PersonalCorrectionRule.normalizedDisplayText(newReplacement)
    }

    private var normalizedVocabularyWord: String {
        PersonalCorrectionRule.normalizedDisplayText(newVocabularyWord)
    }

    private func addRule() {
        personalCorrections.addRule(PersonalCorrectionRule(
            trigger: normalizedNewTrigger,
            replacement: normalizedNewReplacement
        ))
        newTrigger = ""
        newReplacement = ""
    }

    private func addVocabulary() {
        personalCorrections.addVocabulary(PersonalVocabularyEntry(
            word: normalizedVocabularyWord,
            syncWithMacOSDictionary: syncVocabularyWithMacOS
        ))
        newVocabularyWord = ""
    }

    private func ruleBinding(
        _ id: UUID,
        keyPath: WritableKeyPath<PersonalCorrectionRule, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                personalCorrections.database.rules.first(where: { $0.id == id })?[keyPath: keyPath] ?? false
            },
            set: { value in
                guard var rule = personalCorrections.database.rules.first(where: { $0.id == id }) else { return }
                rule[keyPath: keyPath] = value
                personalCorrections.updateRule(rule)
            }
        )
    }

    private func ruleActionBinding(_ id: UUID) -> Binding<PersonalCorrectionRule.Action> {
        Binding(
            get: {
                personalCorrections.database.rules.first(where: { $0.id == id })?.action ?? .automatic
            },
            set: { value in
                guard var rule = personalCorrections.database.rules.first(where: { $0.id == id }) else { return }
                rule.action = value
                personalCorrections.updateRule(rule)
            }
        )
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a correction list to preview"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            importPreview = CorrectionImportParser.parse(data: data)
            isShowingImportPreview = true
        } catch {
            operationMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importMacOSReplacements() {
        let rules = NSSpellChecker.shared.userReplacementsDictionary.map {
            PersonalCorrectionRule(
                trigger: $0.key,
                replacement: $0.value,
                source: .macOSTextReplacement
            )
        }
        importPreview = CorrectionImportParser.Preview(rules: rules, issues: [])
        isShowingImportPreview = true
    }

    private func chooseExportLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Cotabby-Personal-Corrections.json"
        panel.message = "Export rules, vocabulary, and local learning data"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await personalCorrections.exportData()
                try data.write(to: url, options: .atomic)
                operationMessage = "Exported a correction backup."
            } catch {
                operationMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private var suppressCompletionsOnTypoBinding: Binding<Bool> {
        Binding(
            get: { suggestionSettings.suppressCompletionsOnTypo },
            set: { suggestionSettings.setSuppressCompletionsOnTypo($0) }
        )
    }

    private var offerTypoCorrectionsBinding: Binding<Bool> {
        Binding(
            get: { suggestionSettings.offerTypoCorrections },
            set: { suggestionSettings.setOfferTypoCorrections($0) }
        )
    }

    private var automaticallyFixTyposBinding: Binding<Bool> {
        Binding(
            get: { suggestionSettings.automaticallyFixTypos },
            set: { suggestionSettings.setAutomaticallyFixTypos($0) }
        )
    }
}

private struct CorrectionImportPreviewView: View {
    let preview: CorrectionImportParser.Preview
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Preview")
                .font(.title2.bold())
            Text("\(preview.rules.count) valid rules · \(preview.errorCount) errors · \(preview.warningCount) warnings")
                .foregroundStyle(.secondary)

            List {
                ForEach(preview.rules) { rule in
                    HStack {
                        Text(rule.trigger)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(rule.replacement)
                    }
                }
                ForEach(preview.issues) { issue in
                    Label {
                        Text(issue.line.map { "Line \($0): \(issue.message)" } ?? issue.message)
                    } icon: {
                        Image(systemName: issue.severity == .error
                            ? "xmark.octagon.fill"
                            : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                    }
                }
            }
            .frame(minHeight: 320)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Import", action: onImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.rules.isEmpty || preview.errorCount > 0)
            }
        }
        .padding(20)
        .frame(width: 620, height: 500)
    }
}
