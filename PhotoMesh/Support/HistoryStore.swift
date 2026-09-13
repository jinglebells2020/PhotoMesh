import Foundation
import Observation

struct HistoryEntry: Identifiable, Codable, Hashable {
    enum Origin: String, Codable { case scan, drawn }

    var id: UUID
    var date: Date
    var circuit: Circuit
    var question: String
    var headline: String
    var origin: Origin
}

/// Solved circuits, newest first, persisted as JSON in Application Support.
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []
    private let limit = 200
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("PhotoMesh", isDirectory: true).appendingPathComponent("history.json")
        }
        load()
    }

    /// Adds a solve, or moves an identical circuit back to the top.
    func remember(circuit: Circuit, analysis: CircuitAnalysis, origin: HistoryEntry.Origin) {
        var stored = circuit
        stored.notes = nil
        let headline = analysis.methods.first?.answers.first.map { "\($0.label): \($0.value)" } ?? analysis.methods.first?.headline ?? ""
        if let index = entries.firstIndex(where: { $0.circuit == stored }) {
            entries[index].date = Date()
            entries[index].headline = headline
            entries[index].question = analysis.question
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(HistoryEntry(id: UUID(), date: Date(), circuit: stored, question: analysis.question, headline: headline, origin: origin), at: 0)
            if entries.count > limit { entries.removeLast(entries.count - limit) }
        }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let snapshot = entries
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
