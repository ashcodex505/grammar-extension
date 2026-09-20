import Carbon.HIToolbox
import Foundation
import Logging

/// Registers one exact system hotkey with macOS: Control–Shift–backtick.
///
/// Unlike a keyboard event tap, `RegisterEventHotKey` does not observe ordinary typing. The system
/// invokes this service only when the registered chord is pressed, keeping the existing Cotabby
/// input path unchanged and adding no per-keystroke work.
@MainActor
final class QuickCorrectionHotKey {
    static let keyCode = UInt32(kVK_ANSI_Grave)
    static let modifiers = UInt32(controlKey | shiftKey)

    private static let signature: OSType = 0x43545143 // "CTQC"
    private static let identifier: UInt32 = 1

    private let onTriggered: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(onTriggered: @escaping @MainActor () -> Void) {
        self.onTriggered = onTriggered
    }

    func start() {
        guard hotKeyReference == nil, eventHandlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            quickCorrectionHotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            CotabbyLogger.app.error("Could not install quick-correction hotkey handler: \(handlerStatus)")
            eventHandlerReference = nil
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            CotabbyLogger.app.error("Could not register quick-correction hotkey: \(registrationStatus)")
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            self.eventHandlerReference = nil
            hotKeyReference = nil
            return
        }

        CotabbyLogger.app.info("Quick-correction hotkey registered")
    }

    func stop() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    fileprivate func handlePressedHotKey(_ id: EventHotKeyID) -> OSStatus {
        guard id.signature == Self.signature, id.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        onTriggered()
        return noErr
    }
}

/// Carbon delivers application-target hotkey events on the main event loop. The explicit thread
/// guard protects the actor assumption if that contract ever changes.
private let quickCorrectionHotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard Thread.isMainThread, let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let hotKey = Unmanaged<QuickCorrectionHotKey>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        hotKey.handlePressedHotKey(hotKeyID)
    }
}
