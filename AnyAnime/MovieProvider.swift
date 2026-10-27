import Foundation

@MainActor
final class MovieProvider {
    let source: ContentSource
    private(set) var baseURL: URL
    private var publicCategories: [AnimeCategory] = []
    var categories: [AnimeCategory] { source == .phim4k ? appProvider.categories : publicCategories }
    var notice: String { source == .phim4k ? appProvider.notice : "" }
    private let appProvider: Phim4KProvider
    private var format: Phim4KFormat
    private let session: URLSession
    private var ticket: String?
    private var ticketExpiry = Date.distantPast
    private var cachedJSON: [URL: (Date, MovieCatalog.Object)] = [:]

    init(source: ContentSource, session suppliedSession: URLSession? = nil, source2Configuration: Phim4KProvider.Configuration? = nil) {
        self.source = source
        format = source == .film4k ? .free2 : .free1
        baseURL = source == .kkphim ? URL(string: "https://phimapi.com")! : format.defaultURL
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { baseURL = URL(string: "http://127.0.0.1:8765")! }
        #endif
        publicCategories = source == .phim4k ? [] : format.defaultCategories
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        session = suppliedSession ?? URLSession(configuration: config)
        appProvider = Phim4KProvider(session: session, configuration: source2Configuration)
    }

    func invalidate() {
        cachedJSON.removeAll()
        appProvider.invalidate()
    }

    func home(onInitial: ([AnimeSection]) -> Void = { _ in }) async throws -> [AnimeSection] {
        #if DEBUG
        // Keep the historical ticket/relay fixture independent of the production source.
        if source == .film4k, PlaybackSmokeTest.providerFixture {
            return MovieCatalog.filmSections(try await request(MovieCatalog.route("api/home", base: baseURL)), base: baseURL)
        }
        #endif
        if source == .phim4k {
            let sections = try await appProvider.home { initial in
                self.baseURL = self.appProvider.baseURL
                onInitial(initial)
            }
            baseURL = appProvider.baseURL
            return sections
        }
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
        if source == .phim4k { return try await appProvider.list(path: path, page: page) }
        let target = path.isEmpty || path == "latest" ? format.listPath : path
        guard MovieCatalog.isCatalogPath(target, format: format) else { throw MovieSourceError.invalidData }
        let json = try await catalogRequest(MovieCatalog.route(target, base: baseURL, query: [.init(name: "page", value: String(page))]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format, source: source)
    }

    func search(_ query: String) async throws -> [Anime] {
        if source == .phim4k { return try await appProvider.search(query) }
        let json = try await catalogRequest(MovieCatalog.route(format.searchPath, base: baseURL, query: [.init(name: "keyword", value: query)]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format, source: source)
    }

    func detail(_ anime: Anime) async throws -> AnimeDetail {
        guard anime.source == source else { throw MovieSourceError.invalidData }
        if source == .phim4k { return try await appProvider.detail(anime) }
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
        guard episode.source == source else { throw MovieSourceError.invalidData }
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
        case .catalogEpisode(let detailURL, let serverName, let episodeKey):
            // Refresh the exact provider, server and episode, even if the API reorders rows.
            let activeDetailURL = detailURL
            let json = try await (source == .phim4k ? appProvider.episodeJSON(detailURL) : request(detailURL))
            guard let row = MovieCatalog.episodeRow(json, serverName: serverName, key: episodeKey),
                  let stream = MovieCatalog.legacyStream(row, base: activeDetailURL) else { throw MovieSourceError.noVideo }
            let web = MovieCatalog.url(row["link_embed"] ?? row["embed"], base: activeDetailURL)
            let originHost = activeDetailURL.scheme.flatMap { s in activeDetailURL.host.map { "\(s)://\($0)" } } ?? baseURL.absoluteString
            return ResolvedPlayback(url: stream.url, headers: ["Referer": originHost + "/", "Origin": originHost, "User-Agent": AnimeService.userAgent],
                                    webURL: stream.web ? web : nil, isWeb: stream.web)
        case .phim4kCore(let detailURL, let seasonID, let episodeID):
            guard source == .phim4k else { throw MovieSourceError.invalidData }
            return try await appProvider.resolveCore(detailURL: detailURL, seasonID: seasonID, episodeID: episodeID)
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
        guard url.host == baseURL.host, url.scheme == baseURL.scheme else {
            throw MovieSourceError.unavailable("Đường dẫn không thuộc " + source.title + ".")
        }
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
