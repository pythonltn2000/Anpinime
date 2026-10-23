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
            candidates = Phim4KFormat.allCases.map { ($0.defaultURL, $0) }
        }
        #if DEBUG
        if PlaybackSmokeTest.providerFixture { candidates = [(URL(string: "http://127.0.0.1:8765")!, .free1)] }
        #endif
        for (url, candidateFormat) in candidates {
            do {
                let json = try await request(MovieCatalog.route(candidateFormat.listPath, base: url, query: [.init(name: "page", value: "1")]))
                let items = MovieCatalog.legacyItems(json, base: url, format: candidateFormat)
                guard !items.isEmpty else { throw MovieSourceError.invalidData }
                try Task.checkCancellation()
                baseURL = url; format = candidateFormat
                categories = [.init(title: "Phim mới cập nhật", path: "latest")]
                return [.init(title: "Phim4K • Mới cập nhật", items: items)]
            } catch {
                if Task.isCancelled { throw CancellationError() }
            }
        }
        throw MovieSourceError.unavailable(custom.isEmpty
            ? "Nguồn phim 2 (Phim4K) hiện không kết nối được các máy chủ Free1/Free2 ghi trong IPA. Bạn có thể chọn Nguồn phim 1 hoặc cập nhật địa chỉ Phim4K trong Cài đặt."
            : "Không đọc được dữ liệu Phim4K tại địa chỉ đã lưu. Kiểm tra địa chỉ và định dạng Free1/Free2 trong Cài đặt.")
    }

    func list(path: String, page: Int = 1) async throws -> [Anime] {
        if source == .film4k {
            let filters = URLComponents(string: "?" + path)?.queryItems ?? []
            let json = try await request(MovieCatalog.route("api/home", base: baseURL,
                                                         query: filters + [.init(name: "page", value: String(page))]))
            return MovieCatalog.filmItems(json["list"] as? [MovieCatalog.Object] ?? [], base: baseURL)
        }
        let json = try await request(MovieCatalog.route(format.listPath, base: baseURL, query: [.init(name: "page", value: String(page))]))
        return MovieCatalog.legacyItems(json, base: baseURL, format: format)
    }

    func search(_ query: String) async throws -> [Anime] {
        let path = source == .film4k ? "api/search/suggest" : format.searchPath
        let key = source == .film4k ? "q" : "keyword"
        let json = try await request(MovieCatalog.route(path, base: baseURL, query: [.init(name: key, value: query)]))
        return source == .film4k
            ? MovieCatalog.filmItems(json["list"] as? [MovieCatalog.Object] ?? [], base: baseURL)
            : MovieCatalog.legacyItems(json, base: baseURL, format: format)
    }

    func detail(_ anime: Anime) async throws -> AnimeDetail {
        if source == .film4k {
            let json = try await request(MovieCatalog.route("api/title/" + anime.url.lastPathComponent, base: baseURL))
            return try MovieCatalog.filmDetail(json, anime: anime, base: baseURL)
        }
        let json = try await request(anime.url)
        return try MovieCatalog.legacyDetail(json, anime: anime)
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
            return ResolvedPlayback(url: stream.url, headers: ["Referer": baseURL.absoluteString, "User-Agent": AnimeService.userAgent],
                                    webURL: web, isWeb: stream.web)
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
