import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var busy = false

    private let workQueue = DispatchQueue(label: "video.cutback.flip.work", qos: .userInitiated)
    private var hotkeyObservers: [AnyCancellable] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        registerHotkeys()

        // Rebinding in Settings takes effect immediately.
        let settings = Settings.shared
        let reregister: (Any) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.registerHotkeys() }
        }
        hotkeyObservers = [
            settings.$replaceHotkey.dropFirst().sink(receiveValue: reregister),
            settings.$peekHotkey.dropFirst().sink(receiveValue: reregister),
            settings.$autoHotkey.dropFirst().sink(receiveValue: reregister),
            settings.$shortcutMode.dropFirst().sink(receiveValue: reregister)
        ]

        // Launching the app a second time reaches Settings even when a menu bar manager
        // such as Ice has collapsed the status icon out of sight.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("video.cutback.flip.openSettings"),
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.openSettings() }
            }

        // Record what this process can actually do, so --doctor reports the app's answer
        // instead of inheriting the terminal's permissions and reporting its own.
        StatusWriter.start()

        if !TextAccess.hasAccessibilityPermission() {
            TextAccess.requestAccessibilityPermission()
        }

        // Launching Flip is a deliberate act: it has no window of its own to return to, and a
        // menu bar manager may be hiding its icon, so opening Settings is the only thing a
        // launch can usefully do. (If this ever becomes a login item, that launch should pass
        // --background and skip this.)
        if !flipArguments.contains("--background") {
            openSettings()
        }
    }

    /// Fires when the app is launched or clicked while already running, which is what Spotlight,
    /// Launchpad and the Dock do rather than starting a second process.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    private func registerHotkeys() {
        let settings = Settings.shared
        HotkeyManager.shared.unregisterAll()
        if settings.shortcutMode == .automatic {
            HotkeyManager.shared.register(id: 3, binding: settings.autoHotkey) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.run(trigger: .auto) }
            }
        } else {
            HotkeyManager.shared.register(id: 1, binding: settings.replaceHotkey) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.run(trigger: .replace) }
            }
            HotkeyManager.shared.register(id: 2, binding: settings.peekHotkey) { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.run(trigger: .peek) }
            }
        }
        StatusWriter.write()
        statusItem?.menu = menu()
    }

    // MARK: - Main menu

    /// A menu bar app has no main menu by default, and macOS routes the standard editing
    /// shortcuts through it. Without an Edit menu, command+V does nothing in the API key
    /// field even though right click, paste works, because that uses the field's own
    /// context menu. These items carry no code: the responder chain handles the selectors.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "History...", action: #selector(openHistory), keyEquivalent: "y").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Flip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Flip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = NSMenuItem(title: "Paste and Match Style",
                                    action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatch)
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
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
        menu.addItem(shortcutHint(settings.shortcutMode == .automatic
                                  ? settings.autoHotkey.display + "  replaces the text when you are in a field"
                                  : settings.replaceHotkey.display + "  replaces the text in place"))

        let peek = NSMenuItem(title: "Show translation in \(settings.resolvedTarget(for: .peek).label)",
                              action: #selector(menuPeek), keyEquivalent: "")
        peek.target = self
        menu.addItem(peek)
        menu.addItem(shortcutHint(settings.shortcutMode == .automatic
                                  ? settings.autoHotkey.display + "  opens a popup when you are not"
                                  : settings.peekHotkey.display + "  opens a popup"))

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

    @objc private func menuReplace() { Task { @MainActor in await run(trigger: .replace) } }
    @objc private func menuPeek() { Task { @MainActor in await run(trigger: .peek) } }

    // MARK: - The two pipelines

    enum Trigger { case replace, peek, auto }

    private func run(trigger: Trigger) async {
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
        let appName = TextAccess.frontmostAppName()

        // Never read or overwrite a password field, whichever shortcut was pressed.
        if await offMain({ TextAccess.focusInfo().isSecure }) {
            PopupPanel.shared.showToast(
                "That is a password field. Flip will not read it or paste over it.", isError: true)
            return
        }

        // --- work out what to do and what text to work on ---
        var snapshot: TextAccess.ClipboardSnapshot?
        var source: String?
        var mode: Mode

        switch trigger {
        case .peek:
            mode = .peek
            PopupPanel.shared.showWorking("Translating into \(settings.resolvedTarget(for: mode).label)")
            source = await offMain { TextAccess.accessibilitySelectedText() }
            if source == nil {
                let saved = await offMain { TextAccess.snapshotClipboard() }
                source = await offMain { TextAccess.copySelection(selectAllIfEmpty: false) }
                await offMain { TextAccess.restoreClipboard(saved) }
            }

        case .replace:
            mode = .replace
            PopupPanel.shared.showWorking("Translating into \(settings.resolvedTarget(for: mode).label)")
            let saved = await offMain { TextAccess.snapshotClipboard() }
            source = await offMain { TextAccess.copySelection(selectAllIfEmpty: true) }
            snapshot = saved

        case .auto:
            // Fast path: the focused element told us where the selection is, so nothing needs
            // to touch the clipboard to find out.
            if let decision = await offMain({ AutoMode.decideFromAccessibility() }) {
                mode = decision.mode
                if case .replaceSelection(let text) = decision {
                    source = text
                    snapshot = await offMain { TextAccess.snapshotClipboard() }
                } else if case .popup(let text) = decision {
                    source = text
                }
            } else {
                let saved = await offMain { TextAccess.snapshotClipboard() }
                let copied = await offMain { TextAccess.copySelection(selectAllIfEmpty: false) }
                let decision = await offMain { AutoMode.decideAfterCopy(copied: copied) }
                mode = decision.mode
                switch decision {
                case .replaceSelection(let text):
                    source = text
                    snapshot = saved
                case .replaceWholeField:
                    source = await offMain { TextAccess.copySelection(selectAllIfEmpty: true) }
                    snapshot = saved
                case .popup(let text):
                    source = text
                    await offMain { TextAccess.restoreClipboard(saved) }
                case .nothing, .refuseSecure:
                    source = nil
                    await offMain { TextAccess.restoreClipboard(saved) }
                }
            }
            PopupPanel.shared.showWorking("Translating into \(settings.resolvedTarget(for: mode).label)")
        }

        let target = settings.resolvedTarget(for: mode)

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
                                        size: NSSize(width: 580, height: 830))
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
