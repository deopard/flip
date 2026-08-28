import SwiftUI
import AppKit

/// A dropdown you can also type into. SwiftUI has no equivalent: `Picker` only offers the
/// listed choices, and a `TextField` offers no list. Model names and effort levels both need
/// both, because the useful values change faster than this app does.
struct ComboBoxField: NSViewRepresentable {
    @Binding var text: String
    let options: [String]
    var placeholder: String = ""

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.usesDataSource = false
        combo.completes = true
        combo.isEditable = true
        combo.delegate = context.coordinator
        combo.target = context.coordinator
        combo.action = #selector(Coordinator.valueChanged(_:))
        combo.font = .systemFont(ofSize: 12)
        combo.placeholderString = placeholder
        combo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if combo.objectValues as? [String] != options {
            combo.removeAllItems()
            combo.addItems(withObjectValues: options)
        }
        if combo.stringValue != text && !context.coordinator.isEditing {
            combo.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ComboBoxField
        var isEditing = false

        init(_ parent: ComboBoxField) { self.parent = parent }

        @objc func valueChanged(_ sender: NSComboBox) {
            parent.text = sender.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) { isEditing = true }

        func controlTextDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox,
                  combo.indexOfSelectedItem >= 0,
                  let value = combo.itemObjectValue(at: combo.indexOfSelectedItem) as? String else { return }
            // The field's own string is still the old one at this point.
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = value
                combo.stringValue = value
            }
        }
    }
}
