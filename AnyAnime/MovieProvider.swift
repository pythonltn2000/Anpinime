import Foundation

@MainActor
final class MovieProvider {
    let source: ContentSource
    private(set) var baseURL: URL
    private(set) var categories: [AnimeCategory] = []
    private var format: Phim4KFormat
    private let session: URLSession
    private var ticket: String?
    private var ticketExpiry = Date.distantPast
    private var configured = false
    private var cachedJSON: [URL: (Date, MovieCatalog.Object)] = [:]

    init(source: ContentSource) {
        self.source = source
        format = source == .film4k ? .free2 : .free1
        baseURL = source == .kkphim ? URL(string: "https://phimapi.com")! : format.defaultURL
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { baseURL = URL(string: "http://127.0.0.1:8765")! }
        #endif
        categories = source == .phim4k ? [] : format.defaultCategories
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    func invalidate() {
        cachedJSON.removeAll()
        configured = false
    }

    private func configure() async throws {
        guard source == .phim4k, !configured else { return }
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { configured = true; return }
        #endif
        let custom = UserDefaults.standard.string(forKey: "AnPinime.phim4kURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selected = Phim4KFormat(rawValue: UserDefaults.standard.string(forKey: "AnPinime.phim4kFormat") ?? "") ?? .free1
        if !custom.isEmpty {
            guard let url = URL(string: custom), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw MovieSourceError.unavailable("Địa chỉ Nguồn phim 2 phải là URL HTTPS hợp lệ.")
            }
            baseURL = url
            format = selected
        } else {
            let candidates = await MovieSourceDirectory.candidates(session: session)
            var found = false
            for (url, candidateFormat) in candidates {
                try Task.checkCancellation()
                do {
                    let json = try await catalogRequest(MovieCatalog.route(candidateFormat.listPath, base: url))
                    guard !MovieCatalog.legacyItems(json, base: url, format: candidateFormat, source: source).isEmpty else { continue }
                    baseURL = url
                    format = candidateFormat
                    found = true
                    break
                } catch { try Task.checkCancellation() }
            }
            guard found else { throw MovieSourceError.unavailable("Nguồn phim 2 tạm thời không phản hồi. Hãy thử lại hoặc cập nhật địa chỉ trong Cài đặt.") }
        }
        categories = format.defaultCategories
        configured = true
    }

    func home(onInitial: ([AnimeSection]) -> Void = { _ in }) async throws -> [AnimeSection] {
        #if DEBUG
        // Keep the historical ticket/relay fixture independent of the production source.
        if source == .film4k, PlaybackSmokeTest.providerFixture {
            return MovieCatalog.filmSections(try await request(MovieCatalog.route("api/home", base: baseURL)), base: baseURL)
        }
        #endif
        try await configure()
        // Return the first useful page immediately; other categories load on demand.
        let items = try await list(path: "")
        guard !items.isEmpty else { throw MovieSourceError.invalidData }
        let initial = [AnimeSection(title: "Mới cập nhật", items: items, categoryPath: format.listPath)]
        onInitial(initial)
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { return initial }
        #endif
        let configs = Array(format.homeSectionsConfig.dropFirst())
        var extra: [Int: AnimeSection] = [:]
        await withTaskGroup(of: (Int, AnimeSection?).self) { group in
            for (index, config) in configs.enumerated() {
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled,
                          let rows = try? await self.list(path: config.path), !rows.isEmpty else { return (index, nil) }
                    return (index, AnimeSection(title: config.title, items: rows, categoryPath: config.path))
                }
            }
            for await (index, section) in group {
                if let section { extra[index] = section }
            }
        }
        try Task.checkCancellation()
        return initial + extra.keys.sorted().compactMap { extra[$0] }
    }

    func list(path: String, page: Int = 1) async throws -> [Anime] {
        try await configure()
        let target = path.isEmpty || path == "latest" ? format.listPath : path
        let json = try await catalogRequest(MovieCatalog.route(target, base: baseURL, query: [.init(name: "page", value: String(page))]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format, source: source)
    }

    func search(_ query: String) async throws -> [Anime] {
        try await configure()
        let json = try await catalogRequest(MovieCatalog.route(format.searchPath, base: baseURL, query: [.init(name: "keyword", value: query)]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format, source: source)
    }

    func detail(_ anime: Anime) async throws -> AnimeDetail {
        #if DEBUG
        if source == .film4k, PlaybackSmokeTest.providerFixture {
            return try MovieCatalog.filmDetail(try await request(MovieCatalog.route("api/title/" + anime.url.lastPathComponent, base: baseURL)), anime: anime, base: baseURL)
        }
        #endif
        let json = try await catalogRequest(anime.url)
        return try MovieCatalog.legacyDetail(json, anime: anime)
    }

    private func catalogRequest(_ url: URL) async throws -> MovieCatalog.Object {
        if let (date, json) = cachedJSON[url], Date().timeIntervalSince(date) < 120 { return json }
        let json = try await request(url)
        if cachedJSON.count >= 80 { cachedJSON.removeAll() }
        cachedJSON[url] = (Date(), json)
        return json
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
            let activeDetailURL = detailURL
            let json = try await request(detailURL)
            let movie = json["movie"] as? MovieCatalog.Object ?? [:]
            let groups = json["episodes"] as? [MovieCatalog.Object] ?? movie["episodes"] as? [MovieCatalog.Object] ?? []
            guard groups.indices.contains(server) else { throw MovieSourceError.noVideo }
            let rows = groups[server]["server_data"] as? [MovieCatalog.Object] ?? groups[server]["items"] as? [MovieCatalog.Object] ?? []
            guard rows.indices.contains(index), let stream = MovieCatalog.legacyStream(rows[index], base: activeDetailURL) else { throw MovieSourceError.noVideo }
            let web = MovieCatalog.url(rows[index]["link_embed"] ?? rows[index]["embed"], base: activeDetailURL)
            let originHost = activeDetailURL.scheme.flatMap { s in activeDetailURL.host.map { "\(s)://\($0)" } } ?? baseURL.absoluteString
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
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        var originComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        originComponents.path = ""; originComponents.query = nil; originComponents.fragment = nil
        let origin = originComponents.string ?? baseURL.absoluteString
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")
        let maxAttempts = (url.host == "127.0.0.1" || url.host == "localhost") ? 1 : 2
        var lastError: Error = MovieSourceError.invalidData
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: req)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw MovieSourceError.invalidData }
                guard (200..<300).contains(http.statusCode) else { throw MovieSourceError.http(http.statusCode) }
                return try MovieCatalog.object(data)
            } catch {
                try Task.checkCancellation()
                lastError = error
                if case MovieSourceError.http(let status) = error, status != 429, !(500...599).contains(status) { throw error }
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: 180_000_000)
                }
            }
        }
        throw lastError
    }
}
