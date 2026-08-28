import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the current selection out of whatever app is frontmost and pastes text back into it.
///
/// Two strategies:
///  - Accessibility (fast, does not touch the clipboard) - works in native apps and, when
///    Chromium has its accessibility tree enabled, in Electron apps such as Slack.
///  - Synthetic command+C / command+V (universal) - saves and restores the user's clipboard.
enum TextAccess {

    // MARK: - Permission

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Frontmost app

    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - Accessibility read

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.35)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        // CFTypeRef coming back from the AX API is an AXUIElement.
        return (element as! AXUIElement)
    }

    static func accessibilitySelectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: - Synthetic keystrokes

    private static func modifiersAreHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskAlternate)
            || flags.contains(.maskControl)
            || flags.contains(.maskShift)
            || flags.contains(.maskCommand)
    }

    /// The hotkey itself is option+command, so the physical keys are still down when we fire.
    /// Posting command+C on top of that would arrive as option+command+C. Wait them out.
    private static func waitForModifierRelease(timeout: TimeInterval = 0.6) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !modifiersAreHeld() { return }
            usleep(12_000)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(12_000)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard snapshot

    struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    static func snapshotClipboard() -> ClipboardSnapshot {
        let pb = NSPasteboard.general
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { payload[type] = data }
            }
            if !payload.isEmpty { snapshot.append(payload) }
        }
        return ClipboardSnapshot(items: snapshot)
    }

    static func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { payload -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in payload { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }

    // MARK: - Read

    /// Copies the current selection. If nothing is selected and `selectAllIfEmpty` is true,
    /// selects the whole focused field first (that is the "translate my whole input box" path).
    ///
    /// Returns the text and whether a select-all was needed.
    static func copySelection(selectAllIfEmpty: Bool) -> String? {
        waitForModifierRelease()
        let pb = NSPasteboard.general
        let before = pb.changeCount

        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        if let text = waitForClipboard(changedFrom: before),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        guard selectAllIfEmpty else { return nil }

        postKey(CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        usleep(40_000)
        let beforeSecond = pb.changeCount
        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        return waitForClipboard(changedFrom: beforeSecond)
    }

    private static func waitForClipboard(changedFrom before: Int, timeout: TimeInterval = 0.8) -> String? {
        let pb = NSPasteboard.general
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pb.changeCount != before {
                usleep(15_000) // let the source app finish writing every representation
                let text = pb.string(forType: .string)
                if let text, !text.isEmpty { return text }
                return nil
            }
            usleep(15_000)
        }
        return nil
    }

    // MARK: - Write

    /// Puts `text` on the clipboard, pastes it over the current selection, then restores
    /// whatever the user had on the clipboard before.
    static func paste(_ text: String, restoring snapshot: ClipboardSnapshot) {
        waitForModifierRelease(timeout: 0.3)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(30_000)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        // Give the target app time to consume the pasteboard before we put the old value back.
        usleep(350_000)
        restoreClipboard(snapshot)
    }
}
