import Foundation

/// The reference app's own REST catalog. IDs and original media links are kept;
/// a VIP/Remux entry must never point to a lower-quality Free1 substitute.
enum Phim4KCatalog {
    typealias Object = MovieCatalog.Object
    static let prefix = "rest-api/v130/"

    static func items(_ rows: [Object], base: URL, type: String? = nil) -> [Anime] {
        var seen = Set<String>()
        return rows.compactMap { row in
            let id = MovieCatalog.text(row["videos_id"])
            let title = MovieCatalog.text(row["title"])
            let kind = type ?? (MovieCatalog.text(row["is_tvseries"]) == "1" ? "tvseries" : "movie")
            guard !id.isEmpty, !title.isEmpty, seen.insert(kind + ":" + id).inserted else { return nil }
            let detail = MovieCatalog.route(prefix + "single_details", base: base,
                query: [.init(name: "type", value: kind), .init(name: "id", value: id)])
            return Anime(title: title, url: detail,
                         imageURL: MovieCatalog.url(row["thumbnail_url"], base: base),
                         bannerURL: MovieCatalog.url(row["poster_url"], base: base),
                         episodeText: kind == "tvseries" ? "Phim bộ" : "Phim lẻ",
                         quality: MovieCatalog.text(row["video_quality"]), score: MovieCatalog.rating(row["imdb_rating"]),
                         summary: plain(row["description"]),
                         info: [MovieCatalog.text(row["release"]), MovieCatalog.text(row["runtime"])].filter { !$0.isEmpty }.joined(separator: " • "),
                         source: .phim4k, catalogLabel: "Phim4K · VIP/Premium")
        }
    }

    static func sections(_ json: Object, base: URL) -> [AnimeSection] {
        var result: [AnimeSection] = []
        for (key, title, type, path) in [("latest_movies", "Phim lẻ mới nhất", "movie", "core/movies"),
                                        ("latest_tvseries", "Phim Bộ mới nhất", "tvseries", "core/tvseries")] {
            let rows = items(json[key] as? [Object] ?? [], base: base, type: type)
            if !rows.isEmpty { result.append(AnimeSection(title: title, items: rows, categoryPath: path)) }
        }
        for group in json["features_genre_and_movie"] as? [Object] ?? [] {
            let rows = items(group["videos"] as? [Object] ?? [], base: base)
            let id = MovieCatalog.text(group["genre_id"])
            if !rows.isEmpty {
                result.append(AnimeSection(title: "Phim4K · " + MovieCatalog.text(group["name"]), items: rows,
                                           categoryPath: "core/genre/" + id))
            }
        }
        return result
    }


    static func homeRows(_ json: Object) -> [(title: String, path: String)] {
        let definitions = [("Drama xứ Hàn", "all_country", "country_id", "country", ["han quoc", "south korea", "korea"]),
                           ("Drama tàu", "all_country", "country_id", "country", ["trung quoc", "china"]),
                           ("Phim Việt", "all_country", "country_id", "country", ["viet nam", "vietnam"]),
                           ("Hoạt hình", "all_genre", "genre_id", "genre", ["hoat hinh", "animation"])]
        return definitions.compactMap { title, collection, idKey, kind, names in
            guard let row = (json[collection] as? [Object] ?? []).first(where: {
                let name = MovieCatalog.text($0["name"]).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
                return names.contains(name)
            }), !MovieCatalog.text(row[idKey]).isEmpty else { return nil }
            return (title, "core/" + kind + "/" + MovieCatalog.text(row[idKey]))
        }
    }

