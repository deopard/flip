import AppKit

/// macOS evaluates Accessibility trust when a process starts and keeps that answer for the
/// life of the process. Granting the permission to a running app therefore does nothing until
/// it is restarted, which is a confusing dead end. This restarts it in place.
@MainActor
enum Relauncher {
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = ["--relaunched"]

        // Give the new instance a moment to come up, then exit, so the single-instance guard
        // in main.swift does not turn the new copy away.
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
            }
        }
    }
}
