import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @State private var copiedID: UUID?
    @State private var confirmingClear = false

    private var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.source.lowercased().contains(q)
            || $0.translated.lowercased().contains(q)
            || ($0.appName ?? "").lowercased().contains(q)
        }
    }

    private var grouped: [(String, [HistoryEntry])] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [HistoryEntry]] = [:]
        for entry in filtered {
            let key: String
            if calendar.isDateInToday(entry.date) { key = "Today" }
            else if calendar.isDateInYesterday(entry.date) { key = "Yesterday" }
            else { key = Self.dayFormatter.string(from: entry.date) }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.0) { day, entries in
                            Section {
                                ForEach(entries) { entry in
                                    row(entry)
                                    Divider().opacity(0.4)
                                }
                            } header: {
                                Text(day)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 18).padding(.vertical, 7)
                                    .background(.regularMaterial)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 620, height: 620)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Text("History").font(.system(size: 14, weight: .semibold))
            Text("\(store.entries.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.14), in: Capsule())
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 170)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            if confirmingClear {
                Button("Confirm") { store.clear(); confirmingClear = false }
                    .foregroundStyle(.red)
                Button("Cancel") { confirmingClear = false }
            } else {
                Button("Clear all") { confirmingClear = true }
                    .disabled(store.entries.isEmpty)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No translations yet" : "No match")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Select text anywhere, then press \(HotkeyManager.replaceCombo.display) or \(HotkeyManager.peekCombo.display).")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let isOpen = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(Self.timeFormatter.string(from: entry.date))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                badge(entry.mode.label, entry.mode == .replace ? Color.blue : Color.purple)
                if let app = entry.appName {
                    Text(app).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Text(entry.targetLabel).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(entry.model) \u{00B7} \(entry.latencyMs) ms")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Button(copiedID == entry.id ? "Copied" : "Copy") { copy(entry) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(copiedID == entry.id ? Color.green : Color.accentColor)
                Button { store.delete(entry) } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            Text(entry.translated)
                .font(.system(size: 13))
                .lineLimit(isOpen ? nil : 3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.source)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(isOpen ? nil : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    private func copy(_ entry: HistoryEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.translated, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM yyyy"; return f
    }()
}
