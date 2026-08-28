import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var busy = false

    private let workQueue = DispatchQueue(label: "video.cutback.flip.work", qos: .userInitiated)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

        HotkeyManager.shared.register(id: 1, combo: HotkeyManager.replaceCombo) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.run(mode: .replace) }
        }
        HotkeyManager.shared.register(id: 2, combo: HotkeyManager.peekCombo) { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.run(mode: .peek) }
        }

        // Launching the app a second time reaches Settings even when a menu bar manager
        // such as Ice has collapsed the status icon out of sight.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("video.cutback.flip.openSettings"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.openSettings() }
            }

        if !TextAccess.hasAccessibilityPermission() {
            TextAccess.requestAccessibilityPermission()
        }

        // Nothing works without a key, and the icon may be hidden, so say so up front.
        if !TextAccess.hasAccessibilityPermission() || Settings.shared.apiKey.isEmpty {
            openSettings()
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble",
                                     accessibilityDescription: "Flip")
        item.button?.image?.isTemplate = true
        item.menu = menu()
        statusItem = item
    }

    private func setBusyIcon(_ isBusy: Bool) {
        let name = isBusy ? "character.bubble.fill" : "character.bubble"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Flip")
        statusItem?.button?.image?.isTemplate = true
    }

    private func menu() -> NSMenu {
        let settings = Settings.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        let replace = NSMenuItem(title: "Translate selection into \(settings.resolvedTarget(for: .replace).label)",
                                 action: #selector(menuReplace), keyEquivalent: "")
        replace.target = self
        menu.addItem(replace)
        menu.addItem(shortcutHint(HotkeyManager.replaceCombo.display + "  replaces the text in place"))

        let peek = NSMenuItem(title: "Show translation in \(settings.resolvedTarget(for: .peek).label)",
                              action: #selector(menuPeek), keyEquivalent: "")
        peek.target = self
        menu.addItem(peek)
        menu.addItem(shortcutHint(HotkeyManager.peekCombo.display + "  opens a popup"))

        menu.addItem(.separator())

        let history = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        if !TextAccess.hasAccessibilityPermission() {
            let warn = NSMenuItem(title: "Accessibility permission needed", action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(title: "Quit Flip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func shortcutHint(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: "   " + text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        return item
    }

    @objc private func menuReplace() { Task { @MainActor in await run(mode: .replace) } }
    @objc private func menuPeek() { Task { @MainActor in await run(mode: .peek) } }

    // MARK: - The two pipelines

    private func run(mode: Mode) async {
        guard !busy else { return }

        guard TextAccess.hasAccessibilityPermission() else {
            TextAccess.requestAccessibilityPermission()
            PopupPanel.shared.showToast("Flip needs Accessibility access to read your selection. Grant it in System Settings > Privacy & Security > Accessibility.", isError: true)
            statusItem?.menu = menu()
            return
        }

        busy = true
        setBusyIcon(true)
        defer { busy = false; setBusyIcon(false) }

        let settings = Settings.shared
        let target = settings.resolvedTarget(for: mode)
        let appName = TextAccess.frontmostAppName()
        PopupPanel.shared.showWorking("Translating into \(target.label)")

        // --- read the selection ---
        var snapshot: TextAccess.ClipboardSnapshot?
        var source: String?

        if mode == .peek {
            source = await offMain { TextAccess.accessibilitySelectedText() }
        }
        if source == nil {
            let saved = await offMain { TextAccess.snapshotClipboard() }
            source = await offMain { TextAccess.copySelection(selectAllIfEmpty: mode == .replace) }
            if mode == .replace {
                snapshot = saved                      // give it back after we paste
            } else {
                await offMain { TextAccess.restoreClipboard(saved) }
            }
        }

        guard let text = source,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let snapshot { await offMain { TextAccess.restoreClipboard(snapshot) } }
            PopupPanel.shared.showToast(TranslatorError.emptyInput.localizedDescription, isError: true)
            return
        }

        // --- translate ---
        let outcome: TranslationOutcome
        do {
            outcome = try await Translator.translate(text: text, settings: settings, mode: mode)
        } catch {
            if let snapshot { await offMain { TextAccess.restoreClipboard(snapshot) } }
            PopupPanel.shared.showToast(error.localizedDescription, isError: true)
            if case TranslatorError.missingKey = error { openSettings() }
            return
        }

        // --- deliver ---
        switch mode {
        case .replace:
            let restore = snapshot ?? TextAccess.ClipboardSnapshot(items: [])
            let translated = outcome.text
            await offMain { TextAccess.paste(translated, restoring: restore) }
            PopupPanel.shared.showToast("Replaced with \(target.label)", isError: false)
        case .peek:
            PopupPanel.shared.showResult(
                source: text,
                translated: outcome.text,
                meta: "\(outcome.model)  \u{00B7}  \(outcome.latencyMs) ms  \u{00B7}  \(appName ?? "selection")")
        }

        HistoryStore.shared.add(HistoryEntry(mode: mode,
                                             source: text,
                                             translated: outcome.text,
                                             targetLabel: target.label,
                                             model: outcome.model,
                                             latencyMs: outcome.latencyMs,
                                             appName: appName))
    }

    /// Runs blocking Accessibility / clipboard / synthetic-keystroke work off the main thread
    /// so the popup keeps animating.
    private func offMain<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume(returning: body()) }
        }
    }

    // MARK: - Windows

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Flip Settings",
                                        view: AnyView(SettingsView()),
                                        size: NSSize(width: 580, height: 740))
        }
        show(settingsWindow)
    }

    @objc func openHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(title: "Flip History",
                                       view: AnyView(HistoryView()),
                                       size: NSSize(width: 620, height: 620))
        }
        show(historyWindow)
    }

    private func makeWindow(title: String, view: AnyView, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        return window
    }

    /// A menu bar (accessory) app is not allowed to pull focus from the app the user is in,
    /// so the window would open behind whatever is frontmost. Becoming a regular app for the
    /// lifetime of the window is the supported way to get a real, focused window; the Dock
    /// icon disappears again as soon as the last window closes.
    private func show(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        // The policy change only takes effect on the next run loop pass. Activating in the
        // same pass leaves the window behind whatever the user is currently in.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            Self.center(window, onScreenAt: NSEvent.mouseLocation)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        statusItem?.menu = menu()
    }

    /// Centers on the display the pointer is on. `NSWindow.center()` uses the main display,
    /// which on a two-display setup puts the window where the user is not looking.
    private static func center(_ window: NSWindow, onScreenAt point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: visible.midY - size.height / 2))
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu bar only once nothing is left open.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stillOpen = [self.settingsWindow, self.historyWindow]
                .compactMap { $0 }
                .contains { $0.isVisible }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
