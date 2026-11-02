import Foundation
import Combine

struct AIDramaHistoryEntry: Identifiable, Codable {
    let series: AIDramaSeries
    let episodeID: String
    let episodeNumber: Int?
    let position: Double
    let duration: Double
    let updatedAt: Date
    var id: String { series.id }
}

/// Only stable series/episode identities and progress are persisted, never a
/// video URL. Existing anime/movie history keys are not read or modified.
@MainActor
final class AIDramaHistoryStore: ObservableObject {
    static let shared = AIDramaHistoryStore()
    @Published private(set) var entries: [AIDramaHistoryEntry] = []
    private let defaults: UserDefaults
    private let key = "AnPinime.AIDrama.history.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AIDramaHistoryEntry].self, from: data) {
            var seen = Set<String>()
            entries = decoded.filter {
                !$0.series.id.isEmpty && !$0.episodeID.isEmpty && $0.position.isFinite && $0.duration.isFinite
                    && seen.insert($0.series.id).inserted
            }.sorted { $0.updatedAt > $1.updatedAt }
            entries = Array(entries.prefix(200))
        }
    }

    func record(series: AIDramaSeries, episode: AIDramaEpisode, position: Double, duration: Double) {
        guard episode.seriesID == series.id, position.isFinite, position > 0, duration.isFinite else { return }
        let entry = AIDramaHistoryEntry(series: series, episodeID: episode.id, episodeNumber: episode.number,
                                       position: max(0, position), duration: max(0, duration), updatedAt: Date())
        entries.removeAll { $0.id == series.id }
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        persist()
    }

    func refreshMetadata(for series: [AIDramaSeries]) {
        guard !entries.isEmpty else { return }
        let current = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var changed = false
        let updated = entries.map { entry -> AIDramaHistoryEntry in
            guard let item = current[entry.id], item != entry.series else { return entry }
            changed = true
            return AIDramaHistoryEntry(series: item, episodeID: entry.episodeID, episodeNumber: entry.episodeNumber,
                                       position: entry.position, duration: entry.duration, updatedAt: entry.updatedAt)
        }
        if changed { entries = updated; persist() }
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: key)
        let progressPrefixes = ["AnPinime.AIDrama.positions.", "AnPinime.AIDrama.selected.", "AnPinime.AIDrama.paused."]
        for savedKey in defaults.dictionaryRepresentation().keys where progressPrefixes.contains(where: { savedKey.hasPrefix($0) }) {
            defaults.removeObject(forKey: savedKey)
        }
    }

    func remove(seriesID: String) {
        entries.removeAll { $0.id == seriesID }
        persist()
    }

    #if DEBUG
    func removeFixtureHistory() { remove(seriesID: "7000000000000000001") }
    #endif

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }
}
