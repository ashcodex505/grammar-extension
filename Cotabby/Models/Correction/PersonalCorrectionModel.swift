import AppKit
import Combine
import Foundation

/// Main-actor source of truth for the correction UI and live immutable lookup index. It owns one
/// process-lifetime store and serializes writes without making the keystroke path await persistence.
@MainActor
final class PersonalCorrectionModel: ObservableObject {
    @Published private(set) var database = PersonalCorrectionDatabase()
    @Published private(set) var isLoaded = false
    @Published private(set) var errorMessage: String?

    private(set) var index = PersonalCorrectionIndex.empty
    private let store: PersonalCorrectionStore
    private var persistenceTask: Task<Void, Never>?

    init(store: PersonalCorrectionStore = PersonalCorrectionStore()) {
        self.store = store
        Task { [weak self] in await self?.load() }
    }

    func addRule(_ rule: PersonalCorrectionRule) {
        guard !rule.trigger.isEmpty, !rule.replacement.isEmpty else { return }
        database.rules.append(rule)
        didMutateDatabase()
    }

    func updateRule(_ rule: PersonalCorrectionRule) {
        guard let index = database.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var updated = rule
        updated.updatedAt = Date()
        database.rules[index] = updated
        didMutateDatabase()
    }

    func removeRules(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where database.rules.indices.contains(offset) {
            database.rules.remove(at: offset)
        }
        didMutateDatabase()
    }

    func removeRule(id: UUID) {
        database.rules.removeAll(where: { $0.id == id })
        didMutateDatabase()
    }

    func addVocabulary(_ entry: PersonalVocabularyEntry) {
        guard !entry.word.isEmpty else { return }
        database.vocabulary.removeAll(where: {
            $0.normalizedWord == entry.normalizedWord && $0.scope == entry.scope
        })
        database.vocabulary.append(entry)
        if entry.syncWithMacOSDictionary { NSSpellChecker.shared.learnWord(entry.word) }
        didMutateDatabase()
    }

    func removeVocabulary(at offsets: IndexSet) {
        let removed = offsets.compactMap {
            database.vocabulary.indices.contains($0) ? database.vocabulary[$0] : nil
        }
        for offset in offsets.sorted(by: >) where database.vocabulary.indices.contains(offset) {
            database.vocabulary.remove(at: offset)
        }
        for entry in removed where entry.syncWithMacOSDictionary {
            NSSpellChecker.shared.unlearnWord(entry.word)
        }
        didMutateDatabase()
    }

    /// Same-scope triggers are replaced by the imported rule. A preview containing errors is never
    /// committed, so import remains an all-or-nothing user action.
    func commitImport(_ preview: CorrectionImportParser.Preview) {
        guard preview.errorCount == 0 else { return }
        for imported in preview.rules {
            database.rules.removeAll(where: { existing in
                existing.normalizedTrigger == imported.normalizedTrigger
                    && existing.scope == imported.scope
                    && existing.isCaseSensitive == imported.isCaseSensitive
            })
            database.rules.append(imported)
        }
        didMutateDatabase()
    }

    func exportData() async throws -> Data {
        try await store.exportData(database)
    }

    func waitForPendingWrites() async {
        await persistenceTask?.value
    }

    private func load() async {
        do {
            let loaded = try await store.load()
            database = loaded
            index = PersonalCorrectionIndex(database: loaded)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    private func didMutateDatabase() {
        index = PersonalCorrectionIndex(database: database)
        let snapshot = database
        let previous = persistenceTask
        persistenceTask = Task { [store] in
            await previous?.value
            do {
                try await store.save(snapshot)
            } catch {
                await MainActor.run { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }
}
