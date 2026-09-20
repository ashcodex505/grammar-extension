import AppKit
import ApplicationServices
import SwiftUI

/// Validated content for one correction captured from a selection in another application.
/// Keeping normalization here makes the panel and persistence path agree on exactly what will be
/// saved, and leaves the selection-reading boundary independently testable.
struct QuickCorrectionDraft: Equatable {
    static let maximumCharacterCount = 500

    let trigger: String

    init?(selectedText: String) {
        let trigger = PersonalCorrectionRule.normalizedDisplayText(selectedText)
        guard !trigger.isEmpty, trigger.count <= Self.maximumCharacterCount else { return nil }
        self.trigger = trigger
    }

    func normalizedReplacement(_ value: String) -> String? {
        let replacement = PersonalCorrectionRule.normalizedDisplayText(value)
        guard !replacement.isEmpty, replacement.count <= Self.maximumCharacterCount else { return nil }
        return replacement
    }
}

/// Coordinates the global quick-correction command from Accessibility selection capture through
/// an AppKit-hosted SwiftUI entry panel and into the existing personal-correction database.
///
/// The selection is read synchronously before Cotabby activates. Once the panel closes, focus is
/// returned to the source application so the user's selected text and editing flow remain intact.
@MainActor
final class QuickCorrectionController: NSObject, NSWindowDelegate {
    private let personalCorrections: PersonalCorrectionModel
    private var windowController: NSWindowController?
    private var sourceApplication: NSRunningApplication?

    init(personalCorrections: PersonalCorrectionModel) {
        self.personalCorrections = personalCorrections
    }

    func presentForCurrentSelection() {
        if let window = windowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let fallbackApplication = NSWorkspace.shared.frontmostApplication
        guard let focused = AXHelper.focusedElement() else {
            presentError(
                "Cotabby could not read the focused field. Check Accessibility permission and try again.",
                returningTo: fallbackApplication
            )
            return
        }

        let element = AXHelper.nearestEditable(from: focused)
        let sourceApplication = AXHelper.owningApplication(of: element) ?? fallbackApplication
        guard !isSecure(element) else {
            presentError(
                "Quick corrections are unavailable in password and other secure fields.",
                returningTo: sourceApplication
            )
            return
        }

        guard let selectedText = AXHelper.selectedText(on: element),
              let draft = QuickCorrectionDraft(selectedText: selectedText) else {
            presentError(
                "Select a word or short phrase first, then press Control–Shift–` again.",
                returningTo: sourceApplication
            )
            return
        }

        self.sourceApplication = sourceApplication
        showPanel(for: draft)
    }

    private func showPanel(for draft: QuickCorrectionDraft) {
        let existingReplacement = personalCorrections.database.rules.first(where: {
            $0.normalizedTrigger == PersonalCorrectionRule.lookupKey(
                for: draft.trigger,
                caseSensitive: $0.isCaseSensitive
            ) && $0.scope == .global
        })?.replacement ?? ""

        let rootView = QuickCorrectionPanelView(
            trigger: draft.trigger,
            initialReplacement: existingReplacement,
            onSave: { [weak self] replacement in
                guard let self,
                      let normalized = draft.normalizedReplacement(replacement) else { return }
                self.personalCorrections.upsertRule(PersonalCorrectionRule(
                    trigger: draft.trigger,
                    replacement: normalized,
                    source: .manual
                ))
                self.windowController?.close()
            },
            onCancel: { [weak self] in
                self?.windowController?.close()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 245),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Correction"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.center()

        let controller = NSWindowController(window: panel)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
    }

    private func presentError(_ message: String, returningTo application: NSRunningApplication?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Quick Correction"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        application?.activate(options: [.activateIgnoringOtherApps])
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        SecureFieldDetector.isSecure(
            role: AXHelper.stringValue(for: kAXRoleAttribute as CFString, on: element),
            subrole: AXHelper.stringValue(for: kAXSubroleAttribute as CFString, on: element),
            roleDescription: AXHelper.stringValue(
                for: kAXRoleDescriptionAttribute as CFString,
                on: element
            ),
            title: AXHelper.stringValue(for: kAXTitleAttribute as CFString, on: element),
            descriptionLabel: AXHelper.stringValue(
                for: kAXDescriptionAttribute as CFString,
                on: element
            )
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === windowController?.window else { return }
        windowController = nil
        let application = sourceApplication
        sourceApplication = nil
        application?.activate(options: [.activateIgnoringOtherApps])
    }
}

private struct QuickCorrectionPanelView: View {
    let trigger: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var replacement: String
    @FocusState private var isReplacementFocused: Bool

    init(
        trigger: String,
        initialReplacement: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.trigger = trigger
        self.onSave = onSave
        self.onCancel = onCancel
        _replacement = State(initialValue: initialReplacement)
    }

    private var normalizedReplacement: String? {
        QuickCorrectionDraft(selectedText: trigger)?.normalizedReplacement(replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Replace selected text")
                    .font(.headline)
                Text(trigger)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("With")
                    .font(.subheadline.weight(.medium))
                TextField("Correct spelling or phrase", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .focused($isReplacementFocused)
                    .onSubmit(save)
            }

            Text("This adds an automatic rule to Settings → Corrections.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Correction", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedReplacement == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 245)
        .onAppear {
            DispatchQueue.main.async { isReplacementFocused = true }
        }
    }

    private func save() {
        guard normalizedReplacement != nil else { return }
        onSave(replacement)
    }
}
