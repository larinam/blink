import AppKit
import Carbon.HIToolbox

struct ShortcutDescription: Equatable {
    let key: String?
    var label: String { key.map { "⌃⌥⌘\($0)" } ?? "⌃⌥⌘ + U.S. B-position key" }
    var spoken: String {
        key.map { "Control–Option–Command–\($0)" }
            ?? "Control–Option–Command and the key at the B position on a U.S. keyboard"
    }
}

/// Registers one deliberate shortcut; it never observes ordinary keyboard input.
/// AppDelegate owns this for the application lifetime and calls stop() at termination.
/// The Carbon callback borrows this object: any future shorter-lived owner must call
/// stop() before releasing it, so the event handler cannot retain a dangling context.
@MainActor
final class GlobalShortcut {
    private(set) var description: ShortcutDescription
    var onDescriptionChange: ((ShortcutDescription) -> Void)?
    private static let identifier = EventHotKeyID(signature: 0x424C4E4B, id: 1)
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private var layoutObserver: NSObjectProtocol?
    private let keyLabel: @MainActor () -> String?

    init(keyLabel: @escaping @MainActor () -> String? = GlobalShortcut.currentKeyLabel) {
        self.keyLabel = keyLabel
        description = ShortcutDescription(key: keyLabel())
    }

    func start(action: @escaping () -> Void) -> Bool {
        stop()
        self.action = action
        refreshDescription()
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDescription() }
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                guard identifier.signature == GlobalShortcut.identifier.signature,
                      identifier.id == GlobalShortcut.identifier.id else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action?()
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { unregister(); return false }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey),
            Self.identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard registered == noErr else { unregister(); return false }
        return true
    }

    func stop() {
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        layoutObserver = nil
        unregister()
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }

    func refreshDescription() {
        let updated = ShortcutDescription(key: keyLabel())
        guard updated != description else { return }
        description = updated
        onDescriptionChange?(updated)
    }

    /// Translate only the one registered physical key; never observe typed input.
    private static func currentKeyLabel() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return keyLabel(for: source)
    }

    static func keyLabel(for source: TISInputSource) -> String? {
        guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        // Command-aware layouts (for example Russian or Dvorak–QWERTY⌘) use
        // a separate table for shortcut labels. Option's typed glyph is irrelevant.
        let command = UInt32((cmdKey >> 8) & 0xFF)
        let status = UCKeyTranslate(layout, UInt16(kVK_ANSI_B), UInt16(kUCKeyActionDisplay), command,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKey, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: characters, count: length).uppercased()
        guard !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return label
    }
}
