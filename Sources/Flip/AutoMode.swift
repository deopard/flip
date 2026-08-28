import AppKit

/// Decides, for the single shortcut, whether to replace the text in place or show a popup.
///
/// Keyboard focus alone is not enough. In Slack, Discord, Notion and most chat apps, focus stays
/// in the composer while you select text in a message you are reading. Deciding on focus would
/// paste a translation of the message you were reading into the box you were writing in.
///
/// What actually separates the two cases is where the selection is. If the selection lives
/// inside the focused editable element, replacing it is what the user meant. If the selection is
/// anywhere else, or there is no editable focus at all, showing a popup is.
enum AutoMode {

    enum Decision {
        /// Text taken straight from the focused field; translate and paste over it.
        case replaceSelection(String)
        /// A cursor sits in a field with content but nothing is selected; take the whole field.
        case replaceWholeField
        /// Translate this and show it, changing nothing on screen.
        case popup(String)
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

    /// The part that needs no clipboard. Returns nil when the caller must fall back to a
    /// synthetic copy to find out what is selected.
    static func decideFromAccessibility() -> Decision? {
        let focus = focusInfo()
        if focus.isSecure { return .refuseSecure }
        let selected = TextAccess.accessibilitySelectedText()

        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The focused element reported its own selection, so we know exactly where it is.
            return focus.isEditable ? .replaceSelection(selected) : .popup(selected)
        }
        return nil
    }

    /// Called once the clipboard has told us what is actually selected, wherever it lives.
    ///
    /// `copied` is nil when a synthetic copy produced nothing, which means nothing is selected.
    static func decideAfterCopy(copied: String?) -> Decision {
        let focus = focusInfo()
        if focus.isSecure { return .refuseSecure }
        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmed.isEmpty else {
            // Nothing selected anywhere. Only useful if a cursor is sitting in a field.
            if focus.isEditable,
               let value = TextAccess.accessibilityFocusValue(),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .replaceWholeField
            }
            if focus.isEditable && focus.isUnknown == false {
                // Editable but we cannot read its contents; select-all and see.
                return .replaceWholeField
            }
            return .nothing
        }

        guard focus.isEditable else { return .popup(copied!) }

        // The field holds focus and something is selected, but the element did not report the
        // selection as its own. If its full value contains what was copied, the selection is
        // inside it after all; otherwise the user selected something elsewhere.
        if let value = TextAccess.accessibilityFocusValue(), !value.isEmpty {
            return value.contains(trimmed) ? .replaceSelection(copied!) : .popup(copied!)
        }

        // No value to compare against. Do not overwrite text on a guess.
        return .popup(copied!)
    }

    private static func focusInfo() -> TextAccess.FocusInfo { TextAccess.focusInfo() }
}
