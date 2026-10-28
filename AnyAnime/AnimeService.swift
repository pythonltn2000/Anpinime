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
        let notice: String
        let complete: Bool
    }
    private var homeCache: [ContentSource: HomeSnapshot] = [:]
    private var htmlCache: [URL: (Date, String)] = [:]
    private var htmlRequests: [URL: Task<String, Error>] = [:]
    private var detailCache: [String: (Date, AnimeDetail)] = [:]
    private var scheduleCache: [DayOfWeek: [AnimeScheduleItem]] = [:]
    private var scheduleCacheDate = Date.distantPast
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
            status = cached.notice
            if cached.complete, Date().timeIntervalSince(cached.date) < 300 { return }
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

    private func saveHome(_ selected: ContentSource, complete: Bool = true) {
        homeCache[selected] = HomeSnapshot(sections: homeSections, categories: movieCategories, baseURL: baseURL, date: Date(), notice: status, complete: complete)
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
        } else if let cached = homeCache[source], cached.complete, Date().timeIntervalSince(cached.date) < 300 {
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
                    self.saveHome(selectedSource, complete: false)
                }
                try Task.checkCancellation()
                guard homeRequestID == generation else { return }
                homeSections = sections
                movieCategories = provider.categories
                baseURL = provider.baseURL
                imageGeneration += 1
                status = provider.notice
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

    func search(_ query: String, source requestedSource: ContentSource? = nil) async throws -> [Anime] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let selected = requestedSource ?? source
        if selected.isMovie { return try await provider(selected).search(clean) }
        let currentBase = await resolver.resolve()
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "/tim-kiem/" + encoded + "/", relativeTo: currentBase)?.absoluteURL else {
            throw AnimeServiceError.invalidURL
        }
        let html = try await fetchHTML(url: url)
        try Task.checkCancellation()
        return HTMLParser.animes(from: html, baseURL: currentBase)
    }

    func cachedDetail(for id: String) -> AnimeDetail? {
        guard let (date, detail) = detailCache[id], Date().timeIntervalSince(date) < 180 else { return nil }
        return detail
    }

    func detailMetadata(for anime: Anime, forceRefresh: Bool = false) async throws -> AnimeDetail {
        if anime.source.isMovie { return try await provider(anime.source).detail(anime) }
        if !forceRefresh, let cached = cachedDetail(for: anime.id) {
            return cached
        }
        let domainStart = Date()
        let resolved = await resolver.resolve(force: forceRefresh)
        #if DEBUG
        print("[Anime] domain_resolution_ms=\(Int(Date().timeIntervalSince(domainStart) * 1000))")
        #endif
        let detailURL = HTMLParser.rebasedAnimeURL(anime.url, baseURL: resolved)
        if forceRefresh { htmlCache[detailURL] = nil; detailCache[anime.id] = nil }
        let detailStart = Date()
        let html = try await fetchHTML(url: detailURL)
        #if DEBUG
        print("[Anime] domain=\(resolved.host ?? "") detail_http_ms=\(Int(Date().timeIntervalSince(detailStart) * 1000))")
        #endif
        let pageBase = await resolver.resolve()
        let parseStart = Date()
        let metadata = HTMLParser.detail(from: html, anime: anime, baseURL: pageBase, includeEpisodes: false)
        #if DEBUG
        print("[Anime] detail_parse_ms=\(Int(Date().timeIntervalSince(parseStart) * 1000))")
        #endif
        return metadata
    }

    func loadEpisodes(for anime: Anime, initialDetail: AnimeDetail, forceRefresh: Bool = false) async throws -> [Episode] {
        if anime.source.isMovie { return initialDetail.episodes }
        if !forceRefresh, let cached = cachedDetail(for: anime.id), !cached.episodes.isEmpty {
            return cached.episodes
        }
        let resolved = await resolver.resolve(force: forceRefresh)
        let detailURL = HTMLParser.rebasedAnimeURL(anime.url, baseURL: resolved)
        var episodes = initialDetail.episodes

        var detailHTML = ""
        if let cached = cachedHTML(for: detailURL) {
            detailHTML = cached
        } else {
            do {
                detailHTML = try await fetchHTML(url: detailURL)
            } catch {
                if episodes.isEmpty { throw error }
            }
        }

        let pageBase = await resolver.resolve()
        if !detailHTML.isEmpty {
            let start = Date()
            let parsed = try await parseAnimeEpisodes(detailHTML, anime: anime, baseURL: pageBase)
            episodes = HTMLParser.mergedEpisodes(episodes, parsed)
            #if DEBUG
            print("[Anime] episode_parse_ms=\(Int(Date().timeIntervalSince(start) * 1000)) episode_count=\(episodes.count)")
            #endif
        }
        if HTMLParser.hasCompleteStreamedEpisodes(detailHTML, episodes: episodes) {
            // The page supplied its entire numbered list; a second network or WebKit request adds no episodes.
        } else if let watchURL = HTMLParser.watchURL(from: detailHTML, baseURL: pageBase, animeURL: anime.url), watchURL != detailURL {
            do {
                if forceRefresh { htmlCache[watchURL] = nil }
                let watchHTML = try await fetchHTML(url: watchURL)
                let full = try await parseAnimeEpisodes(watchHTML, anime: anime, baseURL: pageBase)
                episodes = HTMLParser.mergedEpisodes(episodes, full)
                let numbered = full.compactMap(\.number)
                let appearsTruncated = (numbered.max() ?? 0) > Set(numbered).count
                if episodes.isEmpty || appearsTruncated {
                    let (rendered, renderedURL) = try await website.load(watchURL, waitForEpisodes: true)
                    cacheHTML(rendered, for: watchURL)
                    let dynamic = try await parseAnimeEpisodes(rendered, anime: anime, baseURL: renderedURL)
                    episodes = HTMLParser.mergedEpisodes(episodes, dynamic)
                }
            } catch {
                if episodes.isEmpty { throw error }
            }
        } else if episodes.isEmpty {
            let (rendered, renderedURL) = try await website.load(detailURL, waitForEpisodes: true)
            cacheHTML(rendered, for: detailURL)
            let dynamic = try await parseAnimeEpisodes(rendered, anime: anime, baseURL: renderedURL)
            episodes = HTMLParser.mergedEpisodes(episodes, dynamic)
        }

        if !episodes.isEmpty {
            let merged = AnimeDetail(title: initialDetail.title, posterURL: initialDetail.posterURL,
                                     bannerURL: initialDetail.bannerURL, summary: initialDetail.summary,
                                     info: initialDetail.info, episodes: episodes)
            if detailCache.count >= 40 { detailCache.removeAll() }
            detailCache[anime.id] = (Date(), merged)
        }
        return episodes
    }

    private func parseAnimeEpisodes(_ html: String, anime: Anime, baseURL: URL) async throws -> [Episode] {
        let task = Task.detached(priority: .userInitiated) {
            HTMLParser.detail(from: html, anime: anime, baseURL: baseURL).episodes
        }
        return try await withTaskCancellationHandler(operation: {
            let episodes = await task.value
            try Task.checkCancellation()
            return episodes
        }, onCancel: { task.cancel() })
    }

    func detail(for anime: Anime) async throws -> AnimeDetail {
        if anime.source.isMovie { return try await provider(anime.source).detail(anime) }
        if let (date, detail) = detailCache[anime.id], Date().timeIntervalSince(date) < 180, !detail.episodes.isEmpty {
            return detail
        }
        let startTime = Date()
        let metadata = try await detailMetadata(for: anime)
        let parseStart = Date()
        let episodes = try await loadEpisodes(for: anime, initialDetail: metadata)
        let parseMs = Int(Date().timeIntervalSince(parseStart) * 1000)

        #if DEBUG
        let resolved = await resolver.resolve()
        print("[Anime] domain=\(resolved.host ?? "")")
        print("[Anime] episodes_load_ms=\(parseMs)")
        print("[Anime] episode_accepted=\(episodes.count)")
        print("[Anime] episode_count=\(episodes.count)")
        print("[Anime] total_detail_ms=\(Int(Date().timeIntervalSince(startTime) * 1000))")
        #endif

        try Task.checkCancellation()
        let detail = AnimeDetail(title: metadata.title, posterURL: metadata.posterURL, bannerURL: metadata.bannerURL,
                                 summary: metadata.summary, info: metadata.info, episodes: episodes)
        if !episodes.isEmpty {
            if detailCache.count >= 40 { detailCache.removeAll() }
            detailCache[anime.id] = (Date(), detail)
        }
        return detail
    }

    var scheduleUpdatedAt: Date? { scheduleCache.isEmpty ? nil : scheduleCacheDate }

    func schedule(forceRefresh: Bool = false) async throws -> [DayOfWeek: [AnimeScheduleItem]] {
        if !forceRefresh, !scheduleCache.isEmpty, Date().timeIntervalSince(scheduleCacheDate) < 600 {
            return scheduleCache
        }
        let resolved = await resolver.resolve(force: forceRefresh)
        let scheduleURL = resolved.appendingPathComponent("lich-chieu-phim.html")
        if forceRefresh { htmlCache[scheduleURL] = nil }
        let html = try await fetchHTML(url: scheduleURL)
        let parsed = HTMLParser.schedule(from: html, baseURL: resolved)
        guard !parsed.values.allSatisfy({ $0.isEmpty }) else {
            throw AnimeServiceError.emptyData
        }
        scheduleCache = parsed
        scheduleCacheDate = Date()
        return parsed
    }

    func cachedHTML(for url: URL) -> String? {
        guard let (date, html) = htmlCache[url], Date().timeIntervalSince(date) < 120 else { return nil }
        return html
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
        try Task.checkCancellation()
        if let html = cachedHTML(for: url) { return html }
        if let pending = htmlRequests[url] {
            let html = try await pending.value
            try Task.checkCancellation()
            return html
        }
        let task = Task { try await fetchHTMLWithRetry(url: url) }
        htmlRequests[url] = task
        defer { htmlRequests[url] = nil }
        let html = try await task.value
        try Task.checkCancellation()
        return html
    }

    private func fetchHTMLWithRetry(url: URL) async throws -> String {
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
        let requestStart = Date()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AnimeServiceError.invalidResponse }
        #if DEBUG
        print("[Anime] page_status=\(http.statusCode) page_http_ms=\(Int(Date().timeIntervalSince(requestStart) * 1000))")
        #endif
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
