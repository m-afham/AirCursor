import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts (Carbon hot keys need no Accessibility permission).
final class HotKeyManager {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4143_5253 // "ACRS"

    func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("AirCursor: hot key \(id) unavailable (\(status)); another app may own it.")
            return
        }
        refs.append(ref)
        handlers[id] = handler
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }
}

struct HotKey {
    let id: UInt32
    let keyCode: Int
    let display: String
    let description: String

    static let modifiers = controlKey | optionKey

    // ⌃⌥Space is avoided on purpose: macOS uses it for "next input source".
    static let toggleTracking = HotKey(id: 1, keyCode: kVK_ANSI_T, display: "⌃⌥T", description: "Pause / resume head tracking")
    static let scrollMode = HotKey(id: 2, keyCode: kVK_ANSI_S, display: "⌃⌥S", description: "Toggle scroll mode")
    static let recenter = HotKey(id: 3, keyCode: kVK_ANSI_C, display: "⌃⌥C", description: "Recenter cursor on screen")
    static let drag = HotKey(id: 4, keyCode: kVK_ANSI_D, display: "⌃⌥D", description: "Start / drop a drag")

    static let readingMode = HotKey(id: 5, keyCode: kVK_ANSI_R, display: "⌃⌥R", description: "Enter / exit Reading Mode")
    static let readingPlayback = HotKey(id: 6, keyCode: kVK_ANSI_P, display: "⌃⌥P", description: "Start / pause reading over a document")
    static let readingForward = HotKey(id: 7, keyCode: kVK_ANSI_N, display: "⌃⌥N", description: "Reading: step forward")
    static let readingBack = HotKey(id: 8, keyCode: kVK_ANSI_B, display: "⌃⌥B", description: "Reading: back a little")

    static let all = [toggleTracking, scrollMode, recenter, drag, readingMode, readingPlayback, readingForward, readingBack]
}
