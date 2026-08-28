import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon RegisterEventHotKey. Works while any app is frontmost
/// and needs no extra entitlement beyond Accessibility (which the paste path needs anyway).
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    static let signature: OSType = 0x4E554E43 // 'FLIP'

    struct Combo {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let display: String
    }

    enum Registration: Equatable {
        case ok
        case alreadyTaken          // another app owns this combo
        case failed(OSStatus)

        var isOK: Bool { self == .ok }

        var explanation: String {
            switch self {
            case .ok:
                return "registered"
            case .alreadyTaken:
                return "already taken by another app"
            case .failed(let status):
                return "failed, Carbon status \(status)"
            }
        }
    }

    /// Registration outcome per combo display string, so the UI can report a dead shortcut.
    private(set) var registrations: [String: Registration] = [:]

    /// option + command + '
    static let replaceCombo = Combo(keyCode: UInt32(kVK_ANSI_Quote),
                                    carbonModifiers: UInt32(optionKey | cmdKey),
                                    display: "\u{2325}\u{2318}'")
    /// option + command + ;
    static let peekCombo = Combo(keyCode: UInt32(kVK_ANSI_Semicolon),
                                 carbonModifiers: UInt32(optionKey | cmdKey),
                                 display: "\u{2325}\u{2318};")

    private init() {}

    func install() {
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
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.fire(id: hkID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(id: UInt32, combo: Combo, handler: @escaping () -> Void) -> Registration {
        install()
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)

        let outcome: Registration
        if status == noErr && ref != nil {
            outcome = .ok
        } else if status == OSStatus(eventHotKeyExistsErr) {
            outcome = .alreadyTaken
        } else {
            outcome = .failed(status)
        }
        registrations[combo.display] = outcome
        return outcome
    }

    private func fire(id: UInt32) {
        handlers[id]?()
    }
}
