import Foundation

@MainActor
final class AnimeService: ObservableObject {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    @Published private(set) var baseURL = URL(string: "https://animevietsub.vip/")!
    @Published private(set) var homeSections: [AnimeSection] = []
    @Published private(set) var homeLoading = false
    @Published private(set) var status = "Đang xác định máy chủ AnimeVietsub…"
    @Published private(set) var verificationGeneration = 0
    @Published private(set) var imageGeneration = 0
    @Published private(set) var source: ContentSource = .anime
    let website = WebsiteSession()

    @Published private(set) var movieCategories: [AnimeCategory] = []
    var categories: [AnimeCategory] { source.isMovie ? movieCategories : animeCategories }
    var contentName: String { source.isMovie ? "phim" : "anime" }
    private let film4k = MovieProvider(source: .film4k)
    private let phim4k = MovieProvider(source: .phim4k)
    private let kkphim = MovieProvider(source: .kkphim)
    private struct HomeSnapshot {
        let sections: [AnimeSection]
        let categories: [AnimeCategory]
        let baseURL: URL
        let date: Date
    }
    private var homeCache: [ContentSource: HomeSnapshot] = [:]
    private var htmlCache: [URL: (Date, String)] = [:]
    private var detailCache: [String: (Date, AnimeDetail)] = [:]
    private var homeRequestID = UUID()
    private var homeTask: Task<Void, Never>?

    private let animeCategories: [AnimeCategory] = [
        .init(title: "TV/Series", path: "/anime-bo/"),
        .init(title: "Movie/OVA", path: "/anime-le/"),
        .init(title: "Hoạt hình Trung Quốc", path: "/hoat-hinh-trung-quoc/"),
        .init(title: "Đang chiếu", path: "/danh-sach/list-dang-chieu/"),
        .init(title: "Trọn bộ", path: "/danh-sach/list-tron-bo/"),
        .init(title: "Action", path: "/the-loai/hanh-dong/"),
        .init(title: "Adventure", path: "/the-loai/phieu-luu/"),
        .init(title: "Comedy", path: "/the-loai/hai-huoc/"),
        .init(title: "Drama", path: "/the-loai/drama/"),
        .init(title: "Fantasy", path: "/the-loai/phep-thuat/"),
        .init(title: "Horror", path: "/the-loai/kinh-di/"),
        .init(title: "Romance", path: "/the-loai/tinh-cam/"),
        .init(title: "Sci-Fi", path: "/the-loai/sci-fi/"),
        .init(title: "School", path: "/the-loai/truong-hoc/"),
        .init(title: "Shounen", path: "/the-loai/shounen/"),
        .init(title: "Slice of Life", path: "/the-loai/doi-thuong/"),
        .init(title: "Supernatural", path: "/the-loai/sieu-nhien/"),
        .init(title: "Sports", path: "/the-loai/the-thao/"),
        .init(title: "Mecha", path: "/the-loai/mecha/"),
        .init(title: "Mystery", path: "/the-loai/mystery/"),
        .init(title: "Psychological", path: "/the-loai/psychological/"),
        .init(title: "Harem", path: "/the-loai/harem/"),
        .init(title: "Ecchi", path: "/the-loai/ecchi/"),
        .init(title: "Seinen", path: "/the-loai/seinen/")
    ]

    private let resolver = DomainResolver.shared
    private let session: URLSession

