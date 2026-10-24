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
            let epText = row["mediaType"] as? String == "tv" ? (count.isEmpty ? "Phim bộ" : "\(count) tập") : "Phim lẻ"
            let infoParts = [text(row["year"]), text(row["country"]), epText].filter { !$0.isEmpty }
            return Anime(title: title, url: route("movie/" + slug, base: base),
                         imageURL: url(row["poster"], base: base),
                         bannerURL: url(row["backdrop"], base: base) ?? url(row["poster"], base: base),
                         episodeText: epText,
                         quality: text(row["maxRes"]),
                         score: rating(row["score"]),
                         summary: text(row["overview"]),
                         info: infoParts.joined(separator: " • "),
                         source: .film4k)
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
        let maxRes = text(movie["maxRes"]).nonempty ?? anime.quality
        if rows.isEmpty {
            let sources = json["sources"] as? [Object] ?? movie["sources"] as? [Object] ?? []
            // A detail response may omit streams; /api/watch resolves them when Play is tapped.
            if json["playable"] as? Bool != false || !sources.isEmpty {
                let serverCount = max(1, sources.count)
                for serverIndex in 0..<serverCount {
                    let sourceObj = sources.indices.contains(serverIndex) ? sources[serverIndex] : [:]
                    let serverLabel = text(sourceObj["label"] ?? sourceObj["name"] ?? sourceObj["server"]).nonempty
                        ?? (serverCount > 1 ? "Server \(serverIndex + 1)" : "Phim lẻ")
                    let badge = text(sourceObj["quality"] ?? sourceObj["res"]).nonempty ?? maxRes
                    episodes.append(Episode(title: "Xem phim", url: route("watch/" + slug, base: base), number: 1,
                                            season: serverLabel, qualityBadge: badge, source: .film4k,
                                            playback: .film4k(slug: slug, season: nil, episode: nil, server: serverIndex)))
                }
            }
        } else {
            for row in rows {
                guard let season = integer(row["season"]), let number = integer(row["episode"]) else { continue }
                let sources = row["sources"] as? [Object] ?? []
                guard !sources.isEmpty else { continue }
                let key = String(format: "s%02de%02d", season, number)
                let watch = route("watch/" + slug, base: base, query: [.init(name: "e", value: key), .init(name: "from", value: "0")])
                episodes.append(Episode(title: "Tập \(number)", url: watch, number: number, season: "Phần \(season)",
                                        qualityBadge: maxRes, source: .film4k,
                                        playback: .film4k(slug: slug, season: season, episode: number, server: 0)))
            }
            episodes.sort { $0.season == $1.season ? ($0.number ?? 0) < ($1.number ?? 0) : $0.season.localizedStandardCompare($1.season) == .orderedAscending }
        }
        return AnimeDetail(title: text(movie["title"]).nonempty ?? anime.title,
                           posterURL: url(movie["poster"], base: base) ?? anime.imageURL,
                           bannerURL: url(movie["backdrop"], base: base) ?? anime.bannerURL,
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
        let rows = data["items"] as? [Object] ?? data["movies"] as? [Object] ?? json["items"] as? [Object] ?? []
        let rawImageBase = url(data["APP_DOMAIN_CDN_IMAGE"] ?? json["pathImage"], base: base) ?? base
        let imageBase = rawImageBase.absoluteString.hasSuffix("/")
            ? rawImageBase
            : (URL(string: rawImageBase.absoluteString + "/") ?? rawImageBase)
        var seen = Set<String>()
        return rows.compactMap { row in
            let slug = text(row["slug"]), title = text(row["name"]).nonempty ?? text(row["title"])
            guard !slug.isEmpty, !title.isEmpty, seen.insert(slug).inserted else { return nil }
            let poster = url(row["poster_url"] ?? row["thumb_url"], base: imageBase)
            let banner = url(row["thumb_url"] ?? row["poster_url"], base: imageBase)
            let epText = text(row["episode_current"] ?? row["current_episode"])
            let qual = text(row["quality"]).nonempty ?? text(row["lang"])
            let yearText = text(row["year"])
            let langText = text(row["lang"])
            let countries = (row["country"] as? [Object] ?? []).compactMap { text($0["name"]).nonempty }
            let genres = (row["category"] as? [Object] ?? []).compactMap { text($0["name"]).nonempty }
            let originName = text(row["origin_name"] ?? row["original_name"])
            let rawDesc = text(row["description"] ?? row["content"])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summaryText = rawDesc.nonempty ?? (originName.isEmpty ? "" : "\(originName) • \((genres + countries).prefix(3).joined(separator: ", "))")
            let infoParts = ([yearText, langText] + countries.prefix(1) + genres.prefix(2)).filter { !$0.isEmpty }
            return Anime(title: title,
                         url: route(format.detailPath + slug, base: base),
                         imageURL: poster,
                         bannerURL: banner,
                         episodeText: epText,
                         quality: qual,
                         score: rating((row["tmdb"] as? Object)?["vote_average"]),
                         summary: summaryText,
                         info: infoParts.joined(separator: " • "),
                         source: .phim4k)
        }
    }

    static func legacyDetail(_ json: Object, anime: Anime, serverPrefix: String = "") throws -> AnimeDetail {
        guard let movie = json["movie"] as? Object else { throw MovieSourceError.invalidData }
        let servers = json["episodes"] as? [Object] ?? movie["episodes"] as? [Object] ?? []
        let movieQuality = text(movie["quality"]).nonempty ?? anime.quality
        let movieLang = text(movie["lang"])
        var episodes: [Episode] = []
        for (serverIndex, server) in servers.enumerated() {
            let rows = server["server_data"] as? [Object] ?? server["items"] as? [Object] ?? []
            let rawGroup = text(server["server_name"]).nonempty ?? "Máy chủ \(serverIndex + 1)"
            let group = serverPrefix.isEmpty ? rawGroup : "\(serverPrefix) · \(rawGroup)"
            let badge = detectQualityBadge(from: rawGroup + " " + movieQuality + " " + movieLang)
            for (index, row) in rows.enumerated() {
                guard legacyStream(row, base: anime.url) != nil else { continue }
                let title = text(row["name"]).nonempty ?? "Tập \(index + 1)"
                episodes.append(Episode(title: title, url: anime.url, number: index + 1, season: group,
                                        qualityBadge: badge, source: .phim4k,
                                        playback: .phim4k(detailURL: anime.url, server: serverIndex, index: index)))
            }
        }
        let rawSummary = text(movie["content"] ?? movie["description"])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let countries = (movie["country"] as? [Object] ?? []).compactMap { text($0["name"]).nonempty }.joined(separator: ", ")
        let categories = (movie["category"] as? [Object] ?? []).compactMap { text($0["name"]).nonempty }.prefix(3).joined(separator: ", ")
        let infoList = [text(movie["year"]), text(movie["quality"]), text(movie["lang"]), countries, categories]
            .filter { !$0.isEmpty }
        return AnimeDetail(title: text(movie["name"]).nonempty ?? anime.title,
                           posterURL: url(movie["poster_url"], base: anime.url) ?? anime.imageURL,
                           bannerURL: url(movie["thumb_url"], base: anime.url) ?? anime.bannerURL,
                           summary: rawSummary.nonempty ?? anime.summary.nonempty ?? "Chưa có nội dung giới thiệu.",
                           info: infoList.joined(separator: " • "),
                           episodes: episodes)
    }

    static func directEpisodes(from json: Object, detailURL: URL, serverPrefix: String) -> [Episode] {
        let movie = json["movie"] as? Object ?? [:]
        let servers = json["episodes"] as? [Object] ?? movie["episodes"] as? [Object] ?? []
        let movieQuality = text(movie["quality"])
        var result: [Episode] = []
        for (serverIndex, server) in servers.enumerated() {
            let rows = server["server_data"] as? [Object] ?? server["items"] as? [Object] ?? []
            let rawGroup = text(server["server_name"]).nonempty ?? "Máy chủ \(serverIndex + 1)"
            let group = serverPrefix.isEmpty ? rawGroup : "\(serverPrefix) · \(rawGroup)"
            let badge = detectQualityBadge(from: rawGroup + " " + movieQuality)
            for (index, row) in rows.enumerated() {
                guard let stream = legacyStream(row, base: detailURL) else { continue }
                let web = url(row["link_embed"] ?? row["embed"], base: detailURL)
                let title = text(row["name"]).nonempty ?? "Tập \(index + 1)"
                result.append(Episode(title: title, url: detailURL, number: index + 1, season: group,
                                      qualityBadge: badge, source: .phim4k,
                                      playback: .directStream(url: stream.url, webURL: web, isWeb: stream.web, referer: detailURL)))
            }
        }
        return result
    }

    static func corePhim4KEpisodes(from detail: Object, detailURL: URL, fallbackEpisodes: [Episode]) -> [Episode] {
        var result: [Episode] = []
        // Single movie `videos` array from api.phim4k.online/rest-api/v130/single_details
        let videos = detail["videos"] as? [Object] ?? []
        for (idx, video) in videos.enumerated() {
            let label = text(video["label"]).nonempty ?? "Server 4K #\(idx + 1)"
            let badge = detectQualityBadge(from: label)
            let rawURL = url(video["file_url"], base: detailURL)
            let isInternalCDN = rawURL?.host?.contains("phim4k.lol") == true || rawURL?.pathExtension.lowercased() == "mkv"
            if let rawURL, !isInternalCDN {
                let isWeb = text(video["file_type"]).lowercased().contains("embed")
                result.append(Episode(title: "Xem phim", url: detailURL, number: 1, season: "Phim4K · \(label)",
                                      qualityBadge: badge, source: .phim4k,
                                      playback: .directStream(url: rawURL, webURL: nil, isWeb: isWeb, referer: detailURL)))
            } else if let matched = matchFallbackEpisode(label: label, episodeIndex: 0, in: fallbackEpisodes) {
                result.append(Episode(title: "Xem phim", url: detailURL, number: 1, season: "Phim4K · \(label)",
                                      qualityBadge: badge, source: .phim4k,
                                      playback: matched.playback))
            }
        }
        // TV series `season` array from api.phim4k.online/rest-api/v130/single_details
        let seasons = detail["season"] as? [Object] ?? []
        for seasonObj in seasons {
            let seasonName = text(seasonObj["seasons_name"]).nonempty ?? "Season 1"
            let badge = detectQualityBadge(from: seasonName)
            let eps = seasonObj["episodes"] as? [Object] ?? []
            for (idx, epObj) in eps.enumerated() {
                let epTitle = text(epObj["episodes_name"]).nonempty ?? "Tập \(idx + 1)"
                let rawURL = url(epObj["file_url"], base: detailURL)
                let isInternalCDN = rawURL?.host?.contains("phim4k.lol") == true || rawURL?.pathExtension.lowercased() == "mkv"
                if let rawURL, !isInternalCDN {
                    result.append(Episode(title: epTitle, url: detailURL, number: idx + 1, season: "Phim4K · \(seasonName)",
                                          qualityBadge: badge, source: .phim4k,
                                          playback: .directStream(url: rawURL, webURL: nil, isWeb: false, referer: detailURL)))
                } else if let matched = matchFallbackEpisode(label: seasonName, episodeIndex: idx, in: fallbackEpisodes) {
                    result.append(Episode(title: epTitle, url: detailURL, number: idx + 1, season: "Phim4K · \(seasonName)",
                                          qualityBadge: badge, source: .phim4k,
                                          playback: matched.playback))
                }
            }
        }
        return result
    }

    private static func matchFallbackEpisode(label: String, episodeIndex: Int, in fallback: [Episode]) -> Episode? {
        guard !fallback.isEmpty else { return nil }
        let normalized = label.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN")).lowercased()
        let wantsDub = normalized.contains("thuyet minh") || normalized.contains("long tieng")
        let candidates = fallback.filter { ep in
            let s = ep.season.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN")).lowercased()
            let isDub = s.contains("thuyet minh") || s.contains("long tieng")
            return wantsDub ? isDub : !isDub
        }
        let pool = candidates.isEmpty ? fallback : candidates
        if let exact = pool.first(where: { ($0.number ?? 1) == episodeIndex + 1 }) {
            return exact
        }
        return pool.indices.contains(episodeIndex) ? pool[episodeIndex] : pool.first
    }

    static func detectQualityBadge(from text: String) -> String {
        let upper = text.uppercased()
        var parts: [String] = []
        if upper.contains("2160P") || upper.contains("4K") { parts.append("4K UHD") }
        else if upper.contains("REMUX") { parts.append("Blu-ray Remux") }
        else if upper.contains("1080P") || upper.contains("FHD") || upper.contains("FULL HD") { parts.append("1080p FHD") }
        else if upper.contains("720P") || upper.contains("HD") { parts.append("HD") }
        if upper.contains("HDR") || upper.contains("DV") || upper.contains("DOLBY") { parts.append("HDR") }
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN")).lowercased()
        if folded.contains("thuyet minh") { parts.append("Thuyết minh") }
        else if folded.contains("long tieng") { parts.append("Lồng tiếng") }
        else if folded.contains("vietsub") { parts.append("Vietsub") }
        return parts.isEmpty ? "FHD" : parts.joined(separator: " · ")
    }

    static func legacyStream(_ row: Object, base: URL) -> (url: URL, web: Bool)? {
        for field in ["link_m3u8", "m3u8", "stream_url", "video_url", "file_url", "link", "link_embed", "embed"] {
            if let url = url(row[field], base: base) {
                let ext = url.pathExtension.lowercased()
                let isDirectMedia = ["m3u8", "mp4", "m4v", "mov", "ts", "mkv"].contains(ext)
                    || url.path.contains("/stream/hls")
                    || field.contains("m3u8")
                    || field == "stream_url"
                    || field == "video_url"
                let isEmbed = field.contains("embed") && !isDirectMedia
                return (url, isEmbed)
            }
        }
        return nil
    }

    static func integer(_ value: Any?) -> Int? { Int(text(value)) }
}