    static func categories(_ json: Object) -> [AnimeCategory] {
        var result = [AnimeCategory(title: "Phim lẻ", path: "core/movies", group: "Phim4K · VIP/Premium"),
                      AnimeCategory(title: "Phim bộ", path: "core/tvseries", group: "Phim4K · VIP/Premium")]
        for (key, idKey, path, group) in [("all_genre", "genre_id", "genre", "VIP/Premium · Thể loại"),
                                          ("all_country", "country_id", "country", "VIP/Premium · Quốc gia")] {
            for row in json[key] as? [Object] ?? [] {
                let id = MovieCatalog.text(row[idKey]), title = MovieCatalog.text(row["name"])
                guard !id.isEmpty, !title.isEmpty else { continue }
                result.append(AnimeCategory(title: title, path: "core/" + path + "/" + id, group: group))
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    static func listRoute(_ path: String, base: URL, page: Int) throws -> URL {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "core", parts.count >= 2 else { throw MovieSourceError.invalidData }
        var query = [URLQueryItem(name: "page", value: String(page))]
        let endpoint: String
        switch parts[1] {
        case "movies", "tvseries":
            guard parts.count == 2 else { throw MovieSourceError.invalidData }
            endpoint = parts[1]
        case "genre", "country":
            guard parts.count == 3, Int(parts[2]) != nil else { throw MovieSourceError.invalidData }
            endpoint = "content_by_" + parts[1] + "_id"
            query.append(.init(name: "id", value: parts[2]))
        default: throw MovieSourceError.invalidData
        }
        return MovieCatalog.route(prefix + endpoint, base: base, query: query)
    }

    static func detail(_ json: Object, anime: Anime) throws -> AnimeDetail {
        guard !MovieCatalog.text(json["videos_id"]).isEmpty else { throw MovieSourceError.invalidData }
        return AnimeDetail(title: MovieCatalog.text(json["title"]),
                           posterURL: MovieCatalog.url(json["thumbnail_url"], base: anime.url) ?? anime.imageURL,
                           bannerURL: MovieCatalog.url(json["poster_url"], base: anime.url) ?? anime.bannerURL,
                           summary: plain(json["description"]), info: anime.info,
                           episodes: episodes(json, detailURL: anime.url))
    }

    static func episodes(_ detail: Object, detailURL: URL) -> [Episode] {
        var result: [Episode] = []
        for video in detail["videos"] as? [Object] ?? [] {
            let id = MovieCatalog.text(video["video_file_id"])
            let label = MovieCatalog.text(video["label"])
            guard !id.isEmpty else { continue }
            result.append(Episode(title: "Xem phim", url: detailURL, number: 1,
                                  season: "VIP/Premium · " + (label.isEmpty ? "Máy chủ " + id : label),
                                  qualityBadge: MovieCatalog.detectQualityBadge(from: label), source: .phim4k,
                                  playback: .phim4kCore(detailURL: detailURL, seasonID: nil, episodeID: id)))
        }
        for season in detail["season"] as? [Object] ?? [] {
            let id = MovieCatalog.text(season["seasons_id"])
            let name = MovieCatalog.text(season["seasons_name"])
            guard !id.isEmpty else { continue }
            for (index, row) in (season["episodes"] as? [Object] ?? []).enumerated() {
                let episodeID = MovieCatalog.text(row["episodes_id"])
                let title = MovieCatalog.text(row["episodes_name"])
                guard !episodeID.isEmpty else { continue }
                result.append(Episode(title: title.isEmpty ? "Tập \(index + 1)" : title, url: detailURL, number: index + 1,
                                      season: "VIP/Premium · " + name, qualityBadge: MovieCatalog.detectQualityBadge(from: name + " " + title),
                                      source: .phim4k, playback: .phim4kCore(detailURL: detailURL, seasonID: id, episodeID: episodeID)))
            }
        }
        return result
    }

    static func stream(_ json: Object, seasonID: String?, episodeID: String, base: URL) -> (url: URL, web: Bool)? {
        let row: Object?
        if let seasonID {
            let season = (json["season"] as? [Object] ?? []).first { MovieCatalog.text($0["seasons_id"]) == seasonID }
            row = (season?["episodes"] as? [Object] ?? []).first { MovieCatalog.text($0["episodes_id"]) == episodeID }
        } else {
            row = (json["videos"] as? [Object] ?? []).first { MovieCatalog.text($0["video_file_id"]) == episodeID }
        }
        guard let row else { return nil }
        let raw = MovieCatalog.text(row["file_url"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let url = MovieCatalog.url(raw, base: base) ?? URL(string: raw)
        guard let url else { return nil }
        return (url, MovieCatalog.text(row["file_type"]).lowercased().contains("embed"))
    }

    enum MediaKind: Equatable {
        case hls, dash, mp4, mkv, otherVideo, embed, authenticationRequired, intermediate, invalid, unknown
    }

    /// Uses response status and MIME before falling back to the URL extension.
    static func mediaKind(status: Int, contentType: String, url: URL, isWeb: Bool = false) -> MediaKind {
        if status == 401 || status == 403 { return .authenticationRequired }
        guard (200..<300).contains(status) else { return .invalid }
        if isWeb { return .embed }
        let type = contentType.lowercased().split(separator: ";").first.map(String.init) ?? ""
        if type.contains("json") || type == "text/html" { return .intermediate }
        if type.contains("mpegurl") { return .hls }
        if type.contains("dash+xml") { return .dash }
        if type.contains("matroska") { return .mkv }
        if type == "video/mp4" { return .mp4 }
        switch url.pathExtension.lowercased() {
        case "m3u8": return .hls
        case "mpd": return .dash
        case "mp4", "m4v": return .mp4
        case "mkv": return .mkv
        default: return type.hasPrefix("video/") ? .otherVideo : .unknown
        }
    }

    private static func plain(_ value: Any?) -> String {
        MovieCatalog.text(value).replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
