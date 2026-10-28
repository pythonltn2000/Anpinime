import Foundation

/// Persist only parsed native timetable data; no HTML, cookies or media URLs.
enum AnimeScheduleStore {
    private static let key = "AnPinime.schedule.v1"
    private struct Snapshot: Codable { let updated: Date; let rows: [Row] }
    private struct Row: Codable {
        let day: Int, id: String, title: String, url: URL, image: URL?, airTime: String, pubTime: String, episode: String, status: String
    }
    static func save(_ data: [DayOfWeek: [AnimeScheduleItem]], at date: Date, defaults: UserDefaults = .standard) {
        let rows = data.values.flatMap { $0 }.map {
            Row(day: $0.dayOfWeek.rawValue, id: $0.id, title: $0.anime.title, url: $0.anime.url,
                image: $0.anime.imageURL, airTime: $0.airTime, pubTime: $0.pubTimeFormat, episode: $0.expectedEpisode, status: $0.statusText)
        }
        guard !rows.isEmpty, rows.count <= 2000, let encoded = try? JSONEncoder().encode(Snapshot(updated: date, rows: rows)) else { return }
        defaults.set(encoded, forKey: key)
    }
    static func load(defaults: UserDefaults = .standard) -> (Date, [DayOfWeek: [AnimeScheduleItem]])? {
        guard let data = defaults.data(forKey: key), data.count < 2_000_000,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              !snapshot.rows.isEmpty, snapshot.rows.count <= 2000 else { return nil }
        var result: [DayOfWeek: [AnimeScheduleItem]] = [:]
        for row in snapshot.rows {
            guard let day = DayOfWeek(rawValue: row.day), row.url.scheme == "https", row.url.host != nil,
                  row.url.path.hasPrefix("/phim/"), !row.title.isEmpty else { continue }
            let anime = Anime(title: row.title, url: row.url, imageURL: row.image, episodeText: row.episode, quality: "", score: "")
            result[day, default: []].append(AnimeScheduleItem(id: row.id, anime: anime, airTime: row.airTime,
                pubTimeFormat: row.pubTime, expectedEpisode: row.episode, statusText: row.status, dayOfWeek: day))
        }
        return result.isEmpty ? nil : (snapshot.updated, result)
    }
}
