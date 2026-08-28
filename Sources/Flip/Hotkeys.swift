import AppKit
import Carbon.HIToolbox

/// A shortcut, stored as the raw key code plus Carbon modifier mask. The label is captured at
/// the same time as the key so there is no need to map key codes back to characters, which
/// depends on the active keyboard layout.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var display: String {
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "\u{2303}" }
        if carbonModifiers & UInt32(optionKey) != 0 { out += "\u{2325}" }
        if carbonModifiers & UInt32(shiftKey) != 0 { out += "\u{21E7}" }
        if carbonModifiers & UInt32(cmdKey) != 0 { out += "\u{2318}" }
        return out + keyLabel
    }

    static let standard = HotkeyBinding(keyCode: UInt32(kVK_ANSI_Quote),
                                        carbonModifiers: UInt32(optionKey | cmdKey),
                                        keyLabel: "'")

    /// Builds a binding from a captured key press. Returns nil for a press that would make a
    /// useless global shortcut, that is one with no command, option or control.
    static func from(event: NSEvent) -> HotkeyBinding? {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let needsOne = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        guard modifiers & needsOne != 0 else { return nil }

        let label = HotkeyBinding.label(for: event)
        guard !label.isEmpty else { return nil }
        return HotkeyBinding(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, keyLabel: label)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "\u{21A9}", kVK_Tab: "\u{21E5}",
        kVK_Delete: "\u{232B}", kVK_ForwardDelete: "\u{2326}", kVK_Escape: "\u{238B}",
        kVK_LeftArrow: "\u{2190}", kVK_RightArrow: "\u{2192}",
        kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}",
        kVK_Home: "\u{2196}", kVK_End: "\u{2198}",
        kVK_PageUp: "\u{21DE}", kVK_PageDown: "\u{21DF}",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static func label(for event: NSEvent) -> String {
        if let named = namedKeys[Int(event.keyCode)] { return named }
        // charactersIgnoringModifiers still folds in shift, so ask for the unshifted character.
        let raw = event.charactersIgnoringModifiers ?? ""
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Key \(event.keyCode)" }
        return cleaned.uppercased()
    }
}

/// System-wide shortcuts via Carbon RegisterEventHotKey. Works while any app is frontmost and
/// needs no entitlement beyond Accessibility, which the paste path requires anyway.
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum Registration: Equatable {
        case ok
        case alreadyTaken          // another app owns this combination
        case failed(OSStatus)

        var isOK: Bool { self == .ok }

        var explanation: String {
            switch self {
            case .ok: return "registered"
            case .alreadyTaken: return "already taken by another app"
            case .failed(let status): return "failed, Carbon status \(status)"
            }
        }
    }

    static let signature: OSType = 0x464C4950 // 'FLIP'

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef?] = [:]
    private var bindings: [UInt32: HotkeyBinding] = [:]
    private var installed = false

    /// Registration outcome per shortcut label, for the UI and for --doctor.
    private(set) var registrations: [String: Registration] = [:]

    private init() {}

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard status == noErr else { return noErr }
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire(id: hkID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(id: UInt32, binding: HotkeyBinding, handler: (() -> Void)? = nil) -> Registration {
        install()
        if let handler { handlers[id] = handler }

        if let existing = refs[id], let ref = existing {
            UnregisterEventHotKey(ref)
            if let old = bindings[id] { registrations.removeValue(forKey: old.display) }
        }
        refs.removeValue(forKey: id)
        bindings[id] = binding

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.carbonModifiers,
                                         EventHotKeyID(signature: HotkeyManager.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        refs[id] = ref

        let outcome: Registration
        if status == noErr && ref != nil {
            outcome = .ok
        } else if status == OSStatus(eventHotKeyExistsErr) {
            outcome = .alreadyTaken
        } else {
            outcome = .failed(status)
        }
        registrations[binding.display] = outcome
        return outcome
    }

    func unregisterAll() {
        for (_, ref) in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        registrations.removeAll()
        bindings.removeAll()
    }

    func registration(for binding: HotkeyBinding) -> Registration? {
        registrations[binding.display]
    }

    private func fire(id: UInt32) { handlers[id]?() }
}
