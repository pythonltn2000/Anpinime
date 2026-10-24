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
        homeSections = []
        movieCategories = []
        homeLoading = true
        status = "Đang kết nối \(value.subtitle)…"
        if value.isMovie { baseURL = provider(value).baseURL }
        else { baseURL = URL(string: "https://animevietsub.vip")! }
        imageGeneration += 1
        homeTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoadHome(generation: generation, selectedSource: value, forceDomainRefresh: false)
        }
    }

    private func provider(_ source: ContentSource) -> MovieProvider { source == .film4k ? film4k : phim4k }

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
        if !forceDomainRefresh, homeLoading, let existing = homeTask {
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
                let sections = try await provider.home()
                try Task.checkCancellation()
                guard homeRequestID == generation else { return }
                homeSections = sections
                movieCategories = provider.categories
                baseURL = provider.baseURL
                imageGeneration += 1
                status = "Đã kết nối \(selectedSource.subtitle)"
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
            var parsed = HTMLParser.sections(from: html, baseURL: baseURL)

            if parsed.count < 2 {
                let fallbacks: [(String, String)] = [
                    ("Hoạt hình Trung Quốc", "/hoat-hinh-trung-quoc/"),
                    ("Đang chiếu", "/danh-sach/list-dang-chieu/"),
                    ("Trọn bộ", "/danh-sach/list-tron-bo/")
                ]
                for (title, path) in fallbacks {
                    if let items = try? await list(path: path), !items.isEmpty {
                        parsed.append(AnimeSection(title: title, items: items))
                    }
                    guard homeRequestID == generation else { return }
                }
            }

            guard !parsed.isEmpty else { throw AnimeServiceError.emptyData }
            homeSections = parsed
            imageGeneration += 1
            status = "Đã kết nối \(baseURL.host ?? "AnimeVietsub")"
        } catch {
            guard homeRequestID == generation else { return }
            register(error)
        }
    }

    func list(path: String, page: Int = 1) async throws -> [Anime] {
        if source.isMovie { return try await provider(source).list(path: path, page: page) }
        let url = try makeURL(path)
        let html = try await fetchHTML(url: url)
        let items = HTMLParser.animes(from: html, baseURL: baseURL)
        guard !items.isEmpty else { throw AnimeServiceError.emptyData }
        return items
    }

    func search(_ query: String) async throws -> [Anime] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        if source.isMovie { return try await provider(source).search(clean) }
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw AnimeServiceError.invalidURL
        }
        return try await list(path: "/tim-kiem/\(encoded)/")
    }

    func detail(for anime: Anime) async throws -> AnimeDetail {
        if anime.source.isMovie { return try await provider(anime.source).detail(anime) }
        let html = try await fetchHTML(url: anime.url)
        return HTMLParser.detail(from: html, anime: anime, baseURL: baseURL)
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
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnimeServiceError.invalidResponse }
        let responseURL = http.url ?? url
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""

        if http.statusCode == 403 || HTMLParser.containsVerification(html) {
            let (browserHTML, browserURL) = try await website.load(responseURL)
            if let accepted = await resolver.acceptResolvedURL(browserURL), source == .anime { baseURL = accepted }
            if source == .anime { imageGeneration += 1 }
            return browserHTML
        }
        guard (200..<400).contains(http.statusCode) else { throw AnimeServiceError.http(http.statusCode) }
        guard !html.isEmpty else { throw AnimeServiceError.emptyData }

        if let accepted = await resolver.acceptResolvedURL(responseURL), source == .anime, accepted.host != baseURL.host {
            baseURL = accepted
        }
        return html
    }

    private func makeURL(_ path: String) throws -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AnimeServiceError.invalidURL
        }
        return url
    }
}
