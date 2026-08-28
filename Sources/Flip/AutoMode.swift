import AppKit

/// Decides, for the shortcut, whether to replace the text in place or show a popup.
///
/// Two separate jobs, and Accessibility is only good at one of them.
///
/// **Where the selection is** is what separates the cases, and Accessibility answers it well.
/// Keyboard focus does not: in Slack, Discord, Notion and most chat apps focus stays in the
/// composer while you select text in a message you are reading, so a focus-based rule would
/// paste a translation of what you were reading into the box you were writing in.
///
/// **What the selected text actually is** must come from the clipboard. Chromium, and therefore
/// every Electron app, flattens its accessibility tree into a single line: `AXSelectedText`
/// comes back with every line break gone and U+FFFC in place of each emoji and mention. A
/// translation of that reads as one run-on paragraph. A synthetic copy returns the real text.
enum AutoMode {

    enum Decision {
        /// The selection sits inside the focused editable element; paste over it.
        case replaceSelection
        /// A cursor sits in a field with content but nothing is selected; take the whole field.
        case replaceWholeField
        /// Translate and show, changing nothing on screen.
        case popup
        case nothing
        /// A password field has focus. Refuse outright.
        case refuseSecure

        var mode: Mode {
            switch self {
            case .replaceSelection, .replaceWholeField: return .replace
            case .popup, .nothing, .refuseSecure: return .peek
            }
        }

        var explanation: String {
            switch self {
            case .replaceSelection: return "selection is inside the focused field, replacing in place"
            case .replaceWholeField: return "cursor is in a field with nothing selected, translating the whole field"
            case .popup: return "selection is not in an editable field, showing a popup"
            case .nothing: return "nothing selected and no editable field"
            case .refuseSecure: return "a password field has focus, refusing"
            }
        }
    }

    /// Called once a synthetic copy has produced the real text. `copied` is nil when nothing
    /// was selected anywhere.
    static func decide(copied: String?) -> Decision {
        let focus = TextAccess.focusInfo()
        if focus.isSecure { return .refuseSecure }

        let selection = normalize(copied ?? "")

        guard !selection.isEmpty else {
            // Nothing selected. Only useful when a cursor sits in a field.
            guard focus.isEditable else { return .nothing }
            if let value = TextAccess.accessibilityFocusValue() {
                return normalize(value).isEmpty ? .nothing : .replaceWholeField
            }
            return .replaceWholeField          // editable but its contents are not readable
        }

        guard focus.isEditable else { return .popup }

        // The field holds focus and something is selected. Decide whether that selection is
        // inside it. Both signals are compared after normalising, because the accessibility
        // strings and the clipboard disagree about whitespace and embedded objects.
        if let axSelection = TextAccess.accessibilitySelectedText(),
           !normalize(axSelection).isEmpty {
            // The focused element claims the selection as its own.
            return .replaceSelection
        }
        if let value = TextAccess.accessibilityFocusValue(), !normalize(value).isEmpty {
            return normalize(value).contains(selection) ? .replaceSelection : .popup
        }

        // Nothing to compare against. Do not overwrite text on a guess.
        return .popup
    }

    /// Reports what would happen without touching the clipboard, for `--probe-focus`. The text
    /// is not read here, so this cannot distinguish a selection inside the field from one
    /// outside it; it reports the focus half only.
    static func focusOnlyDescription() -> String {
        let focus = TextAccess.focusInfo()
        if focus.isSecure { return Decision.refuseSecure.explanation }
        return focus.isEditable
            ? "focus is editable, so a selection inside it would be replaced in place"
            : "focus is not editable, so any selection would open the popup"
    }

    /// U+FFFC stands in for an emoji or mention chip in an accessibility string and means
    /// nothing to a translator. Whitespace differs between the two sources, so it is collapsed
    /// for comparison only, never in the text that gets translated.
    static func normalize(_ text: String) -> String {
        let withoutObjects = text.replacingOccurrences(of: "\u{FFFC}", with: " ")
        return withoutObjects
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cleans a source string before it is translated: object placeholders removed, real line
    /// breaks kept exactly as they were.
    static func cleanForTranslation(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
    }
}
