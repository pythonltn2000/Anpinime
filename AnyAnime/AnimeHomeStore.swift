import Foundation

/// Parsed Home cards only. Keep website HTML, cookies and playback URLs out of the disk cache.
/// The actor also keeps disk reads/encoding off the main actor that draws Home.
actor AnimeHomeStore {
    static let shared = AnimeHomeStore()
    private let fileURL: URL
    private let maximumAge: TimeInterval = 24 * 3600

    struct Snapshot {
        let date: Date
        let baseURL: URL
        let sections: [AnimeSection]
    }
    private struct StoredSnapshot: Codable {
        let date: Date
        let configuration: String
        let baseURL: URL
        let sections: [StoredSection]
    }
    private struct StoredSection: Codable {
        let title: String
        let items: [StoredAnime]
        let categoryPath: String?
    }
    private struct StoredAnime: Codable {
        let title: String, subtitle: String, url: URL, imageURL: URL?, bannerURL: URL?
        let episodeText: String, quality: String, score: String
    }

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = root.appendingPathComponent("AnPinime/AnimeHome-v1.json")
    }

    func load(configuration: URL?, now: Date = Date()) -> Snapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue < 2_000_000,
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
              stored.configuration == configurationKey(configuration),
              now.timeIntervalSince(stored.date) >= -60, now.timeIntervalSince(stored.date) < maximumAge,
              allowsBase(stored.baseURL, configuration: configuration),
              !stored.sections.isEmpty, stored.sections.count <= 30,
              stored.sections.reduce(0, { $0 + $1.items.count }) <= 1000 else { return nil }
        var sections: [AnimeSection] = []
        for section in stored.sections {
            guard !section.title.isEmpty, !section.items.isEmpty else { return nil }
            var items: [Anime] = []
            for row in section.items {
                guard !row.title.isEmpty, row.title.count <= 1000,
                      row.url.scheme == "https", row.url.host == stored.baseURL.host,
                      row.url.path.contains("phim") else { return nil }
                items.append(Anime(title: row.title, subtitle: row.subtitle, url: row.url,
                                   imageURL: row.imageURL, bannerURL: row.bannerURL,
                                   episodeText: row.episodeText, quality: row.quality, score: row.score))
            }
            sections.append(AnimeSection(title: section.title, items: items, categoryPath: section.categoryPath))
        }
        return Snapshot(date: stored.date, baseURL: stored.baseURL, sections: sections)
    }

    func save(sections: [AnimeSection], baseURL: URL, configuration: URL?, at date: Date = Date()) {
        guard allowsBase(baseURL, configuration: configuration), !sections.isEmpty, sections.count <= 30,
              sections.reduce(0, { $0 + $1.items.count }) <= 1000,
              sections.allSatisfy({ !$0.title.isEmpty && !$0.items.isEmpty && $0.items.allSatisfy {
                  $0.source == .anime && !$0.title.isEmpty && $0.title.count <= 1000 &&
                  $0.url.scheme == "https" && $0.url.host == baseURL.host && $0.url.path.contains("phim")
              } }) else { return }
        let stored = StoredSnapshot(date: date, configuration: configurationKey(configuration), baseURL: baseURL,
            sections: sections.map { section in
                StoredSection(title: section.title, items: section.items.map {
                    StoredAnime(title: $0.title, subtitle: $0.subtitle, url: $0.url, imageURL: $0.imageURL,
                                bannerURL: $0.bannerURL, episodeText: $0.episodeText, quality: $0.quality, score: $0.score)
                }, categoryPath: section.categoryPath)
            })
        guard let data = try? JSONEncoder().encode(stored), data.count < 2_000_000 else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { /* A cache write failure must never prevent playback or Home from loading. */ }
    }

    func invalidate() { try? FileManager.default.removeItem(at: fileURL) }

    private func configurationKey(_ configuration: URL?) -> String { configuration?.absoluteString ?? "automatic" }
    private func allowsBase(_ url: URL, configuration: URL?) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return false }
        if let configuration { return url.host == configuration.host && url.port == configuration.port }
        return AnimeSiteConfiguration.isAutomaticHost(url.host)
    }
}
