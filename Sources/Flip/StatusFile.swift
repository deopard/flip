import Foundation
import AppKit

/// The menu bar app records what it can actually do here, so `--doctor` can report the app's
/// own answer rather than its own.
///
/// This matters because `AXIsProcessTrusted()` is a property of the asking process, not of the
/// app bundle. A command-line process launched from a terminal that already holds Accessibility
/// permission inherits it, so a diagnostic that checks trust in its own process reports
/// "granted" no matter what the app bundle is actually allowed to do. Only the running app can
/// answer for the running app.
struct FlipStatus: Codable {
    var accessibility: Bool
    var hotkeys: [String: String]
    var pid: Int32
    var updatedAt: Date
    var lastDrag: String?

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flip", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("status.json")
    }

    static func read() -> FlipStatus? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FlipStatus.self, from: data)
    }

    /// True when the process that wrote this file is still alive.
    var isLive: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == pid }
    }
}

@MainActor
enum StatusWriter {
    private static var timer: Timer?

    static func start() {
        write()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in write() }
        }
    }

    static func write() {
        var hotkeys: [String: String] = [:]
        for (combo, registration) in HotkeyManager.shared.registrations {
            hotkeys[combo] = registration.explanation
        }
        let status = FlipStatus(accessibility: TextAccess.hasAccessibilityPermission(),
                                hotkeys: hotkeys,
                                pid: ProcessInfo.processInfo.processIdentifier,
                                updatedAt: Date(),
                                lastDrag: DragTracker.shared.report)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(status) else { return }
        try? data.write(to: FlipStatus.fileURL, options: .atomic)
    }
}
