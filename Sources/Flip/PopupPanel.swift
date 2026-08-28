import AppKit
import SwiftUI

enum PopupState: Equatable {
    case working(String)                 // status line, e.g. "Translating to English"
    case toast(String, Bool)             // message, isError
    case result(source: String, translated: String, meta: String)
}

@MainActor
final class PopupModel: ObservableObject {
    @Published var state: PopupState = .working("")
    @Published var showOriginal = false
    @Published var copied = false
    /// Height of the scrolling text area, measured from the text itself and capped.
    @Published var contentHeight: CGFloat = 60
}

/// Floating, non-activating panel. It must never take key focus away from the app the user
/// is typing in, otherwise the synthetic command+V would land in the panel instead of Slack.
@MainActor
final class PopupPanel {
    static let shared = PopupPanel()

    private var panel: NSPanel?
    private let model = PopupModel()
    private var escMonitor: Any?
    private var clickMonitor: Any?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Public API

    func showWorking(_ status: String) {
        model.showOriginal = false
        model.copied = false
        model.state = .working(status)
        present(interactive: false)
        scheduleDismiss(after: 25) // safety net if a request never returns
    }

    func showToast(_ message: String, isError: Bool) {
        model.state = .toast(message, isError)
        present(interactive: false)
        scheduleDismiss(after: isError ? 6 : 1.2)
    }

    func showResult(source: String, translated: String, meta: String) {
        model.showOriginal = false
        model.copied = false
        model.state = .result(source: source, translated: translated, meta: meta)
        model.contentHeight = measuredHeight()
        present(interactive: true)
        cancelDismiss()
    }

    fileprivate func toggleOriginal() {
        model.showOriginal.toggle()
        model.contentHeight = measuredHeight()
        present(interactive: true)
        cancelDismiss()
    }

    private static let textWidth: CGFloat = 352

    /// Lays the strings out with the same fonts the view uses, so the panel is never
    /// taller or shorter than the text it holds.
    private func measuredHeight() -> CGFloat {
        guard case .result(let source, let translated, _) = model.state else { return 60 }
        var height = Self.height(of: translated, fontSize: 13.5)
        if model.showOriginal {
            height += 10 + 1 + 10 + Self.height(of: source, fontSize: 12)
        }
        return min(max(height, 22), 300)
    }

    private static func height(of text: String, fontSize: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize)
        ])
        let rect = attributed.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + 2
    }

    func hide() {
        cancelDismiss()
        removeMonitors()
        panel?.orderOut(nil)
    }

    // MARK: - Panel plumbing

    private func present(interactive: Bool) {
        let panel = ensurePanel()
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 380, height: 120)
        let width = max(300, min(420, size.width))
        let height = max(56, min(460, size.height))

        let origin = anchorPoint(for: NSSize(width: width, height: height))
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        panel.orderFrontRegardless()

        installMonitors(dismissOnOutsideClick: interactive)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                              styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        created.isFloatingPanel = true
        created.level = .floating
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.animationBehavior = .utilityWindow

        let root = PopupView(model: model,
                             onCopy: { [weak self] text in self?.copy(text) },
                             onToggleOriginal: { [weak self] in self?.toggleOriginal() },
                             onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        created.contentView = hosting
        panel = created
        return created
    }

    /// Anchor just below and right of the pointer, clamped to the active screen.
    private func anchorPoint(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mouse.x + 14
        var y = mouse.y - size.height - 14
        if x + size.width > visible.maxX - 8 { x = mouse.x - size.width - 14 }
        if x < visible.minX + 8 { x = visible.minX + 8 }
        if y < visible.minY + 8 { y = mouse.y + 18 }
        if y + size.height > visible.maxY - 8 { y = visible.maxY - size.height - 8 }
        return NSPoint(x: x, y: y)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        model.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.model.copied = false }
    }

    // MARK: - Dismissal

    private func scheduleDismiss(after seconds: TimeInterval) {
        cancelDismiss()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func installMonitors(dismissOnOutsideClick: Bool) {
        removeMonitors()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.hide() } }   // esc
        }
        guard dismissOnOutsideClick else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        escMonitor = nil
        clickMonitor = nil
    }
}

// MARK: - View

struct PopupView: View {
    @ObservedObject var model: PopupModel
    let onCopy: (String) -> Void
    let onToggleOriginal: () -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .working(let status):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)

            case .toast(let message, let isError):
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? Color.orange : Color.green)
                        .font(.system(size: 13))
                    Text(message)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)

            case .result(let source, let translated, let meta):
                VStack(alignment: .leading, spacing: 9) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(translated)
                                .font(.system(size: 13.5))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if model.showOriginal {
                                Divider()
                                Text(source)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: model.contentHeight)

                    HStack(spacing: 8) {
                        Text(meta).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Button(model.showOriginal ? "Hide original" : "Original") {
                            onToggleOriginal()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                        Button(model.copied ? "Copied" : "Copy") { onCopy(translated) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(model.copied ? Color.green : Color.accentColor)

                        Button { onClose() } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}
