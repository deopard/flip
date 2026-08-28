import AppKit
import ApplicationServices
import Foundation

/// `Flip --doctor` prints everything that has to be true for the shortcuts to work.
///
/// Accessibility and hotkey state are read from the status file the running app writes, not
/// checked in this process, because both are per-process facts that a command-line tool would
/// answer for itself rather than for the app. Start Flip before running this.
@MainActor
enum Doctor {

    static func run() {
        let settings = Settings.shared
        var problems: [String] = []

        print("Flip doctor")
        print(String(repeating: "-", count: 58))

        // 1. Which copies are running
        let bundleID = "video.cutback.flip"
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != mine
        }
        if others.isEmpty {
            print("running copies      none (good, the hotkey probe below is meaningful)")
        } else {
            let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
            print("running copies      \(others.count) (pid \(pids))")
            print("                    quit it before trusting the hotkey lines below")
        }

        // 2. Accessibility, as answered by the app itself.
        //
        // Deliberately NOT AXIsProcessTrusted() in this process. Accessibility trust belongs
        // to the asking process. A command-line tool started from a terminal that already holds
        // the permission inherits it and would report "granted" whatever the app bundle is
        // actually allowed to do. Only the running app can answer for the running app.
        let status = FlipStatus.read()
        if let status, status.isLive {
            let age = Int(Date().timeIntervalSince(status.updatedAt))
            print("accessibility       \(status.accessibility ? "granted" : "NOT granted")   (reported by the running app \(age)s ago)")
            if !status.accessibility {
                problems.append("Flip is running but macOS is not letting it read your selection. Turn Flip on in System Settings, Privacy & Security, Accessibility. If the switch is already on, quit Flip and open it again: the permission is read when the app starts.")
            }
        } else if let status {
            print("accessibility       \(status.accessibility ? "granted" : "NOT granted")   (stale: last run, pid \(status.pid), is gone)")
            problems.append("Start Flip and run this again. The line above is from an earlier run.")
        } else {
            print("accessibility       unknown, Flip has not run yet")
            problems.append("Start Flip once, then run this again. This tool cannot check the permission on the app's behalf: run from a terminal it would inherit the terminal's own permissions and tell you nothing about the app.")
        }

        // 3. Hotkeys
        if let status, status.isLive, !status.hotkeys.isEmpty {
            for (combo, explanation) in status.hotkeys.sorted(by: { $0.key < $1.key }) {
                print("hotkey \(combo)            \(explanation)   (reported by the running app)")
            }
            let broken = status.hotkeys.filter { $0.value != "registered" }
            if !broken.isEmpty {
                problems.append("A shortcut is not free: \(broken.keys.joined(separator: ", ")). Something else on this Mac owns it. Check Raycast, Karabiner, Wispr Flow, Loom, and System Settings > Keyboard > Keyboard Shortcuts.")
            }
        } else {
            _ = NSApplication.shared
            let replace = HotkeyManager.shared.register(id: 901, combo: HotkeyManager.replaceCombo) {}
            let peek = HotkeyManager.shared.register(id: 902, combo: HotkeyManager.peekCombo) {}
            print("hotkey \(HotkeyManager.replaceCombo.display) replace   \(replace.explanation)   (probed here, Flip is not running)")
            print("hotkey \(HotkeyManager.peekCombo.display) peek      \(peek.explanation)   (probed here, Flip is not running)")
            if !replace.isOK || !peek.isOK {
                problems.append("A shortcut is not free. Something else on this Mac owns it: check Raycast, Karabiner, Wispr Flow, Loom, and System Settings > Keyboard > Keyboard Shortcuts.")
            }
        }

        // 4. Credentials and configuration
        print("provider            \(settings.provider.rawValue)")
        print("base URL            \(settings.baseURL)")
        print("model               \(settings.model)")
        let key = settings.apiKey
        print("API key             \(key.isEmpty ? "MISSING" : "present, \(key.count) characters")")
        if key.isEmpty {
            problems.append("No API key stored. Open the menu bar icon, then Settings, and paste one in.")
        } else {
            // Never print the key. Print only its shape.
            let scalars = Array(key.unicodeScalars)
            let nonASCII = scalars.enumerated().filter { !$0.element.isASCII }
            let control = scalars.enumerated().filter { $0.element.value < 0x20 || $0.element.value == 0x7F }
            let leadingSpace = key.first?.isWhitespace ?? false
            let trailingSpace = key.last?.isWhitespace ?? false
            let innerSpace = key.dropFirst().dropLast().contains { $0 == " " }
            print("  prefix            \(String(key.prefix(3)))")
            print("  non-ASCII chars   \(nonASCII.isEmpty ? "none" : nonASCII.map { "position \($0.offset) U+\(String(format: "%04X", $0.element.value))" }.joined(separator: ", "))")
            print("  control chars     \(control.isEmpty ? "none" : control.map { "position \($0.offset) U+\(String(format: "%04X", $0.element.value))" }.joined(separator: ", "))")
            print("  surrounding space \(leadingSpace || trailingSpace ? "yes" : "no")\(innerSpace ? ", and a space inside" : "")")

            // The definitive test: does URLRequest keep the header?
            var probe = URLRequest(url: URL(string: "https://example.invalid")!)
            probe.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let kept = probe.value(forHTTPHeaderField: "Authorization") != nil
            print("  header accepted   \(kept ? "yes" : "NO, Foundation dropped it")")
            if !kept {
                problems.append("The stored key contains a character that cannot go in an HTTP header, so the request is sent with no Authorization header at all. That is why the API says you did not provide a key. Re-paste the key with no line break, and check for a stray space or a non-Latin character.")
            }
            let cleaned = Settings.sanitize(key)
            if cleaned != key {
                print("  after cleaning    \(cleaned.count) characters, \(key.count - cleaned.count) removed")
            }
        }
        print("replace into        \(settings.resolvedTarget(for: .replace).label)")
        print("peek into           \(settings.resolvedTarget(for: .peek).label)")

        // 5. Menu bar visibility, which is easy to miss on a Mac running a menu bar manager
        let hiders = ["Ice", "Bartender", "Hidden Bar", "Vanilla", "Dozer"]
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        let found = hiders.filter { running.contains($0) }
        if !found.isEmpty {
            print("menu bar manager    \(found.joined(separator: ", ")) is running")
            problems.append("\(found.joined(separator: ", ")) hides menu bar icons. Flip's icon may be collapsed out of sight. Expand the menu bar or move Flip into the always-visible section.")
        }

        print(String(repeating: "-", count: 58))
        if problems.isEmpty {
            print("No problems found.")
        } else {
            print("\(problems.count) thing\(problems.count == 1 ? "" : "s") to fix:")
            for (index, problem) in problems.enumerated() {
                print("  \(index + 1). \(problem)")
            }
        }
    }
}