enum Phim4KFormat: String, CaseIterable, Identifiable {
    case free1, free2
    var id: String { rawValue }
    var title: String { self == .free1 ? "Kiểu API A (Phim4K/KKPhim)" : "Kiểu API B (NguonC)" }
    var defaultURL: URL { URL(string: self == .free1 ? "https://free.cryboiz.workers.dev" : "https://phim.nguonc.com")! }
    var listPath: String { self == .free1 ? "danh-sach/phim-moi-cap-nhat-v3" : "api/films/phim-moi-cap-nhat" }
    var detailPath: String { self == .free1 ? "phim/" : "api/film/" }
    var searchPath: String { self == .free1 ? "v1/api/tim-kiem" : "api/films/search" }

    var homeSectionsConfig: [(title: String, path: String)] {
        if self == .free1 {
            return [
                ("Mới cập nhật", "danh-sach/phim-moi-cap-nhat-v3"),
                ("Drama xứ Kim Chi", "v1/api/quoc-gia/han-quoc"),
                ("Thiên đường Drama Tàu", "v1/api/quoc-gia/trung-quoc"),
                ("Phim Việt", "v1/api/quoc-gia/viet-nam"),
                ("Phim hoạt hình", "v1/api/danh-sach/hoat-hinh"),
                ("Phim lẻ", "v1/api/danh-sach/phim-le"),
                ("Phim bộ mới nhất", "v1/api/danh-sach/phim-bo")
            ]
        } else {
            return [
                ("Mới cập nhật", "api/films/phim-moi-cap-nhat"),
                ("Drama xứ Kim Chi", "api/films/quoc-gia/han-quoc"),
                ("Thiên đường Drama Tàu", "api/films/quoc-gia/trung-quoc"),
                ("Phim Việt", "api/films/quoc-gia/viet-nam"),
                ("Phim hoạt hình", "api/films/the-loai/hoat-hinh"),
                ("Phim lẻ", "api/films/danh-sach/phim-le"),
                ("Phim bộ mới nhất", "api/films/danh-sach/phim-bo")
            ]
        }
    }

