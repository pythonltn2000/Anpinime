import Foundation

/// Provider schemas stay separate from the AnimeVietsub HTML parser.
enum MovieCatalog {
    typealias Object = [String: Any]

    static func object(_ data: Data) throws -> Object {
        guard let json = try JSONSerialization.jsonObject(with: data) as? Object else {
            throw MovieSourceError.invalidData
        }
        return json
    }

    static func text(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        if let value = value as? Object {
            return text(value["vi"]).nonempty ?? text(value["en"])
        }
        return ""
    }

    static func url(_ value: Any?, base: URL) -> URL? {
        let raw = text(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func route(_ path: String, base: URL, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    static func rating(_ value: Any?) -> String {
        guard let number = Double(text(value)), number.isFinite, number > 0 else { return "" }
        return String(format: "%.1f", number)
    }

    static func filmItems(_ rows: [Object], base: URL) -> [Anime] {
        var seen = Set<String>()
        return rows.compactMap { row in
            let slug = text(row["slug"]), title = text(row["title"])
            guard !slug.isEmpty, !title.isEmpty, seen.insert(slug).inserted else { return nil }
            let count = text(row["epCount"])
            return Anime(title: title, url: route("movie/" + slug, base: base),
                         imageURL: url(row["poster"], base: base),
                         episodeText: row["mediaType"] as? String == "tv" ? (count.isEmpty ? "Phim bộ" : "\(count) tập") : "Phim lẻ",
                         quality: text(row["maxRes"]), score: rating(row["score"]), source: .film4k)
        }
    }

    static func filmSections(_ json: Object, base: URL) -> [AnimeSection] {
        [("Mới cập nhật", "list"), ("Phim nổi bật", "top"), ("Phim lẻ mới", "newMovies"), ("Phim bộ mới", "newSeries")]
            .compactMap { title, key in
                let items = filmItems(json[key] as? [Object] ?? [], base: base)
                return items.isEmpty ? nil : AnimeSection(title: title, items: items)
            }
    }

    static func filmDetail(_ json: Object, anime: Anime, base: URL) throws -> AnimeDetail {
        guard let movie = json["movie"] as? Object else { throw MovieSourceError.invalidData }
        let slug = text(movie["slug"]).nonempty ?? anime.url.lastPathComponent
        let rows = json["episodes"] as? [Object] ?? []
        var episodes: [Episode] = []
        if rows.isEmpty {
            let sources = json["sources"] as? [Object] ?? movie["sources"] as? [Object] ?? []
            // A detail response may omit streams; /api/watch resolves them when Play is tapped.
            if json["playable"] as? Bool != false || !sources.isEmpty {
                episodes = [Episode(title: "Xem phim", url: route("watch/" + slug, base: base), number: 1,
                                    season: "Phim lẻ", source: .film4k,
                                    playback: .film4k(slug: slug, season: nil, episode: nil, server: 0))]
            }
        } else {
            for row in rows {
                guard let season = integer(row["season"]), let number = integer(row["episode"]) else { continue }
                let sources = row["sources"] as? [Object] ?? []
                guard !sources.isEmpty else { continue }
                let key = String(format: "s%02de%02d", season, number)
                let watch = route("watch/" + slug, base: base, query: [.init(name: "e", value: key), .init(name: "from", value: "0")])
                episodes.append(Episode(title: "Tập \(number)", url: watch, number: number, season: "Phần \(season)",
                                        source: .film4k, playback: .film4k(slug: slug, season: season, episode: number, server: 0)))
            }
            episodes.sort { $0.season == $1.season ? ($0.number ?? 0) < ($1.number ?? 0) : $0.season.localizedStandardCompare($1.season) == .orderedAscending }
        }
        return AnimeDetail(title: text(movie["title"]).nonempty ?? anime.title,
                           posterURL: url(movie["poster"], base: base) ?? anime.imageURL,
                           bannerURL: url(movie["backdrop"], base: base),
                           summary: text(movie["overview"]).nonempty ?? "Chưa có nội dung giới thiệu.",
                           info: [text(movie["year"]), text(movie["country"]), text(movie["mediaType"]) == "tv" ? "Phim bộ" : "Phim lẻ"].filter { !$0.isEmpty }.joined(separator: " • "),
                           episodes: episodes)
    }

    static func filmStreams(_ json: Object, season: Int?, episode: Int?) -> [Object] {
        if let season, let episode {
            return (json["episodes"] as? [Object] ?? []).first {
                integer($0["season"]) == season && integer($0["episode"]) == episode
            }?["sources"] as? [Object] ?? []
        }
        return json["sources"] as? [Object] ?? []
    }

    // The IPA's Free1 and Free2 use two different public JSON formats.
    static func legacyItems(_ json: Object, base: URL, format: Phim4KFormat) -> [Anime] {
        let data = json["data"] as? Object ?? json
        let rows = data["items"] as? [Object] ?? data["movies"] as? [Object] ?? []
        let imageBase = url(data["APP_DOMAIN_CDN_IMAGE"] ?? json["pathImage"], base: base) ?? base
        var seen = Set<String>()
        return rows.compactMap { row in
            let slug = text(row["slug"]), title = text(row["name"]).nonempty ?? text(row["title"])
            guard !slug.isEmpty, !title.isEmpty, seen.insert(slug).inserted else { return nil }
            return Anime(title: title, url: route(format.detailPath + slug, base: base),
                         imageURL: url(row["poster_url"] ?? row["thumb_url"], base: imageBase),
                         episodeText: text(row["episode_current"] ?? row["current_episode"]),
                         quality: text(row["quality"]), score: rating((row["tmdb"] as? Object)?["vote_average"]), source: .phim4k)
        }
    }

    static func legacyDetail(_ json: Object, anime: Anime) throws -> AnimeDetail {
        guard let movie = json["movie"] as? Object else { throw MovieSourceError.invalidData }
        let servers = json["episodes"] as? [Object] ?? movie["episodes"] as? [Object] ?? []
        var episodes: [Episode] = []
        for (serverIndex, server) in servers.enumerated() {
            let rows = server["server_data"] as? [Object] ?? server["items"] as? [Object] ?? []
            let group = text(server["server_name"]).nonempty ?? "Máy chủ \(serverIndex + 1)"
            for (index, row) in rows.enumerated() {
                guard legacyStream(row, base: anime.url) != nil else { continue }
                let title = text(row["name"]).nonempty ?? "Tập \(index + 1)"
                episodes.append(Episode(title: title, url: anime.url, number: index + 1, season: group,
                                        source: .phim4k, playback: .phim4k(detailURL: anime.url, server: serverIndex, index: index)))
            }
        }
        let summary = text(movie["content"] ?? movie["description"]).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return AnimeDetail(title: text(movie["name"]).nonempty ?? anime.title,
                           posterURL: url(movie["poster_url"], base: anime.url) ?? anime.imageURL,
                           bannerURL: url(movie["thumb_url"], base: anime.url), summary: summary,
                           info: [text(movie["year"]), text(movie["quality"]), text(movie["lang"])].filter { !$0.isEmpty }.joined(separator: " • "), episodes: episodes)
    }

    static func legacyStream(_ row: Object, base: URL) -> (url: URL, web: Bool)? {
        for field in ["link_m3u8", "m3u8", "stream_url", "video_url", "link", "link_embed", "embed"] {
            if let url = url(row[field], base: base) { return (url, field.contains("embed")) }
        }
        return nil
    }

    static func integer(_ value: Any?) -> Int? { Int(text(value)) }
}

enum Phim4KFormat: String, CaseIterable, Identifiable {
    case free1, free2
    var id: String { rawValue }
    var title: String { self == .free1 ? "Kiểu API A" : "Kiểu API B" }
    var defaultURL: URL { URL(string: self == .free1 ? "https://free.cryboiz.workers.dev" : "https://free2.p4k.dpdns.org")! }
    var listPath: String { self == .free1 ? "danh-sach/phim-moi-cap-nhat-v3" : "api/films/phim-moi-cap-nhat" }
    var detailPath: String { self == .free1 ? "phim/" : "api/film/" }
    var searchPath: String { self == .free1 ? "v1/api/tim-kiem" : "api/films/search" }
}

enum MovieSourceError: LocalizedError {
    case invalidData, noVideo, unavailable(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Nguồn phim trả dữ liệu chưa được hỗ trợ. Hãy làm mới hoặc chọn nguồn khác."
        case .noVideo: return "Nguồn này chưa cung cấp video cho tập đã chọn."
        case .unavailable(let message): return message
        case .http(let code): return "Nguồn phim trả lỗi HTTP \(code). Hãy thử lại sau."
        }
    }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
