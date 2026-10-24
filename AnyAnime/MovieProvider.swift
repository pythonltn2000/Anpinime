import Foundation

@MainActor
final class MovieProvider {
    let source: ContentSource
    private(set) var baseURL: URL
    private(set) var categories: [AnimeCategory] = []
    private var format = Phim4KFormat.free1
    private let session: URLSession
    private var ticket: String?
    private var ticketExpiry = Date.distantPast

    init(source: ContentSource) {
        self.source = source
        baseURL = source == .film4k ? URL(string: "https://film4k.net")! : Phim4KFormat.free1.defaultURL
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { baseURL = URL(string: "http://127.0.0.1:8765")! }
        #endif
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    func home() async throws -> [AnimeSection] {
        if source == .film4k {
            let json = try await request(MovieCatalog.route("api/home", base: baseURL))
            categories = [.init(title: "Phim lẻ", path: "type=movie"), .init(title: "Phim bộ", path: "type=tv")]
            categories += (json["genres"] as? [String] ?? []).map {
                var components = URLComponents()
                components.queryItems = [.init(name: "genre", value: $0)]
                return AnimeCategory(title: $0, path: components.percentEncodedQuery ?? "")
            }
            let result = MovieCatalog.filmSections(json, base: baseURL)
            guard !result.isEmpty else { throw MovieSourceError.invalidData }
            return result
        }
        let custom = UserDefaults.standard.string(forKey: "AnPinime.phim4kURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selected = Phim4KFormat(rawValue: UserDefaults.standard.string(forKey: "AnPinime.phim4kFormat") ?? "") ?? .free1
        var candidates: [(URL, Phim4KFormat)]
        if !custom.isEmpty {
            guard let url = URL(string: custom), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw MovieSourceError.unavailable("Địa chỉ Nguồn phim 2 phải là URL HTTPS, không chứa mật khẩu hoặc tham số.")
            }
            candidates = [(url, selected)]
        } else {
            #if DEBUG
            candidates = PlaybackSmokeTest.providerFixture ? [] : await MovieSourceDirectory.candidates(session: session)
            #else
            candidates = await MovieSourceDirectory.candidates(session: session)
            #endif
        }
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { candidates = [(URL(string: "http://127.0.0.1:8765")!, .free1)] }
        #endif
        for (url, candidateFormat) in candidates {
            do {
                let firstSectionPath = candidateFormat.homeSectionsConfig.first?.path ?? candidateFormat.listPath
                let json = try await request(MovieCatalog.route(firstSectionPath, base: url, query: [.init(name: "page", value: "1")]))
                let latestItems = MovieCatalog.legacyItems(json, base: url, format: candidateFormat)
                guard !latestItems.isEmpty else { throw MovieSourceError.invalidData }
                try Task.checkCancellation()
                baseURL = url
                format = candidateFormat
                categories = candidateFormat.defaultCategories

                let sectionConfigs = url.host == "127.0.0.1" ? [] : Array(candidateFormat.homeSectionsConfig.dropFirst())
                var fetchedSections: [Int: AnimeSection] = [
                    0: AnimeSection(title: "Mới cập nhật", items: latestItems, categoryPath: firstSectionPath)
                ]

                await withTaskGroup(of: (Int, AnimeSection?).self) { group in
                    for ( idx, config ) in sectionConfigs.enumerated() {
                        let order = idx + 1
                        group.addTask { [weak self] in
                            guard let self else { return (order, nil) }
                            do {
                                let routeURL = MovieCatalog.route(config.path, base: url, query: [.init(name: "page", value: "1")])
                                let secJSON = try await self.request(routeURL)
                                let secItems = await MainActor.run {
                                    MovieCatalog.legacyItems(secJSON, base: url, format: candidateFormat)
                                }
                                guard !secItems.isEmpty else { return (order, nil) }
                                return (order, AnimeSection(title: config.title, items: secItems, categoryPath: config.path))
                            } catch {
                                return (order, nil)
                            }
                        }
                    }
                    for await (order, section) in group {
                        if let section {
                            fetchedSections[order] = section
                        }
                    }
                }

                let ordered = fetchedSections.keys.sorted().compactMap { fetchedSections[$0] }
                return ordered.isEmpty ? [AnimeSection(title: "Mới cập nhật", items: latestItems, categoryPath: firstSectionPath)] : ordered
            } catch {
                if Task.isCancelled { throw CancellationError() }
            }
        }
        throw MovieSourceError.unavailable(custom.isEmpty
            ? "Nguồn phim 2 hiện chưa kết nối được máy chủ. Bạn có thể chọn Nguồn phim 1 hoặc cập nhật kết nối trong Cài đặt."
            : "Không đọc được dữ liệu Nguồn phim 2 tại địa chỉ đã lưu. Kiểm tra địa chỉ và kiểu API trong Cài đặt.")
    }

    func list(path: String, page: Int = 1) async throws -> [Anime] {
        if source == .film4k {
            let filters = URLComponents(string: "?" + path)?.queryItems ?? []
            let json = try await request(MovieCatalog.route("api/home", base: baseURL,
                                                         query: filters + [.init(name: "page", value: String(page))]))
            return MovieCatalog.filmItems(json["list"] as? [MovieCatalog.Object] ?? [], base: baseURL)
        }
        let cleanPath = (path.isEmpty || path == "latest") ? format.listPath : path
        let json = try await request(MovieCatalog.route(cleanPath, base: baseURL, query: [.init(name: "page", value: String(page))]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format)
    }

    func search(_ query: String) async throws -> [Anime] {
        let path = source == .film4k ? "api/search/suggest" : format.searchPath
        let key = source == .film4k ? "q" : "keyword"
        let json = try await request(MovieCatalog.route(path, base: baseURL, query: [.init(name: key, value: query)]))
        if source == .film4k {
            return MovieCatalog.filmItems(json["list"] as? [MovieCatalog.Object] ?? [], base: baseURL)
        }
        var results = MovieCatalog.legacyItems(json, base: baseURL, format: format)
        if results.isEmpty, baseURL.host != "phim.nguonc.com", let backupURL = URL(string: "https://phim.nguonc.com") {
            if let backupJSON = try? await request(MovieCatalog.route(Phim4KFormat.free2.searchPath, base: backupURL, query: [.init(name: "keyword", value: query)])) {
                results = MovieCatalog.legacyItems(backupJSON, base: backupURL, format: .free2)
            }
        }
        return results
    }

    func detail(_ anime: Anime) async throws -> AnimeDetail {
        if source == .film4k {
            let json = try await request(MovieCatalog.route("api/title/" + anime.url.lastPathComponent, base: baseURL))
            return try MovieCatalog.filmDetail(json, anime: anime, base: baseURL)
        }
        let slug = anime.url.lastPathComponent
        let primaryHost = anime.url.host?.lowercased() ?? ""
        let prefix = primaryHost.contains("cryboiz") ? "Phim4K" : (primaryHost.contains("phimapi") ? "VIP Nhanh" : (primaryHost.contains("nguonc") ? "NguonC" : "Server 1"))
        let primaryJSON = try await request(anime.url)
        let baseDetail = try MovieCatalog.legacyDetail(primaryJSON, anime: anime, serverPrefix: prefix)
        if primaryHost == "127.0.0.1" || primaryHost == "localhost" {
            return baseDetail
        }

        var allEpisodes = baseDetail.episodes
        var summary = baseDetail.summary
        var banner = baseDetail.bannerURL
        var info = baseDetail.info

        // Concurrently aggregate additional servers from VIP CDN (phimapi.com), NguonC (phim.nguonc.com), and Phim4K Core (api.phim4k.online)
        await withTaskGroup(of: (Int, [Episode], String?, URL?, String?).self) { group in
            if !primaryHost.contains("phimapi.com"), let vipURL = URL(string: "https://phimapi.com/phim/\(slug)") {
                group.addTask { [weak self] in
                    guard let self, let json = try? await self.request(vipURL) else { return (1, [], nil, nil, nil) }
                    let eps = await MainActor.run { MovieCatalog.directEpisodes(from: json, detailURL: vipURL, serverPrefix: "VIP Nhanh") }
                    return (1, eps, nil, nil, nil)
                }
            }
            if !primaryHost.contains("nguonc.com"), let nguonURL = URL(string: "https://phim.nguonc.com/api/film/\(slug)") {
                group.addTask { [weak self] in
                    guard let self, let json = try? await self.request(nguonURL) else { return (2, [], nil, nil, nil) }
                    let eps = await MainActor.run { MovieCatalog.directEpisodes(from: json, detailURL: nguonURL, serverPrefix: "NguonC") }
                    return (2, eps, nil, nil, nil)
                }
            }
            let baseFallback = allEpisodes
            let searchTitle = baseDetail.title
            group.addTask { [weak self] in
                guard let self else { return (3, [], nil, nil, nil) }
                let core = await MainActor.run { MovieSourceDirectory.coreAPI() }
                let searchRoute = MovieCatalog.route("rest-api/v130/search", base: core.baseURL,
                                                     query: [.init(name: "q", value: searchTitle), .init(name: "page", value: "1"), .init(name: "type", value: "movietvserieslive")])
                guard let searchJSON = try? await self.requestCore(searchRoute, apiKey: core.apiKey) else { return (3, [], nil, nil, nil) }
                let movies = searchJSON["movie"] as? [MovieCatalog.Object] ?? []
                let series = searchJSON["tvseries"] as? [MovieCatalog.Object] ?? []
                let candidates = movies.map { ($0, "movie") } + series.map { ($0, "tvseries") }
                guard let matched = candidates.first(where: { row, _ in
                    let rowSlug = MovieCatalog.text(row["slug"]).lowercased()
                    let rowTitle = MovieCatalog.text(row["title"]).lowercased()
                    return rowSlug == slug.lowercased() || rowTitle.contains(searchTitle.lowercased())
                }) ?? candidates.first else { return (3, [], nil, nil, nil) }
                let vid = MovieCatalog.text(matched.0["videos_id"])
                guard !vid.isEmpty else { return (3, [], nil, nil, nil) }
                let detailRoute = MovieCatalog.route("rest-api/v130/single_details", base: core.baseURL,
                                                     query: [.init(name: "type", value: matched.1), .init(name: "id", value: vid)])
                guard let coreDetail = try? await self.requestCore(detailRoute, apiKey: core.apiKey) else { return (3, [], nil, nil, nil) }
                return await MainActor.run {
                    let eps = MovieCatalog.corePhim4KEpisodes(from: coreDetail, detailURL: anime.url, fallbackEpisodes: baseFallback)
                    let desc = MovieCatalog.text(coreDetail["description"])
                        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let thumb = MovieCatalog.url(coreDetail["thumbnail_url"] ?? coreDetail["poster_url"], base: core.baseURL)
                    let runtime = MovieCatalog.text(coreDetail["runtime"])
                    return (3, eps, desc.isEmpty ? nil : desc, thumb, runtime.isEmpty ? nil : runtime)
                }
            }

            var extraByOrder: [Int: [Episode]] = [:]
            for await (order, eps, extraDesc, extraBanner, extraRuntime) in group {
                if !eps.isEmpty { extraByOrder[order] = eps }
                if (summary.isEmpty || summary == "Chưa có nội dung giới thiệu."), let extraDesc, !extraDesc.isEmpty {
                    summary = extraDesc
                }
                if banner == nil, let extraBanner {
                    banner = extraBanner
                }
                if let extraRuntime, !info.contains(extraRuntime) {
                    info = [info, extraRuntime].filter { !$0.isEmpty }.joined(separator: " • ")
                }
            }
            for order in extraByOrder.keys.sorted() {
                if let eps = extraByOrder[order] {
                    allEpisodes.append(contentsOf: eps)
                }
            }
        }

        return AnimeDetail(title: baseDetail.title,
                           posterURL: baseDetail.posterURL,
                           bannerURL: banner ?? baseDetail.posterURL,
                           summary: summary,
                           info: info,
                           episodes: allEpisodes)
    }

    func resolve(_ episode: Episode, refresh: Bool = false) async throws -> ResolvedPlayback {
        switch episode.playback {
        case .film4k(let slug, let season, let number, let server):
            async let watch = request(MovieCatalog.route("api/watch/" + slug, base: baseURL))
            try await refreshTicket(force: refresh)
            let json = try await watch
            let sources = MovieCatalog.filmStreams(json, season: season, episode: number)
            guard !sources.isEmpty else { throw MovieSourceError.noVideo }
            // Prefer a native HLS/MP4 source; opaque embeds and DASH use their original web player.
            let candidates = sources.sorted { Self.isNative($0) && !Self.isNative($1) }
            let selected = candidates[min(server, candidates.count - 1)]
            guard let url = MovieCatalog.url(selected["url"], base: baseURL) else { throw MovieSourceError.noVideo }
            var headers = ["Referer": episode.url.absoluteString, "User-Agent": AnimeService.userAgent]
            if url.host == baseURL.host, let ticket { headers["X-F4K-PT"] = ticket }
            let native = Self.isNative(selected)
            return ResolvedPlayback(url: native ? url : episode.url, headers: headers, webURL: episode.url, isWeb: !native)
        case .phim4k(let detailURL, let server, let index):
            // Resolve again at Play time so an expiring URL is never persisted in the catalog.
            let json = try await request(detailURL)
            let movie = json["movie"] as? MovieCatalog.Object ?? [:]
            let groups = json["episodes"] as? [MovieCatalog.Object] ?? movie["episodes"] as? [MovieCatalog.Object] ?? []
            guard groups.indices.contains(server) else { throw MovieSourceError.noVideo }
            let rows = groups[server]["server_data"] as? [MovieCatalog.Object] ?? groups[server]["items"] as? [MovieCatalog.Object] ?? []
            guard rows.indices.contains(index), let stream = MovieCatalog.legacyStream(rows[index], base: detailURL) else { throw MovieSourceError.noVideo }
            let web = MovieCatalog.url(rows[index]["link_embed"] ?? rows[index]["embed"], base: detailURL)
            let originHost = detailURL.scheme.flatMap { s in detailURL.host.map { "\(s)://\($0)" } } ?? baseURL.absoluteString
            return ResolvedPlayback(url: stream.url, headers: ["Referer": originHost + "/", "Origin": originHost, "User-Agent": AnimeService.userAgent],
                                    webURL: web, isWeb: stream.web)
        case .directStream(let url, let webURL, let isWeb, let referer):
            let refURL = referer ?? baseURL
            let originHost = refURL.scheme.flatMap { s in refURL.host.map { "\(s)://\($0)" } } ?? baseURL.absoluteString
            return ResolvedPlayback(url: url, headers: ["Referer": originHost + "/", "Origin": originHost, "User-Agent": AnimeService.userAgent],
                                    webURL: webURL, isWeb: isWeb)
        case .animePage:
            throw MovieSourceError.noVideo
        }
    }

    private func requestCore(_ url: URL, apiKey: String) async throws -> MovieCatalog.Object {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "API-KEY")
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MovieSourceError.invalidData
        }
        return try MovieCatalog.object(data)
    }

