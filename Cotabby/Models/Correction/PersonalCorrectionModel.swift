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
    private var hasMutationsBeforeInitialLoad = false

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

    func removeVocabulary(id: UUID) {
        guard let entry = database.vocabulary.first(where: { $0.id == id }) else { return }
        database.vocabulary.removeAll(where: { $0.id == id })
        if entry.syncWithMacOSDictionary { NSSpellChecker.shared.unlearnWord(entry.word) }
        didMutateDatabase()
    }

    func clearLearnedCorrections() {
        database.learnedCorrections.removeAll()
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

    func recordAppliedCorrection(source: String, destination: String, bundleIdentifier: String?) {
        recordOutcome(
            source: source,
            destination: destination,
            bundleIdentifier: bundleIdentifier,
            reverted: false
        )
    }

    func recordRevertedCorrection(source: String, destination: String, bundleIdentifier: String?) {
        recordOutcome(
            source: source,
            destination: destination,
            bundleIdentifier: bundleIdentifier,
            reverted: true
        )
    }

    func exportData() async throws -> Data {
        try await store.exportData(database)
    }

    func waitForPendingWrites() async {
        await persistenceTask?.value
    }

    private func load() async {
        var installedStarterDefaults = false
        do {
            let isFirstLaunch = !(await store.hasStoredDatabase())
            var loaded = try await store.load()
            if isFirstLaunch {
                loaded.rules = PersonalCorrectionDefaults.rules
                installedStarterDefaults = true
            }
            database = hasMutationsBeforeInitialLoad
                ? Self.merging(loaded, with: database)
                : loaded
            index = PersonalCorrectionIndex(database: database)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
        if hasMutationsBeforeInitialLoad || installedStarterDefaults {
            hasMutationsBeforeInitialLoad = false
            didMutateDatabase()
        }
    }

    private func didMutateDatabase() {
        index = PersonalCorrectionIndex(database: database)
        guard isLoaded else {
            hasMutationsBeforeInitialLoad = true
            return
        }
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

    private func recordOutcome(
        source: String,
        destination: String,
        bundleIdentifier: String?,
        reverted: Bool
    ) {
        let normalizedSource = PersonalCorrectionRule.normalizedDisplayText(source)
        let normalizedDestination = PersonalCorrectionRule.normalizedDisplayText(destination)
        guard !normalizedSource.isEmpty, !normalizedDestination.isEmpty else { return }

        let existingIndex = database.learnedCorrections.firstIndex(where: {
            $0.source == normalizedSource
                && $0.destination == normalizedDestination
                && $0.applicationBundleIdentifier == bundleIdentifier
        })
        let now = Date()
        if let existingIndex {
            var learned = database.learnedCorrections[existingIndex]
            if reverted {
                learned.revertedCount += 1
            } else {
                learned.acceptedCount += 1
            }
            learned.lastSeenAt = now
            learned.state = Self.learnedState(
                accepted: learned.acceptedCount,
                reverted: learned.revertedCount
            )
            database.learnedCorrections[existingIndex] = learned
        } else {
            database.learnedCorrections.append(LearnedCorrection(
                source: normalizedSource,
                destination: normalizedDestination,
                languageCode: nil,
                applicationBundleIdentifier: bundleIdentifier,
                acceptedCount: reverted ? 0 : 1,
                revertedCount: reverted ? 1 : 0,
                dismissedCount: 0,
                state: reverted ? .blocked : .observed,
                firstSeenAt: now,
                lastSeenAt: now
            ))
        }
        didMutateDatabase()
    }

    private static func learnedState(accepted: Int, reverted: Int) -> LearnedCorrection.State {
        if reverted >= 2 || reverted > accepted { return .blocked }
        if accepted >= 3, reverted == 0 { return .trusted }
        if accepted >= 2 { return .suggestionOnly }
        return .observed
    }

    private static func merging(
        _ stored: PersonalCorrectionDatabase,
        with inMemory: PersonalCorrectionDatabase
    ) -> PersonalCorrectionDatabase {
        var merged = stored
        for rule in inMemory.rules {
            merged.rules.removeAll(where: { $0.id == rule.id })
            merged.rules.append(rule)
        }
        for entry in inMemory.vocabulary {
            merged.vocabulary.removeAll(where: { $0.id == entry.id })
            merged.vocabulary.append(entry)
        }
        for incoming in inMemory.learnedCorrections {
            if let index = merged.learnedCorrections.firstIndex(where: {
                $0.source == incoming.source
                    && $0.destination == incoming.destination
                    && $0.applicationBundleIdentifier == incoming.applicationBundleIdentifier
            }) {
                merged.learnedCorrections[index].acceptedCount += incoming.acceptedCount
                merged.learnedCorrections[index].revertedCount += incoming.revertedCount
                merged.learnedCorrections[index].dismissedCount += incoming.dismissedCount
                merged.learnedCorrections[index].lastSeenAt = max(
                    merged.learnedCorrections[index].lastSeenAt,
                    incoming.lastSeenAt
                )
                let learned = merged.learnedCorrections[index]
                merged.learnedCorrections[index].state = learnedState(
                    accepted: learned.acceptedCount,
                    reverted: learned.revertedCount
                )
            } else {
                merged.learnedCorrections.append(incoming)
            }
        }
        return merged
    }
}
