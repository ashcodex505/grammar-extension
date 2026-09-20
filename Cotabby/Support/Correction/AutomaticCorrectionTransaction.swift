import Foundation

/// Short-lived proof that Cotabby—not the host app—just replaced text. It authorizes consuming one
/// immediate Backspace to restore the original spelling. Every identity and suffix check must pass;
/// otherwise the key remains owned by the host application.
nonisolated struct AutomaticCorrectionTransaction: Equatable, Sendable {
    let originalText: String
    let replacementText: String
    let bundleIdentifier: String
    let elementIdentifier: String
    let focusChangeSequence: UInt64

    func undoPlan(for context: FocusedInputSnapshot) -> TypoCorrectionReplacement? {
        guard context.bundleIdentifier == bundleIdentifier,
              context.elementIdentifier == elementIdentifier,
              context.focusChangeSequence == focusChangeSequence else {
            return nil
        }

        let correctedSuffix = replacementText + " "
        guard context.precedingText.hasSuffix(correctedSuffix) else { return nil }
        return TypoCorrectionReplacement(
            deletingUTF16Count: (correctedSuffix as NSString).length,
            replacementText: originalText
        )
    }
}

/// One-shot memory created by undo. Pressing Space again after the restored spelling skips the
/// matching automatic rule once instead of immediately recreating the rejected edit.
nonisolated struct RejectedCorrectionOccurrence: Equatable, Sendable {
    let originalText: String
    let replacementText: String
    let bundleIdentifier: String
    let elementIdentifier: String
    let focusChangeSequence: UInt64

    func matches(_ match: PersonalCorrectionIndex.Match, context: FocusedInputSnapshot) -> Bool {
        matches(
            sourceText: match.matchedText,
            replacementText: match.replacementText,
            context: context
        )
    }

    func matches(_ match: PersonalCorrectionIndex.LearnedMatch, context: FocusedInputSnapshot) -> Bool {
        matches(
            sourceText: match.sourceText,
            replacementText: match.replacementText,
            context: context
        )
    }

    private func matches(
        sourceText: String,
        replacementText: String,
        context: FocusedInputSnapshot
    ) -> Bool {
        originalText == sourceText
            && self.replacementText == replacementText
            && bundleIdentifier == context.bundleIdentifier
            && elementIdentifier == context.elementIdentifier
            && focusChangeSequence == context.focusChangeSequence
    }

    func matchesRestoredOriginal(context: FocusedInputSnapshot) -> Bool {
        bundleIdentifier == context.bundleIdentifier
            && elementIdentifier == context.elementIdentifier
            && focusChangeSequence == context.focusChangeSequence
            && context.precedingText.hasSuffix(originalText + " ")
    }
}
