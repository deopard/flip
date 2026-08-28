import AppKit

/// Remembers the rectangle of the last mouse drag.
///
/// Accessibility gives an exact glyph rectangle when an app answers for it, but many do not.
/// Slack's focused element is an `AXGroup` that reports a selected range and then refuses to
/// give bounds for it. Web content answers a different family of queries, and some apps answer
/// neither.
///
/// A drag, on the other hand, is observable everywhere: the pointer went down at one corner of
/// the text and came up at the other. That rectangle is where the selection is, in every app,
/// with no cooperation required.
@MainActor
final class DragTracker {
    static let shared = DragTracker()

    private var downPoint: NSPoint?
    private var lastDrag: (rect: NSRect, at: Date)?
    private var monitors: [Any] = []

    /// Ignore a click that never moved: that is a caret placement, not a selection.
    private let minimumDistance: CGFloat = 6
    /// A drag from ten minutes ago says nothing about what is selected now.
    private let staleAfter: TimeInterval = 120

    private init() {}

    func start() {
        guard monitors.isEmpty else { return }
        // `locationInWindow` is meaningless for a global monitor: there is no window, and it
        // comes back as zero, which reads as a click that never moved. `NSEvent.mouseLocation`
        // is the screen position, and it must be read inside the callback rather than inside a
        // Task, because by the time a Task runs the pointer has moved on.
        // Global monitor callbacks arrive on the main thread, so mutate directly. Hopping
        // through `Task { @MainActor in ... }` would put the down and the up in separately
        // scheduled tasks with no ordering between them, and an up processed before its down
        // finds no start point and discards the drag.
        let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.downPoint = NSEvent.mouseLocation }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(at: NSEvent.mouseLocation) }
        }
        monitors = [down, up].compactMap { $0 }
    }

    private func finish(at end: NSPoint) {
        defer { downPoint = nil }
        guard let start = downPoint else { return }
        let dx = abs(end.x - start.x), dy = abs(end.y - start.y)
        guard hypot(dx, dy) >= minimumDistance else { return }

        // A drag across several lines starts and ends mid-line, so the rectangle between the
        // two points understates the selection horizontally. It is still the right place to
        // hang a panel: it spans what was dragged over.
        let rect = NSRect(x: min(start.x, end.x),
                          y: min(start.y, end.y),
                          width: max(dx, 1),
                          height: max(dy, 1))
        lastDrag = (rect, Date())
    }

    /// The last drag rectangle, if one happened recently enough to still describe the selection.
    var recentDragRect: NSRect? {
        guard let lastDrag, Date().timeIntervalSince(lastDrag.at) < staleAfter else { return nil }
        return lastDrag.rect
    }

    var report: String {
        guard let lastDrag else { return "no drag recorded yet" }
        let age = Int(Date().timeIntervalSince(lastDrag.at))
        let r = lastDrag.rect
        return "x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width)) h=\(Int(r.height))  (\(age)s ago)"
    }
}
