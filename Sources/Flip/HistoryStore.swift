import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let mode: Mode
    let source: String
    let translated: String
    let targetLabel: String
    let model: String
    let latencyMs: Int
    let appName: String?
    /// Time spent reading the selection before the request went out. The rest of what you feel
    /// is `latencyMs`, plus the paste afterwards.
    let readMs: Int?

    init(mode: Mode, source: String, translated: String, targetLabel: String,
         model: String, latencyMs: Int, appName: String?, readMs: Int? = nil, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.mode = mode
        self.source = source
        self.translated = translated
        self.targetLabel = targetLabel
        self.model = model
        self.latencyMs = latencyMs
        self.appName = appName
        self.readMs = readMs
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 2000
    private let fileURL: URL
    private let ephemeral: Bool

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flip", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        ephemeral = false
        load()
    }

    /// In-memory store used for offscreen rendering. Never touches the real history file.
    init(sample entries: [HistoryEntry]) {
        fileURL = URL(fileURLWithPath: "/dev/null")
        ephemeral = true
        self.entries = entries
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    var storageDescription: String { fileURL.path }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard !ephemeral else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
