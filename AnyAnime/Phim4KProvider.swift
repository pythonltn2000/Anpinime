import Foundation

@MainActor
final class Phim4KProvider {
    struct Catalog {
        let id: String
        let url: URL
        let format: Phim4KFormat
        var name: String { "Phim4K · " + (id == "free2" ? "Free2" : "Free1") }
    }
    struct Configuration {
        let core: MovieSourceDirectory.CoreAPI?
        let catalogs: [Catalog]
    }

    private let session: URLSession
    private let suppliedConfiguration: Configuration?
    private var configuration: Configuration?
    private var cache: [URL: (Date, Any)] = [:]
    private(set) var categories = Phim4KCatalog.categories([:])
    private(set) var notice = ""
    var baseURL: URL { configuration?.core?.baseURL ?? configuration?.catalogs.first?.url ?? MovieSourceDirectory.coreAPI().baseURL }

    init(session: URLSession, configuration: Configuration? = nil) {
        self.session = session
        suppliedConfiguration = configuration
    }

    func invalidate() { cache.removeAll(); configuration = nil; notice = "" }

    private func configure() async throws -> Configuration {
        if let configuration { return configuration }
        let result: Configuration
        if let suppliedConfiguration {
            result = suppliedConfiguration
        } else {
            #if DEBUG
            if PlaybackSmokeTest.providerFixture {
                let fixture = Configuration(core: nil, catalogs: [Catalog(id: "free1", url: URL(string: "http://127.0.0.1:8765")!, format: .free1)])
                configuration = fixture
                return fixture
            }
            #endif
            let custom = UserDefaults.standard.string(forKey: "AnPinime.phim4kURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty {
                guard let url = URL(string: custom), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                    throw MovieSourceError.unavailable("Địa chỉ Phim4K phải là URL HTTPS hợp lệ.")
                }
                let format = Phim4KFormat(rawValue: UserDefaults.standard.string(forKey: "AnPinime.phim4kFormat") ?? "") ?? .free1
                result = Configuration(core: nil, catalogs: [Catalog(id: format.rawValue, url: url, format: format)])
            } else {
                await MovieSourceDirectory.refresh(session: session)
                try Task.checkCancellation()
                result = Configuration(core: MovieSourceDirectory.coreAPI(), catalogs: MovieSourceDirectory.catalogs().map {
                    Catalog(id: $0.id, url: $0.url, format: $0.format)
                })
            }
        }
        configuration = result
        return result
    }

    func home(onInitial: ([AnimeSection]) -> Void) async throws -> [AnimeSection] {
        let config = try await configure()
        var sections: [AnimeSection] = []
        var failures: [String] = []
        categories = config.core == nil ? [] : Phim4KCatalog.categories([:])
        if let core = config.core {
            do {
                let json = try await object(MovieCatalog.route(Phim4KCatalog.prefix + "home_content_for_android", base: core.baseURL))
                sections = Phim4KCatalog.sections(json, base: core.baseURL)
                guard !sections.isEmpty else { throw MovieSourceError.invalidData }
                categories = Phim4KCatalog.categories(json)
                onInitial(sections)
                let rows = Phim4KCatalog.homeRows(json)
                var additional: [Int: AnimeSection] = [:]
                await withTaskGroup(of: (Int, AnimeSection?).self) { group in
                    for (index, row) in rows.enumerated() {
                        group.addTask { [weak self] in
                            guard let self, let items = try? await self.list(path: row.path, page: 1), !items.isEmpty else { return (index, nil) }
                            return (index, AnimeSection(title: row.title, items: items, categoryPath: row.path))
                        }
                    }
                    for await (index, section) in group { if let section { additional[index] = section } }
                }
                sections = additional.keys.sorted().compactMap { additional[$0] } + sections
            } catch {
                try Task.checkCancellation()
                failures.append("Kho Phim4K: " + error.localizedDescription)
            }
        }
        var extra: [Int: [Anime]] = [:]
        // Free1/Free2 belong to the reference app. They are labelled, never used to
        // silently replace Core or a failed detail/episode request.
        await withTaskGroup(of: (Int, [Anime], String?).self) { group in
            for (index, catalog) in config.catalogs.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, [], nil) }
                    do { return (index, try await self.freeList(catalog, path: catalog.format.listPath, page: 1), nil) }
                    catch { return (index, [], catalog.name + ": " + error.localizedDescription) }
                }
            }
            for await (index, items, error) in group {
                extra[index] = items
                if let error { failures.append(error) }
            }
        }
        try Task.checkCancellation()
        for (index, catalog) in config.catalogs.enumerated() {
            if let items = extra[index], !items.isEmpty {
                sections.append(AnimeSection(title: catalog.name, items: items, categoryPath: catalog.id + "/" + catalog.format.listPath))
            }
            categories += catalog.format.defaultCategories.map {
                AnimeCategory(title: $0.title, path: catalog.id + "/" + $0.path, group: catalog.name)
            }
        }
        notice = failures.joined(separator: "\n")
        guard !sections.isEmpty else { throw MovieSourceError.unavailable(notice.isEmpty ? "Phim4K chưa trả danh sách phim." : notice) }
        return sections
    }

    func list(path: String, page: Int) async throws -> [Anime] {
        let config = try await configure()
        let target = path.isEmpty || path == "latest" ? (config.core == nil ? (config.catalogs.first.map { $0.id + "/" + $0.format.listPath } ?? "") : "core/movies") : path
        if target.hasPrefix("core/"), let core = config.core {
            let url = try Phim4KCatalog.listRoute(target, base: core.baseURL, page: page)
            let rows = try await request(url) as? [MovieCatalog.Object] ?? []
            return Phim4KCatalog.items(rows, base: core.baseURL, type: target == "core/tvseries" ? "tvseries" : nil)
        }
        for catalog in config.catalogs where target.hasPrefix(catalog.id + "/") {
            return try await freeList(catalog, path: String(target.dropFirst(catalog.id.count + 1)), page: page)
        }
        throw MovieSourceError.unavailable("Danh mục này không thuộc kho Phim4K đang chọn.")
    }

    private func freeList(_ catalog: Catalog, path: String, page: Int) async throws -> [Anime] {
        guard MovieCatalog.isCatalogPath(path, format: catalog.format) else { throw MovieSourceError.invalidData }
        let json = try await object(MovieCatalog.route(path, base: catalog.url, query: [.init(name: "page", value: String(page))]))
        return labelled(MovieCatalog.legacyItems(json, base: catalog.url, format: catalog.format, source: .phim4k), catalog.name)
    }

    func search(_ query: String) async throws -> [Anime] {
        let config = try await configure()
        var results: [Int: [Anime]] = [:]
        var succeeded = false
        var errors: [String] = []
        await withTaskGroup(of: (Int, [Anime]?, String?).self) { group in
            if let core = config.core {
                group.addTask { [weak self] in
                    guard let self else { return (0, nil, nil) }
                    do {
                        let url = MovieCatalog.route(Phim4KCatalog.prefix + "search", base: core.baseURL,
                            query: [.init(name: "q", value: query), .init(name: "page", value: "1"), .init(name: "type", value: "movietvserieslive")])
                        let json = try await self.object(url)
                        let items = Phim4KCatalog.items(json["movie"] as? [MovieCatalog.Object] ?? [], base: core.baseURL, type: "movie")
                            + Phim4KCatalog.items(json["tvseries"] as? [MovieCatalog.Object] ?? [], base: core.baseURL, type: "tvseries")
                        return (0, items, nil)
                    } catch { return (0, nil, "Kho Phim4K: " + error.localizedDescription) }
                }
            }
            for (index, catalog) in config.catalogs.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index + 1, nil, nil) }
                    do {
                        let json = try await self.object(MovieCatalog.route(catalog.format.searchPath, base: catalog.url,
                            query: [.init(name: "keyword", value: query), .init(name: "page", value: "1")]))
                        let items = MovieCatalog.legacyItems(json, base: catalog.url, format: catalog.format, source: .phim4k)
                        return (index + 1, await self.labelled(items, catalog.name), nil)
                    } catch { return (index + 1, nil, catalog.name + ": " + error.localizedDescription) }
                }
            }
            for await (index, items, error) in group {
                if let items { succeeded = true; results[index] = items }
                if let error { errors.append(error) }
            }
        }
        try Task.checkCancellation()
        notice = errors.joined(separator: "\n")
        guard succeeded else { throw MovieSourceError.unavailable(notice) }
        return results.keys.sorted().flatMap { results[$0] ?? [] }
    }

    func detail(_ anime: Anime) async throws -> AnimeDetail {
        guard anime.source == .phim4k else { throw MovieSourceError.invalidData }
        _ = try await configure()
        if isCore(anime.url) { return try Phim4KCatalog.detail(await object(anime.url), anime: anime) }
        return try MovieCatalog.legacyDetail(await object(anime.url), anime: anime, serverPrefix: anime.catalogLabel)
    }

    func resolveCore(detailURL: URL, seasonID: String?, episodeID: String) async throws -> ResolvedPlayback {
        _ = try await configure()
        guard isCore(detailURL) else { throw MovieSourceError.invalidData }
        let json = try await object(detailURL, fresh: true)
        guard let stream = Phim4KCatalog.stream(json, seasonID: seasonID, episodeID: episodeID, base: detailURL) else {
            throw MovieSourceError.unavailable("Máy chủ đã chọn chưa cung cấp URL phát trực tiếp hoặc yêu cầu resolver hợp lệ.")
        }
        let headers = ["User-Agent": "exoplayer", "Referer": baseURL.absoluteString + "/"]
        guard ["https", "http"].contains(stream.url.scheme?.lowercased() ?? ""), stream.url.host != nil else {
            throw MovieSourceError.unavailable("URL phát của máy chủ không hợp lệ.")
        }
        // Web embeds must remain web pages. For direct media, inspect headers
        // without downloading the film or inventing a signed URL.
        if !stream.web {
            var request = URLRequest(url: stream.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.httpMethod = "HEAD"
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let response: URLResponse
            do { (_, response) = try await session.data(for: request) }
            catch {
                throw MovieSourceError.unavailable("Không kết nối được máy chủ đã chọn: " + error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw MovieSourceError.invalidData }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            #if DEBUG
            print("[Phim4K] source_id=phim4k server_id=\(episodeID) media_http_status=\(http.statusCode) media_content_type=\(contentType)")
            #endif
            let kind = Phim4KCatalog.mediaKind(status: http.statusCode, contentType: contentType, url: http.url ?? stream.url)
            if kind == .authenticationRequired {
                throw MovieSourceError.unavailable("AUTH_REQUIRED: Máy chủ yêu cầu quyền truy cập hoặc phiên đăng nhập hợp lệ.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MovieSourceError.unavailable("Máy chủ video trả HTTP \(http.statusCode). Hãy thử lại hoặc chọn máy chủ khác.")
            }
            if kind == .intermediate {
                throw MovieSourceError.unavailable("Máy chủ trả về trang web hoặc JSON thay vì video; cần resolver hợp lệ.")
            }
            if kind == .unknown {
                throw MovieSourceError.unavailable("Không xác định được định dạng video từ phản hồi máy chủ.")
            }
        }
        return ResolvedPlayback(url: stream.url, headers: headers, webURL: nil, isWeb: stream.web)
    }

    func episodeJSON(_ url: URL) async throws -> MovieCatalog.Object {
        _ = try await configure()
        return try await object(url, fresh: true)
    }

    private func isCore(_ url: URL) -> Bool {
        guard let core = configuration?.core else { return false }
        return url.host == core.baseURL.host && url.path == "/" + Phim4KCatalog.prefix + "single_details"
    }

    private func object(_ url: URL, fresh: Bool = false) async throws -> MovieCatalog.Object {
        guard let json = try await request(url, fresh: fresh) as? MovieCatalog.Object else { throw MovieSourceError.invalidData }
        return json
    }

    private func request(_ url: URL, fresh: Bool = false) async throws -> Any {
        guard let config = configuration else { throw MovieSourceError.invalidData }
        let coreRequest = config.core.map { url.host == $0.baseURL.host && url.path.hasPrefix("/" + Phim4KCatalog.prefix) } ?? false
        let freeRequest = config.catalogs.contains { url.host == $0.url.host && url.scheme == $0.url.scheme }
        guard coreRequest || freeRequest else { throw MovieSourceError.unavailable("Đường dẫn không thuộc app Phim4K.") }
        if !fresh, let (date, json) = cache[url], Date().timeIntervalSince(date) < 120 { return json }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        if coreRequest { req.setValue(config.core?.apiKey, forHTTPHeaderField: "API-KEY") }
        let (data, response) = try await session.data(for: req)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MovieSourceError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let json = try JSONSerialization.jsonObject(with: data)
        guard json is MovieCatalog.Object || json is [MovieCatalog.Object] else { throw MovieSourceError.invalidData }
        if cache.count >= 80 { cache.removeAll() }
        cache[url] = (Date(), json)
        return json
    }

    private func labelled(_ items: [Anime], _ label: String) -> [Anime] {
        items.map { var item = $0; item.catalogLabel = label; return item }
    }
}
