import AppKit
import SwiftUI

/// Renders the app's SwiftUI surfaces straight to PNG, without needing a visible screen.
/// Used to review the interface during development: `Flip --screenshot <dir>`.
@MainActor
enum ScreenshotRenderer {

    static func renderAll(into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try render(AnyView(SettingsView()),
                   size: NSSize(width: 580, height: 740),
                   to: directory.appendingPathComponent("settings.png"))

        try render(AnyView(HistoryView(store: HistoryStore(sample: sampleEntries()))),
                   size: NSSize(width: 620, height: 620),
                   to: directory.appendingPathComponent("history.png"))

        try render(AnyView(popup(.working("Translating into English")).padding(24)),
                   size: NSSize(width: 428, height: 100),
                   to: directory.appendingPathComponent("popup-working.png"))

        try render(AnyView(popup(.toast("Replaced with English", false)).padding(24)),
                   size: NSSize(width: 428, height: 100),
                   to: directory.appendingPathComponent("popup-replaced.png"))

        try render(AnyView(popup(.toast("API returned HTTP 401. Incorrect API key provided.", true)).padding(24)),
                   size: NSSize(width: 428, height: 120),
                   to: directory.appendingPathComponent("popup-error.png"))

        let result = PopupState.result(
            source: "Heads up: the Selects trial for the enterprise account expires on Friday, so we need the renewal quote out by Thursday morning at the latest.",
            translated: "참고로 엔터프라이즈 계정의 Selects 트라이얼이 금요일에 만료됩니다. 늦어도 목요일 오전까지는 갱신 견적을 보내야 합니다.",
            meta: "luna-med  \u{00B7}  820 ms  \u{00B7}  Slack")
        try render(AnyView(popup(result, showOriginal: true, contentHeight: 118).padding(24)),
                   size: NSSize(width: 428, height: 226),
                   to: directory.appendingPathComponent("popup-result.png"))
    }

    // MARK: - Helpers

    private static func popup(_ state: PopupState, showOriginal: Bool = false,
                              contentHeight: CGFloat = 60) -> some View {
        let model = PopupModel()
        model.state = state
        model.showOriginal = showOriginal
        model.contentHeight = contentHeight
        return PopupView(model: model, onCopy: { _ in }, onToggleOriginal: {}, onClose: {})
    }

    private static func render(_ view: AnyView, size: NSSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        // A real window makes materials, vibrancy and control appearance render correctly.
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "Flip", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not allocate bitmap for \(url.lastPathComponent)"])
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Flip", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "could not encode \(url.lastPathComponent)"])
        }
        try data.write(to: url)
        FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
    }

    private static func sampleEntries() -> [HistoryEntry] {
        let now = Date()
        return [
            HistoryEntry(mode: .replace,
                         source: "이번 주 금요일까지 갱신 견적서 보내드리겠습니다. 확인 부탁드립니다.",
                         translated: "I will send the renewal quote by this Friday. Please take a look when you get a chance.",
                         targetLabel: "English", model: "luna-med", latencyMs: 740,
                         appName: "Slack", date: now.addingTimeInterval(-360)),
            HistoryEntry(mode: .peek,
                         source: "We are seeing a spike in failed exports on the desktop client since the 3.2 release. Can someone take a look before EOD?",
                         translated: "3.2 릴리스 이후 데스크톱 클라이언트에서 내보내기 실패가 급증하고 있습니다. 오늘 퇴근 전에 누가 좀 봐주실 수 있을까요?",
                         targetLabel: "Korean", model: "luna-med", latencyMs: 910,
                         appName: "Slack", date: now.addingTimeInterval(-2_700)),
            HistoryEntry(mode: .replace,
                         source: "안녕하세요. 다음 주 화요일 오후 2시에 데모 진행 가능하신지 여쭙습니다.",
                         translated: "Hi, would you be available for a demo next Tuesday at 2pm?",
                         targetLabel: "English", model: "luna-med", latencyMs: 680,
                         appName: "Gmail", date: now.addingTimeInterval(-9_000)),
            HistoryEntry(mode: .peek,
                         source: "Attached is the signed order form. Procurement will process the invoice within 30 days of receipt.",
                         translated: "서명된 주문서를 첨부합니다. 구매팀에서 수령 후 30일 이내에 인보이스를 처리할 예정입니다.",
                         targetLabel: "Korean", model: "luna-med", latencyMs: 1_020,
                         appName: "Mail", date: now.addingTimeInterval(-95_000)),
            HistoryEntry(mode: .replace,
                         source: "리텐션 코호트 쿼리 결과 공유드립니다. 2주차 잔존율이 예상보다 높게 나왔습니다.",
                         translated: "Sharing the retention cohort query results. Week-2 retention came in higher than we expected.",
                         targetLabel: "English", model: "luna-med", latencyMs: 860,
                         appName: "Notion", date: now.addingTimeInterval(-101_000))
        ]
    }
}
