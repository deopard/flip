import SwiftUI
import AppKit

/// Click, then press the combination you want. Escape cancels, delete clears back to the
/// default. While recording, key presses are swallowed so they do not reach the rest of the app.
struct HotkeyRecorder: View {
    @Binding var binding: HotkeyBinding
    let fallback: HotkeyBinding

    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys..." : binding.display)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minWidth: 92)
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .background(recording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(recording ? Color.accentColor : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            if recording {
                Text("esc to cancel")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            } else if binding != fallback {
                Button("Reset") { binding = fallback }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if rejected {
                Text("Needs \u{2318}, \u{2325} or \u{2303}")
                    .font(.system(size: 10.5)).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        rejected = false
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {                    // escape
                stop()
                return nil
            }
            if let captured = HotkeyBinding.from(event: event) {
                binding = captured
                stop()
            } else {
                rejected = true
            }
            return nil                                   // never let it through
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