    func selectSource(_ value: ContentSource) {
        guard source != value else { return }
        homeTask?.cancel()
        homeTask = nil
        let generation = UUID()
        homeRequestID = generation
        source = value
        let cached = homeCache[value]
        homeSections = cached?.sections ?? []
        movieCategories = cached?.categories ?? (value.isMovie ? provider(value).categories : [])
        homeLoading = cached == nil
        status = "Đang kết nối \(value.subtitle)…"
        if value.isMovie { baseURL = provider(value).baseURL }
        else { baseURL = URL(string: "https://animevietsub.vip")! }
        if let cached {
            baseURL = cached.baseURL
            status = ""
            if Date().timeIntervalSince(cached.date) < 300 { return }
        }
        imageGeneration += 1
        homeTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoadHome(generation: generation, selectedSource: value, forceDomainRefresh: false)
        }
    }

    private func provider(_ source: ContentSource) -> MovieProvider {
        switch source {
        case .film4k: return film4k
        case .kkphim: return kkphim
        case .phim4k, .anime: return phim4k
        }
    }

    private func saveHome(_ selected: ContentSource) {
        homeCache[selected] = HomeSnapshot(sections: homeSections, categories: movieCategories, baseURL: baseURL, date: Date())
    }

    func resolvePlayback(_ episode: Episode, refresh: Bool = false) async throws -> ResolvedPlayback {
        try await provider(episode.source).resolve(episode, refresh: refresh)
    }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "vi-VN,vi;q=0.9,en;q=0.8",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        session = URLSession(configuration: configuration)
    }

    func loadHome(forceDomainRefresh: Bool = false) async {
        if forceDomainRefresh {
            homeCache[source] = nil
            htmlCache.removeAll()
            detailCache.removeAll()
            if source.isMovie { provider(source).invalidate() }
        } else if let cached = homeCache[source], Date().timeIntervalSince(cached.date) < 300 {
            return
        }
        if !forceDomainRefresh, let existing = homeTask {
            await existing.value
            return
        }
        homeTask?.cancel()
        let generation = UUID()
        homeRequestID = generation
        let selectedSource = source
        homeLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadHome(generation: generation, selectedSource: selectedSource, forceDomainRefresh: forceDomainRefresh)
        }
        homeTask = task
        await task.value
    }

    private func performLoadHome(generation: UUID, selectedSource: ContentSource, forceDomainRefresh: Bool) async {
        guard homeRequestID == generation, !Task.isCancelled else { return }
        status = forceDomainRefresh ? "Đang cập nhật tên miền…" : "Đang tải anime…"
        defer {
            if homeRequestID == generation {
                homeLoading = false
                homeTask = nil
            }
        }

        if selectedSource.isMovie {
            status = "Đang tải \(selectedSource.title)…"
            do {
                let provider = provider(selectedSource)
                let sections = try await provider.home { [weak self] initial in
                    guard let self, self.homeRequestID == generation, !Task.isCancelled else { return }
                    self.homeSections = initial
                    self.movieCategories = provider.categories
                    self.baseURL = provider.baseURL
                    self.homeLoading = false
                    self.status = ""
                    self.saveHome(selectedSource)
                }
                try Task.checkCancellation()
                guard homeRequestID == generation else { return }
                homeSections = sections
                movieCategories = provider.categories
                baseURL = provider.baseURL
                imageGeneration += 1
                status = ""
                saveHome(selectedSource)
            } catch {
                guard homeRequestID == generation else { return }
                register(error)
            }
            return
        }

        let resolved = await resolver.resolve(force: forceDomainRefresh)
        guard homeRequestID == generation else { return }
        baseURL = resolved
        do {
            let html = try await fetchHTML(url: baseURL)
            guard homeRequestID == generation else { return }
            let parsed = HTMLParser.sections(from: html, baseURL: baseURL)

            guard !parsed.isEmpty else { throw AnimeServiceError.emptyData }
            homeSections = parsed
            imageGeneration += 1
            status = ""
            saveHome(selectedSource)
        } catch {
            guard homeRequestID == generation else { return }
            register(error)
        }
    }

    func list(path: String, page: Int = 1) async throws -> [Anime] {
        if source.isMovie { return try await provider(source).list(path: path, page: page) }
        let url = try makeURL(path)
        let html = try await fetchHTML(url: url)
        try Task.checkCancellation()
        let currentBase = await resolver.resolve()
        let items = HTMLParser.animes(from: html, baseURL: currentBase)
        guard !items.isEmpty else { throw AnimeServiceError.emptyData }
        return items
    }

    func search(_ query: String) async throws -> [Anime] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        if source.isMovie { return try await provider(source).search(clean) }
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw AnimeServiceError.invalidURL
        }
        return try await list(path: "/tim-kiem/\(encoded)/")
    }

    func detail(for anime: Anime) async throws -> AnimeDetail {
        if anime.source.isMovie { return try await provider(anime.source).detail(anime) }
        if let (date, detail) = detailCache[anime.id], Date().timeIntervalSince(date) < 120 { return detail }
        let resolved = await resolver.resolve()
        let detailURL = HTMLParser.rebasedAnimeURL(anime.url, baseURL: resolved)
        let html = try await fetchHTML(url: detailURL)
        let pageBase = await resolver.resolve()
        let metadata = HTMLParser.detail(from: html, anime: anime, baseURL: pageBase)
        var episodes = metadata.episodes
        if let watchURL = HTMLParser.watchURL(from: html, baseURL: pageBase), watchURL != detailURL {
            // Detail pages often contain only a preview of the latest episodes.
            let watchHTML = try await fetchHTML(url: watchURL)
            let full = HTMLParser.detail(from: watchHTML, anime: anime, baseURL: pageBase).episodes
            episodes = HTMLParser.mergedEpisodes(episodes, full)
            let numbered = full.compactMap(\.number)
            let appearsTruncated = (numbered.max() ?? 0) > Set(numbered).count
            if full.count <= 1 || appearsTruncated {
                // Read the rendered DOM when the server list is populated by JavaScript.
                let (rendered, renderedURL) = try await website.load(watchURL, waitForEpisodes: true)
                let dynamic = HTMLParser.detail(from: rendered, anime: anime, baseURL: renderedURL).episodes
                episodes = HTMLParser.mergedEpisodes(episodes, dynamic)
            }
        } else if episodes.count <= 1 {
            let (rendered, renderedURL) = try await website.load(detailURL, waitForEpisodes: true)
            episodes = HTMLParser.mergedEpisodes(episodes, HTMLParser.detail(from: rendered, anime: anime, baseURL: renderedURL).episodes)
        }
        try Task.checkCancellation()
        let detail = AnimeDetail(title: metadata.title, posterURL: metadata.posterURL, bannerURL: metadata.bannerURL,
                                 summary: metadata.summary, info: metadata.info, episodes: episodes)
        if detailCache.count >= 40 { detailCache.removeAll() }
        detailCache[anime.id] = (Date(), detail)
        return detail
    }

    func html(for url: URL) async throws -> String {
        try await fetchHTML(url: url)
    }

    func register(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            status = "Kết nối đã tạm dừng. Bạn có thể thử lại."
            return
        }
        status = error.localizedDescription
    }

    private func fetchHTML(url: URL) async throws -> String {
        do { return try await fetchHTMLOnce(url: url) }
        catch {
            try Task.checkCancellation()
            if let network = error as? URLError,
               [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed].contains(network.code) {
                let resolved = await resolver.resolve(force: true)
                try Task.checkCancellation()
                if source == .anime { baseURL = resolved }
                return try await fetchHTMLOnce(url: HTMLParser.rebasedAnimeURL(url, baseURL: resolved))
            }
            if case AnimeServiceError.http(let code) = error, (500...599).contains(code) {
                try await Task.sleep(nanoseconds: 400_000_000)
                return try await fetchHTMLOnce(url: url)
            }
            throw error
        }
    }

    private func fetchHTMLOnce(url: URL) async throws -> String {
        try Task.checkCancellation()
        if let (date, html) = htmlCache[url], Date().timeIntervalSince(date) < 120 { return html }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AnimeServiceError.invalidResponse }
        let responseURL = http.url ?? url
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""

        if http.statusCode == 403 || HTMLParser.containsVerification(html) {
            let (browserHTML, browserURL) = try await website.load(responseURL)
            if let accepted = await resolver.acceptResolvedURL(browserURL), source == .anime { baseURL = accepted }
            if source == .anime { imageGeneration += 1 }
            try Task.checkCancellation()
            cacheHTML(browserHTML, for: url)
            return browserHTML
        }
        guard (200..<400).contains(http.statusCode) else { throw AnimeServiceError.http(http.statusCode) }
        guard !html.isEmpty else { throw AnimeServiceError.emptyData }

        if let accepted = await resolver.acceptResolvedURL(responseURL), source == .anime, accepted.host != baseURL.host {
            baseURL = accepted
        }
        cacheHTML(html, for: url)
        return html
    }

    private func cacheHTML(_ html: String, for url: URL) {
        if htmlCache.count >= 60 { htmlCache.removeAll() }
        htmlCache[url] = (Date(), html)
    }

    private func makeURL(_ path: String) throws -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AnimeServiceError.invalidURL
        }
        return url
    }
}