    var defaultCategories: [AnimeCategory] {
        let prefixGenre = self == .free1 ? "v1/api/the-loai/" : "api/films/the-loai/"
        let prefixCountry = self == .free1 ? "v1/api/quoc-gia/" : "api/films/quoc-gia/"
        let prefixList = self == .free1 ? "v1/api/danh-sach/" : "api/films/danh-sach/"
        var list: [AnimeCategory] = [
            .init(title: "Phim mới cập nhật", path: listPath),
            .init(title: "Drama xứ Kim Chi (Hàn Quốc)", path: prefixCountry + "han-quoc"),
            .init(title: "Thiên đường Drama Tàu (Trung Quốc)", path: prefixCountry + "trung-quoc"),
            .init(title: "Phim Việt Nam", path: prefixCountry + "viet-nam"),
            .init(title: "Phim hoạt hình", path: self == .free1 ? prefixList + "hoat-hinh" : prefixGenre + "hoat-hinh"),
            .init(title: "Phim lẻ", path: prefixList + "phim-le"),
            .init(title: "Phim bộ mới nhất", path: prefixList + "phim-bo"),
            .init(title: "TV Shows", path: self == .free1 ? prefixList + "tv-shows" : prefixGenre + "tv-shows"),
            .init(title: "Phim Âu Mỹ", path: prefixCountry + "au-my"),
            .init(title: "Phim Nhật Bản", path: prefixCountry + "nhat-ban"),
            .init(title: "Phim Thái Lan", path: prefixCountry + "thai-lan")
        ]
        let genres: [(String, String)] = [
            ("Hành Động", "hanh-dong"),
            ("Tình Cảm", "tinh-cam"),
            ("Hài Hước", "hai-huoc"),
            ("Cổ Trang", "co-trang"),
            ("Tâm Lý", "tam-ly"),
            ("Hình Sự", "hinh-su"),
            ("Chiến Tranh", "chien-tranh"),
            ("Thể Thao", "the-thao"),
            ("Võ Thuật", "vo-thuat"),
            ("Viễn Tưởng", "vien-tuong"),
            ("Phiêu Lưu", "phieu-luu"),
            ("Khoa Học", "khoa-hoc"),
            ("Kinh Dị", "kinh-di"),
            ("Âm Nhạc", "am-nhac"),
            ("Thần Thoại", "than-thoai"),
            ("Tài Liệu", "tai-lieu"),
            ("Gia Đình", "gia-dinh"),
            ("Chính Kịch", "chinh-kich"),
            ("Bí Ẩn", "bi-an"),
            ("Học Đường", "hoc-duong"),
            ("Kinh Điển", "kinh-dien")
        ]
        for (name, slug) in genres {
            list.append(.init(title: "Thể loại: \(name)", path: prefixGenre + slug))
        }
        return list
    }
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