    private static func isNative(_ source: MovieCatalog.Object) -> Bool {
        guard source["drm"] == nil, let url = URL(string: MovieCatalog.text(source["url"])) else { return false }
        return ["m3u8", "mp4", "m4v", "mov"].contains(url.pathExtension.lowercased())
    }

    private func refreshTicket(force: Bool) async throws {
        if !force, ticketExpiry > Date().addingTimeInterval(60) { return }
        let json = try await request(MovieCatalog.route("api/play-ticket", base: baseURL), method: "POST")
        ticket = (json["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let milliseconds = json["expires"] as? Double {
            ticketExpiry = Date(timeIntervalSince1970: milliseconds / 1000)
        } else if json["ok"] as? Bool == true {
            ticketExpiry = Date().addingTimeInterval(120)
        } else { throw MovieSourceError.invalidData }
    }

    private func request(_ url: URL, method: String = "GET") async throws -> MovieCatalog.Object {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        var originComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        originComponents.path = ""; originComponents.query = nil; originComponents.fragment = nil
        let origin = originComponents.string ?? baseURL.absoluteString
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(origin + "/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MovieSourceError.invalidData }
        guard (200..<300).contains(http.statusCode) else { throw MovieSourceError.http(http.statusCode) }
        return try MovieCatalog.object(data)
    }
}
