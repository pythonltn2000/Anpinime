import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Runs the production providers through URLSession, so a correctly labelled model
// cannot hide a request sent to the wrong upstream.
final class ProviderProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var failingHost: String?
    static var mediaStatus = 200
    static var mediaType = "video/x-matroska"
    static var mediaGetStatus = 206
    static var mediaGetType = "video/mp4"
    static var mediaGetPrefix = Data([0,0,0,24,0x66,0x74,0x79,0x70,0x69,0x73,0x6f,0x6d])
    static var directoryEnvelope = Data()
    static var coreVideoRows: [[String: Any]]?
    static var gatewayStatus = 200
    static var gatewayType = "application/json"
    static var gatewayBody = Data(#"{"url":"https://vip.example/resolved.mkv?token=media-fixture"}"#.utf8)
    static var gatewayFailure: URLError?
    static var freeMediaURL: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let failing = Self.failingHost
        let mediaStatus = Self.mediaStatus
        let mediaType = Self.mediaType
        let mediaGetStatus = Self.mediaGetStatus
        let mediaGetType = Self.mediaGetType
        let mediaGetPrefix = Self.mediaGetPrefix
        let directoryEnvelope = Self.directoryEnvelope
        let coreVideoRows = Self.coreVideoRows
        let gatewayStatus = Self.gatewayStatus, gatewayType = Self.gatewayType, gatewayBody = Self.gatewayBody
        let gatewayFailure = Self.gatewayFailure
        let freeMediaURL = Self.freeMediaURL
        Self.lock.unlock()
        let url = request.url!, host = url.host!, path = url.path
        var status = 200
        var body: Any
        var html: String?
        if host == "rip.cryboiz.workers.dev", path == "/api/add" {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: directoryEnvelope)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if ["gateway.example", "gateway-new.example"].contains(host) {
            if let gatewayFailure { client?.urlProtocol(self, didFailWithError: gatewayFailure); return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: gatewayStatus, httpVersion: nil, headerFields: ["Content-Type": gatewayType])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: gatewayBody)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if ["vip.example", "media-new.example"].contains(host), request.httpMethod == "GET" {
            let body = mediaGetType.contains("json") ? Data("{\"error\":true}".utf8) : mediaGetPrefix
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: mediaGetStatus, httpVersion: nil, headerFields: ["Content-Type": mediaGetType, "Content-Range": "bytes 0-11/12285989889"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if ["vip.example", "media-new.example"].contains(host), request.httpMethod == "HEAD" {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: mediaStatus, httpVersion: nil, headerFields: ["Content-Type": mediaType])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if host == failing { status = 503; body = ["error": "Unavailable"] }
        else if host == "kkphim.com" {
            html = try! String(contentsOfFile: "Tests/Fixtures/kkphim-ongoing.html", encoding: .utf8)
            body = [:]
        } else if path == "/the-loai" || path == "/quoc-gia" {
            body = ["items": [["slug": "own-taxonomy", "name": "Own category"]]]
        } else if host == "core.example" {
            let movie: [String: Any] = ["videos_id": "41", "title": "Core movie 4K", "is_tvseries": "0"]
            switch path {
            case "/rest-api/v130/home_content_for_android":
                body = ["latest_movies": [movie], "all_genre": [["genre_id": "45", "name": "Hot"]]]
            case "/rest-api/v130/search": body = ["movie": [movie], "tvseries": []]
            case "/rest-api/v130/single_details":
                body = ["videos_id": "41", "title": "Core movie 4K", "videos": coreVideoRows ?? [
                    ["video_file_id": "a", "label": "VIP 2160P REMUX", "file_type": "mkv", "file_url": "https://vip.example/original.mkv"],
                    ["video_file_id": "b", "label": "1080P", "file_type": "mp4", "file_url": "https://vip.example/original.mp4"]]]
            default: body = [movie]
            }
        } else if host == "free1.example", path.hasPrefix("/phim/") {
            body = ["movie": ["name": "Free1 original"], "episodes": [["server_name": "Vietsub", "server_data": [
                ["name": "Tập 01", "slug": "tap-01", "link": freeMediaURL ?? "https://stream.example/api/content/stream/hls?movie=shared-slug&server=Vietsub&slug=tap-01"]]]]]
        } else if path.hasPrefix("/phim/") || path.hasPrefix("/api/film/") {
            let rows: [[String: Any]] = [["name": "01", "slug": "tap-1", "link_m3u8": "https://" + host + "/movie.m3u8", "link_embed": "https://" + host + "/advertising-player"]]
            body = ["movie": ["name": host], "episodes": [["server_name": "Vietsub", "server_data": rows]]]
        } else {
            body = ["items": [["slug": "shared-slug", "name": host]]]
        }
        let data = html.map { Data($0.utf8) } ?? (try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    static func reset(failing: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        requests = []; failingHost = failing; mediaStatus = 200; mediaType = "video/x-matroska"; mediaGetStatus = 206; mediaGetType = "video/mp4"
        mediaGetPrefix = Data([0,0,0,24,0x66,0x74,0x79,0x70,0x69,0x73,0x6f,0x6d])
        coreVideoRows = nil; gatewayStatus = 200; gatewayType = "application/json"
        gatewayBody = Data(#"{"url":"https://vip.example/resolved.mkv?token=media-fixture"}"#.utf8)
        gatewayFailure = nil
        freeMediaURL = nil
    }
    static func captured() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    static func setCoreVideos(_ rows: [[String: Any]]) {
        lock.lock(); defer { lock.unlock() }
        coreVideoRows = rows
    }

    static func setFreeMediaURL(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        freeMediaURL = url
    }

    static func setGateway(status: Int = 200, type: String = "application/json", body: String,
                           failure: URLError? = nil) {
        lock.lock(); defer { lock.unlock() }
        gatewayStatus = status; gatewayType = type; gatewayBody = Data(body.utf8); gatewayFailure = failure
    }

    static func setDirectory(_ config: [String: Any], tampered: Bool = false) throws {
        // Public client configuration envelope, independent of account or CDN
        // signing credentials. Exercise production authenticated decoding.
        let key = SymmetricKey(data: Data([206, 51, 195, 123, 77, 239, 26, 201, 30, 27, 136, 218, 57, 173, 133, 211,
                                          137, 62, 112, 164, 243, 123, 157, 247, 17, 203, 108, 161, 208, 77, 197, 2]))
        let nonceData = Data(repeating: 7, count: 12)
        let plaintext = try JSONSerialization.data(withJSONObject: ["data": config])
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceData))
        var encrypted = box.ciphertext + box.tag
        if tampered { encrypted[encrypted.count - 1] ^= 1 }
        func encoded(_ value: Data) -> String {
            value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let data = try JSONSerialization.data(withJSONObject: ["alg": "AES-GCM-256", "encoding": "base64url",
                                                               "iv": encoded(nonceData), "ciphertext": encoded(encrypted)])
        lock.lock(); defer { lock.unlock() }
        directoryEnvelope = data
    }
}

@MainActor
enum AnimeService { static let userAgent = "AnPinime Provider Tests" }

@main
struct ProviderTests {
    @MainActor static func main() async throws {
        try await verifyTransportPolicy()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderProtocol.self]
        let session = URLSession(configuration: config)
        try await verifyDirectoryMetadata(session: session)
        let source2 = Phim4KProvider.Configuration(core: .init(baseURL: URL(string: "https://core.example")!, apiKey: "fixture-key"), catalogs: [
            .init(id: "free1", url: URL(string: "https://free1.example")!, format: .free1),
            .init(id: "free2", url: URL(string: "https://free2.example")!, format: .free2)
        ], gateway: URL(string: "https://gateway.example")!)
        let overridden = try Phim4KProvider.applyingCatalogOverride("https://custom-free.example", format: .free1, to: source2)
        require(overridden.core?.baseURL == source2.core?.baseURL && overridden.catalogs.map(\.id) == ["free1", "free2"], "Manual Free override preserves Core and both original catalog identities")
        require(overridden.catalogs[0].url.host == "custom-free.example" && overridden.catalogs[1].url.host == "free2.example", "Manual Free override replaces only its selected catalog")
        require(overridden.gateway == source2.gateway, "Manual Free override preserves the independent premium gateway configuration")
        let restoredAutomatic = try Phim4KProvider.applyingCatalogOverride("", format: .free1, to: source2)
        require(restoredAutomatic.catalogs[0].url.host == "free1.example", "Clearing the manual URL restores the original-app Free configuration")
        do { _ = try Phim4KProvider.applyingCatalogOverride("https://custom-free.example/?token=x", format: .free1, to: source2); fatalError("Expected signed override rejection") } catch {}
        do { _ = try Phim4KProvider.applyingCatalogOverride("https://animevietsub.news", format: .free1, to: source2); fatalError("Expected anime host rejection") } catch {}
        for (source, host, category) in [(ContentSource.film4k, "phim.nguonc.com", "api/films/the-loai/hanh-dong"),
                                         (.kkphim, "phimapi.com", "v1/api/the-loai/hanh-dong")] {
            ProviderProtocol.reset()
            let provider = MovieProvider(source: source, session: session)
            let sections = try await provider.home()
            let search = try await provider.search("Tên phim & dấu tiếng Việt")
            let list = try await provider.list(path: category, page: 2)
            let detail = try await provider.detail(search[0])
            let playback = try await provider.resolve(detail.episodes[0])
            require(sections.flatMap(\.items).allSatisfy { $0.source == source } && list.allSatisfy { $0.source == source }, "Catalog identity follows " + source.rawValue)
            require(Set(ProviderProtocol.captured().compactMap { $0.url?.host }) == [host], "Home/search/category/detail/playback only request " + host)
            require(playback.url.host == host && playback.url.path == "/movie.m3u8" && playback.webURL == nil, "Native content never falls back to an advertising page")
            let searchRequest = ProviderProtocol.captured().first { $0.url!.path.contains("search") || $0.url!.path.contains("tim-kiem") }!
            require(URLComponents(url: searchRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "keyword" })?.value == "Tên phim & dấu tiếng Việt", "Search keyword remains intact")
            if source == .kkphim {
                require(provider.categories.contains { $0.path == "v1/api/the-loai/own-taxonomy" }, "KKPhim refreshes its taxonomy from its own API")
                ProviderProtocol.reset()
                let ongoing = try await provider.list(path: "site/danh-sach/phim-bo-dang-chieu", page: 2)
                require(ongoing.count == 2 && ongoing.allSatisfy { $0.source == .kkphim && $0.url.host == "phimapi.com" }, "KKPhim website-only lists retain provider identity")
                let website = ProviderProtocol.captured().first!.url!
                require(website.host == "kkphim.com" && website.path == "/danh-sach/phim-bo-dang-chieu" && website.query == "page=2", "Ongoing list paginates on KKPhim's actual website route")
                _ = try await provider.detail(ongoing[0])
                require(ProviderProtocol.captured().last!.url!.host == "phimapi.com", "Website results open details through the same provider's API")
            }
            ProviderProtocol.reset(failing: host)
            provider.invalidate()
            do { _ = try await provider.search("fail"); fatalError("Expected source failure") } catch {}
            require(Set(ProviderProtocol.captured().compactMap { $0.url?.host }) == [host], "Failure never switches providers")
        }
        ProviderProtocol.reset()
        let app = MovieProvider(source: .phim4k, session: session, source2Configuration: source2)
        let home = try await app.home()
        require(home.first?.title == "Phim lẻ mới nhất", "Source 2 starts with Phim4K Core, not Free1/KKPhim")
        require(home.map(\.title).contains("Phim4K · Free1") && home.map(\.title).contains("Phim4K · Free2"), "All catalogs announced by the app remain separately available")
        let search = try await app.search("Avatar")
        require(search.map(\.catalogLabel) == ["Phim4K · VIP/Premium", "Phim4K · Free1", "Phim4K · Free2"], "Search preserves the app's three catalog identities")
        _ = try await app.list(path: "core/genre/45", page: 2)
        _ = try await app.list(path: "free1/v1/api/the-loai/hanh-dong")
        _ = try await app.list(path: "free2/api/films/the-loai/hanh-dong")
        let detail = try await app.detail(search[0])
        require(detail.episodes.count == 2, "Source 2 restores both original Core servers")
        let playback = try await app.resolve(detail.episodes[0])
        require(playback.url.absoluteString == "https://vip.example/original.mkv", "VIP selection retains the exact Core link")
        let captured = ProviderProtocol.captured()
        require(Set(captured.compactMap { $0.url?.host }) == ["core.example", "free1.example", "free2.example", "vip.example"], "Source 2 never directly queries NguonC or KKPhim")
        require(captured.filter { $0.url?.host != "core.example" }.allSatisfy { $0.value(forHTTPHeaderField: "API-KEY") == nil }, "Core API credentials stay on the Core host")
        require(captured.filter { $0.url?.host == "core.example" }.allSatisfy { $0.value(forHTTPHeaderField: "API-KEY") == "fixture-key" }, "Core app requests retain the required API header")
        require(captured.filter { ["core.example", "free1.example", "free2.example"].contains($0.url?.host ?? "") }.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == "Dart/3.12 (dart:io)"
        }, "Source-2 catalogs use the original Dart client user agent, independently of native media")
        let freeDetail = try await app.detail(search[1])
        let freePlayback = try await app.resolve(freeDetail.episodes[0])
        require(!freePlayback.isWeb && freePlayback.url.host == "stream.example" && freePlayback.url.path == "/api/content/stream/hls", "Free1 uses its actual app HLS endpoint rather than an embed")
        require(URLComponents(url: freePlayback.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "slug" })?.value == "tap-01", "Free1 preserves the selected server and episode query")
        require(freePlayback.headers["User-Agent"] == "oxoo" && ["Origin", "Referer", "API-KEY", "Authorization", "Cookie"].allSatisfy { freePlayback.headers[$0] == nil }, "Free playback follows the original app's media headers without Core or website credentials")
        ProviderProtocol.lock.lock(); ProviderProtocol.mediaStatus = 403; ProviderProtocol.mediaGetStatus = 403; ProviderProtocol.lock.unlock()
        do { _ = try await app.resolve(detail.episodes[0]); fatalError("Expected auth error") }
        catch { require(error.localizedDescription.contains("AUTH_REQUIRED"), "VIP 403 surfaces AUTH_REQUIRED without fallback") }
        ProviderProtocol.lock.lock(); ProviderProtocol.mediaStatus = 200; ProviderProtocol.mediaType = "application/json"; ProviderProtocol.mediaGetStatus = 200; ProviderProtocol.mediaGetType = "application/json"; ProviderProtocol.lock.unlock()
        do { _ = try await app.resolve(detail.episodes[0]); fatalError("Expected invalid media response") }
        catch { require(error.localizedDescription.contains("JSON"), "JSON response is not handed to the video decoder") }
        ProviderProtocol.reset()
        ProviderProtocol.lock.lock(); ProviderProtocol.mediaStatus = 405; ProviderProtocol.lock.unlock()
        let ranged = try await app.resolve(detail.episodes[0])
        require(ranged.url.absoluteString == "https://vip.example/original.mkv", "HEAD 405 falls back to the same media URL")
        let probe = ProviderProtocol.captured().last { $0.httpMethod == "GET" && $0.url?.host == "vip.example" }
        require(probe?.value(forHTTPHeaderField: "Range") == "bytes=0-2047", "GET probe sends a bounded range")
        ProviderProtocol.reset()
        do { _ = try await app.list(path: "v1/api/the-loai/hanh-dong"); fatalError("Expected foreign category rejection") } catch {}
        let wrongProvider = MovieProvider(source: .kkphim, session: session)
        do { _ = try await wrongProvider.detail(search[0]); fatalError("Expected identity rejection") } catch {}
        try await verifyGatewayIntegration(session: session)
        print("All provider routing regressions passed")
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS: " + message)
    }

    @MainActor static func verifyGatewayIntegration(session: URLSession) async throws {
        let core = URL(string: "https://core.example")!
        let movie = Anime(title: "Selected premium movie", url: URL(string: "https://core.example/rest-api/v130/single_details?type=movie&id=41")!,
                          imageURL: nil, episodeText: "", quality: "", score: "", source: .phim4k)
        let configuration = Phim4KProvider.Configuration(core: .init(baseURL: core, apiKey: "fixture-key"), catalogs: [
            .init(id: "free1", url: URL(string: "https://free1.example")!, format: .free1)
        ], gateway: URL(string: "https://gateway.example")!)
        let provider = MovieProvider(source: .phim4k, session: session, source2Configuration: configuration)
        let ids = ["31937", "33090", "27463", "31938", "31939"]
        let rows: [[String: Any]] = ids.enumerated().map { index, id in
            ["video_file_id": id, "label": "Original premium server " + id, "file_type": "mkv",
             "file_url": "https://cdn.phim4k.lol/OPAQUE_" + String(index)]
        }
        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(rows)
        let detail = try await provider.detail(movie)
        func serverID(_ episode: Episode) -> String? {
            if case .phim4kCore(_, _, let id) = episode.playback { return id }
            return nil
        }
        require(detail.episodes.compactMap(serverID) == ids, "Gateway integration retains every exact Wakanda-style server ID without quality-based deduplication")
        let selected = detail.episodes.first { serverID($0) == "31937" }!
        var refreshed = Array(rows.reversed())
        let index = refreshed.firstIndex { $0["video_file_id"] as? String == "31937" }!
        refreshed[index]["file_url"] = "https://cdn.phim4k.lol/REFRESHED_HANDLE"
        ProviderProtocol.setCoreVideos(refreshed)
        ProviderProtocol.lock.lock(); ProviderProtocol.mediaStatus = 405; ProviderProtocol.lock.unlock()
        let resolved = try await provider.resolve(selected)
        let requests = ProviderProtocol.captured()
        let gateway = requests.first { $0.url?.host == "gateway.example" }!
        let query = URLComponents(url: gateway.url!, resolvingAgainstBaseURL: false)!.queryItems!
        require(gateway.url?.lastPathComponent == "REFRESHED_HANDLE" && Set(query.map(\.name)) == ["token", "ts"], "Fresh exact server ID determines the gateway file handle after API reordering and URL refresh")
        require(query.first { $0.name == "token" }?.value?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
                && query.first { $0.name == "ts" }?.value?.range(of: "^[0-9a-f]{8}$", options: .regularExpression) != nil,
                "Gateway request has the original protocol's token and masked timestamp shapes")
        require(gateway.httpMethod == "GET" && gateway.value(forHTTPHeaderField: "Range") == nil, "Gateway exchange is a bounded JSON GET, separate from media Range probing")
        require(resolved.url.absoluteString == "https://vip.example/resolved.mkv?token=media-fixture", "Gateway JSON media URL and its source-supplied query are used exactly")
        let media = requests.filter { $0.url?.host == "vip.example" }
        require(media.map(\.httpMethod) == ["HEAD", "GET"] && media.allSatisfy { $0.url == resolved.url }, "HEAD rejection triggers a bounded GET on the resolved media URL, not the virtual CDN or gateway")
        require(media.last?.value(forHTTPHeaderField: "Range") == "bytes=0-2047", "Resolved premium media probe stays bounded")
        require(requests.filter { $0.url?.host != "core.example" }.allSatisfy { request in
            ["API-KEY", "Authorization", "Cookie", "Referer", "Origin"].allSatisfy { request.value(forHTTPHeaderField: $0) == nil }
        }, "Neither gateway nor premium media requests receive Core, account or website headers")
        require(resolved.headers["User-Agent"] == "oxoo" && media.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "oxoo" }, "Premium media uses the original app's oxoo user agent")
        require(!requests.contains { $0.url?.host == "cdn.phim4k.lol" || $0.url?.host == "free1.example" }, "Premium resolution never probes the obsolete virtual host or substitutes Free1")

        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(refreshed)
        ProviderProtocol.setGateway(body: #"{"url":"https://media-new.example/new.mkv?token=next-fixture"}"#)
        let movedMedia = try await provider.resolve(selected)
        require(movedMedia.url.host == "media-new.example" && ProviderProtocol.captured().contains { $0.url?.host == "media-new.example" }, "A fresh gateway response can move the exact selected stream to a new media host")

        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(rows)
        ProviderProtocol.setGateway(body: #"{"url":"http://vip.example/original-http.model?token=http-fixture"}"#)
        ProviderProtocol.lock.lock()
        ProviderProtocol.mediaStatus = 405
        ProviderProtocol.mediaGetPrefix = Data([0x1a, 0x45, 0xdf, 0xa3, 0, 0, 0, 0])
        ProviderProtocol.lock.unlock()
        let originalHTTP = try await provider.resolve(selected)
        let httpMedia = ProviderProtocol.captured().filter { $0.url?.host == "vip.example" }
        require(originalHTTP.url.absoluteString == "http://vip.example/original-http.model?token=http-fixture"
                && httpMedia.map(\.httpMethod) == ["HEAD", "GET"], "A genuine HTTP media URL returned by the HTTPS gateway is preserved without a guessed HTTPS rewrite")
        require(httpMedia.allSatisfy { request in request.url?.scheme == "http"
            && request.value(forHTTPHeaderField: "User-Agent") == "oxoo"
            && ["API-KEY", "Authorization", "Cookie", "Origin", "Referer"].allSatisfy { request.value(forHTTPHeaderField: $0) == nil }
        }, "HTTP premium media receives only the original app media headers, never API or session credentials")

        var movedConfiguration = configuration
        movedConfiguration.gateway = URL(string: "https://gateway-new.example")!
        let movedProvider = MovieProvider(source: .phim4k, session: session, source2Configuration: movedConfiguration)
        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(refreshed)
        _ = try await movedProvider.resolve(selected)
        require(ProviderProtocol.captured().contains { $0.url?.host == "gateway-new.example" }
                && !ProviderProtocol.captured().contains { $0.url?.host == "gateway.example" }, "An updated gateway configuration replaces the old host without changing the selected server")

        let rejected: [(Int, String, String)] = [
            (400, "application/json", #"{"error":"bad request"}"#),
            (401, "application/json", #"{"error":"unauthorized"}"#),
            (403, "application/json", #"{"error":"forbidden"}"#),
            (500, "application/json", #"{"url":"https://vip.example/never.mkv"}"#),
            (200, "text/html", "<!doctype html><html>Gateway unavailable</html>"),
            (200, "application/json", #"{"status":true}"#),
            (200, "application/json", #"{"url":null}"#),
            (200, "application/json", #"{"url":""}"#),
            (200, "application/json", #"{"url":"/relative.mkv"}"#),
            (200, "application/json", #"{"url":"javascript:alert(1)"}"#),
            (200, "application/json", #"{"url":"file:///movie.mkv"}"#),
            (200, "application/json", #"{"url":"http://127.0.0.1/movie.mkv"}"#),
            (200, "application/json", #"{"url":"https://user:password@vip.example/movie.mkv"}"#),
            (200, "application/json", #"{"url":"https://vip.example/never.mkv"}"# + String(repeating: " ", count: 70_000))
        ]
        for (status, type, body) in rejected {
            ProviderProtocol.reset()
            ProviderProtocol.setCoreVideos(rows)
            ProviderProtocol.setGateway(status: status, type: type, body: body)
            do { _ = try await provider.resolve(selected); fatalError("Expected gateway failure") } catch {}
            require(ProviderProtocol.captured().contains { $0.url?.host == "gateway.example" }
                    && ProviderProtocol.captured().allSatisfy { ["core.example", "gateway.example"].contains($0.url?.host ?? "") },
                    "Rejected gateway status or payload fails before any media, obsolete CDN or Free request")
            require(ProviderProtocol.captured().filter { $0.url?.host == "gateway.example" }.allSatisfy { $0.httpMethod == "GET" },
                    "A failed gateway exchange is never handed back as a media URL for HEAD probing")
        }
        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(rows)
        ProviderProtocol.setGateway(body: "", failure: URLError(.timedOut))
        do { _ = try await provider.resolve(selected); fatalError("Expected gateway timeout") } catch {}
        require(ProviderProtocol.captured().allSatisfy { ["core.example", "gateway.example"].contains($0.url?.host ?? "") }, "Gateway network failure cannot become a signed gateway URL handed to the player")
        require(ProviderProtocol.captured().filter { $0.url?.host == "gateway.example" }.allSatisfy { $0.httpMethod == "GET" }, "Gateway timeout remains a resolver failure and is not probed as video")

        ProviderProtocol.reset()
        ProviderProtocol.setCoreVideos(rows.filter { $0["video_file_id"] as? String != "31937" })
        do { _ = try await provider.resolve(selected); fatalError("Expected missing selected server") } catch {}
        require(ProviderProtocol.captured().allSatisfy { $0.url?.host == "core.example" }, "A removed selected ID never resolves another server or another provider")
        for invalid in ["http://core.example/rest-api/v130/single_details?type=movie&id=41", "https://core.example:8443/rest-api/v130/single_details?type=movie&id=41", "https://core.example.attacker.test/rest-api/v130/single_details?type=movie&id=41"] {
            ProviderProtocol.reset()
            let wrong = Anime(title: movie.title, url: URL(string: invalid)!, imageURL: nil, episodeText: "", quality: "", score: "", source: .phim4k)
            do { _ = try await provider.detail(wrong); fatalError("Expected wrong Core origin rejection") } catch {}
            require(ProviderProtocol.captured().isEmpty, "Wrong Core scheme, port or lookalike host is rejected before sending credentials")
        }

        // A Free catalog marks its source before any host-based VIP routing.
        // Even a virtual-host-shaped link stays Free and is never signed.
        ProviderProtocol.reset()
        let free = Anime(title: "Free sample", url: URL(string: "https://free1.example/phim/sample")!, imageURL: nil,
                         episodeText: "", quality: "", score: "", source: .phim4k, catalogLabel: "Phim4K · Free1")
        ProviderProtocol.setFreeMediaURL("https://cdn.phim4k.lol/FREE_SOURCE_HANDLE.mkv")
        let freeDetail = try await provider.detail(free)
        let freePlayback = try await provider.resolve(freeDetail.episodes[0])
        require(!freePlayback.isWeb && freePlayback.url.absoluteString == "https://cdn.phim4k.lol/FREE_SOURCE_HANDLE.mkv"
                && ProviderProtocol.captured().allSatisfy { $0.url?.host == "free1.example" }, "Free-source context bypasses signing even for a virtual-CDN-shaped URL")
        require(freePlayback.headers["User-Agent"] == "oxoo" && ["API-KEY", "Authorization", "Cookie", "Referer", "Origin"].allSatisfy { freePlayback.headers[$0] == nil }, "Free media uses the original app's user agent without website or premium headers")
        ProviderProtocol.setFreeMediaURL("https://embed.example/watch/opaque")
        let webPlayback = try await provider.resolve(freeDetail.episodes[0])
        require(webPlayback.isWeb && webPlayback.webURL == nil && webPlayback.url.host == "embed.example",
                "A link-only opaque Free embed retains web-backed playback without an optional embed URL")
        require(webPlayback.headers["User-Agent"] == AnimeService.userAgent && webPlayback.headers["Referer"] == "https://free1.example/",
                "Web-backed Free playback retains website headers for its WebKit-to-native handoff")
        ProviderProtocol.reset()
    }

    @MainActor static func verifyTransportPolicy() async throws {
        let core = URL(string: "https://core.example")!
        require(Phim4KTransportPolicy.sameOrigin(core, URL(string: "https://CORE.example:443/rest-api/v130/movies")!), "Core origin compares case-insensitive host and effective HTTPS port")
        for changed in ["http://core.example", "https://core.example:8443", "https://core.example.attacker.test", "https://other.example", "https://user:password@core.example"] {
            let url = URL(string: changed)!
            require(!Phim4KTransportPolicy.permitsCoreRequest(url, baseURL: core), "Core credentials cannot follow a changed scheme, port, host or userinfo")
        }
        let loopback = URL(string: "http://127.0.0.1:8765")!
        require(!Phim4KTransportPolicy.permitsEndpoint(loopback) && Phim4KTransportPolicy.permitsEndpoint(loopback, allowLoopbackHTTP: true), "HTTP loopback requires an explicit fixture opt-in")
        require(!Phim4KTransportPolicy.permitsEndpoint(URL(string: "http://core.example")!, allowLoopbackHTTP: true), "Fixture opt-in never permits public HTTP endpoints")
        let originalHTTPMedia = URL(string: "http://media.example/movie.model?token=fixture")!
        require(Phim4KTransportPolicy.permitsMediaEndpoint(originalHTTPMedia) && !Phim4KTransportPolicy.permitsEndpoint(originalHTTPMedia), "An original HTTP media URL is allowed only by media policy, never Core or gateway policy")
        require(!Phim4KTransportPolicy.permitsMediaEndpoint(loopback)
                && Phim4KTransportPolicy.permitsMediaEndpoint(loopback, allowLoopbackHTTP: true), "HTTP media loopback still requires an explicit local fixture")
        require(!Phim4KTransportPolicy.permitsEndpoint(URL(string: "file:///movie.mkv")!), "Non-HTTP media/gateway schemes are rejected")
        var signedMedia = URLRequest(url: URL(string: "https://media.example:8443/movie.mkv?token=fixture")!)
        signedMedia.setValue("fixture-key", forHTTPHeaderField: "API-KEY")
        signedMedia.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        signedMedia.setValue("account=fixture", forHTTPHeaderField: "Cookie")
        signedMedia.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        signedMedia.setValue("fixture-agent", forHTTPHeaderField: "User-Agent")
        let changedPort = Phim4KTransportPolicy.redirectedRequest(signedMedia, from: URL(string: "https://media.example/movie.mkv")!)!
        require(changedPort.value(forHTTPHeaderField: "API-KEY") == nil && changedPort.value(forHTTPHeaderField: "Authorization") == nil && changedPort.value(forHTTPHeaderField: "Cookie") == nil,
                "A same-host port change is cross-origin and removes sensitive headers")
        require(changedPort.value(forHTTPHeaderField: "Range") == "bytes=0-2047" && changedPort.value(forHTTPHeaderField: "User-Agent") == "fixture-agent", "Cross-origin media redirects preserve only required non-sensitive media headers")
        require(!changedPort.httpShouldHandleCookies && changedPort.url == signedMedia.url, "A redirect cannot reattach session cookies or rewrite the server-supplied signed URL")
        var downgrade = signedMedia
        downgrade.url = loopback
        require(Phim4KTransportPolicy.redirectedRequest(downgrade, from: core, allowLoopbackHTTP: true, allowRemoteHTTP: true) == nil, "HTTPS downgrade is rejected even when HTTP media and loopback fixtures are enabled")
        let upgrade = Phim4KTransportPolicy.redirectedRequest(signedMedia, from: originalHTTPMedia, allowRemoteHTTP: true)
        require(upgrade?.url == signedMedia.url && upgrade?.value(forHTTPHeaderField: "API-KEY") == nil
                && upgrade?.value(forHTTPHeaderField: "Range") == "bytes=0-2047", "An HTTP-to-HTTPS media redirect is allowed while sensitive headers are stripped")

        // Exercise URLSession's real redirect delegate with two local origins.
        // URLProtocol fixtures alone cannot prove redirected header behavior.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", "-c", #"""
import json, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path == '/cross': destination = 'http://127.0.0.1:'+str(second.server_port)+'/headers'
        elif self.path == '/same': destination = '/headers'
        elif self.path.startswith('/loop/'):
            destination = '/loop/'+str(int(self.path.rsplit('/',1)[1])+1)
        else: destination = None
        values = {k:self.headers.get(k) for k in ['API-KEY','Authorization','Cookie','Range','User-Agent']}
        values['fixturePath'] = self.path
        body = json.dumps(values).encode()
        self.send_response(302 if destination else 200)
        if destination: self.send_header('Location',destination)
        self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
first = ThreadingHTTPServer(('127.0.0.1',0),Handler)
second = ThreadingHTTPServer(('127.0.0.1',0),Handler)
for server in [first,second]: threading.Thread(target=server.serve_forever,daemon=True).start()
print(json.dumps([first.server_port,second.server_port]),flush=True)
threading.Event().wait()
"""#]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        var line = Data()
        while line.count < 128 {
            guard let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else { throw URLError(.cannotConnectToHost) }
            if byte == Data([10]) { break }
            line.append(byte)
        }
        let ports = try JSONSerialization.jsonObject(with: line) as! [Int]
        let root = URL(string: "http://127.0.0.1:\(ports[0])")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let mediaSession = URLSession(configuration: configuration, delegate: Phim4KRedirectPolicy(mode: .media, allowLoopbackHTTP: true, maxRedirects: 2), delegateQueue: nil)
        let coreSession = URLSession(configuration: configuration, delegate: Phim4KRedirectPolicy(mode: .sameOriginOnly, allowLoopbackHTTP: true, maxRedirects: 2), delegateQueue: nil)
        defer { mediaSession.invalidateAndCancel(); coreSession.invalidateAndCancel() }
        var cross = URLRequest(url: root.appendingPathComponent("cross"), timeoutInterval: 5)
        for (name, value) in ["API-KEY": "fixture-key", "Authorization": "Bearer fixture", "Cookie": "account=fixture", "Range": "bytes=0-2047", "User-Agent": "fixture-agent"] { cross.setValue(value, forHTTPHeaderField: name) }
        let (body, response) = try await mediaSession.data(for: cross)
        let received = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        require((response as? HTTPURLResponse)?.statusCode == 200 && response.url?.port == ports[1], "Media session follows an allowed cross-origin loopback redirect")
        require(["API-KEY", "Authorization", "Cookie"].allSatisfy { received[$0] is NSNull }, "Actual cross-origin redirect never sends Core/session credentials to the media origin")
        require(received["Range"] as? String == "bytes=0-2047" && received["User-Agent"] as? String == "fixture-agent", "Actual redirected media request keeps Range and User-Agent")
        let (_, rejected) = try await coreSession.data(for: cross)
        require((rejected as? HTTPURLResponse)?.statusCode == 302 && rejected.url?.port == ports[0], "Core-only session refuses cross-origin redirects before sending its API key")
        cross.url = root.appendingPathComponent("same")
        let (sameBody, sameResponse) = try await coreSession.data(for: cross)
        let sameHeaders = try JSONSerialization.jsonObject(with: sameBody) as! [String: Any]
        require((sameResponse as? HTTPURLResponse)?.statusCode == 200 && sameHeaders["API-KEY"] as? String == "fixture-key", "Same-origin Core redirects retain the required client header")
        for iteration in 0..<2 {
            let (boundedBody, bounded) = try await mediaSession.data(from: root.appendingPathComponent("loop/0"))
            let actual = try JSONSerialization.jsonObject(with: boundedBody) as! [String: Any]
            let status = (bounded as? HTTPURLResponse)?.statusCode ?? 0
            let path = bounded.url?.path ?? "missing"
            let serverPath = actual["fixturePath"] as? String ?? "missing"
            require(status == 302 && path == "/loop/2" && serverPath == "/loop/2",
                    "Redirect count is bounded per task and resets for a new request; iteration=\(iteration), status=\(status), responsePath=\(path), serverPath=\(serverPath)")
        }
    }

    @MainActor static func verifyDirectoryMetadata(session: URLSession) async throws {
        let suite = "AnPinime.DirectoryMetadataTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "AnPinime.source2Directory"
        let original = ["api": "https://core.example", "free1": "https://free1.example", "free2": "https://free2.example", "tokens": "fixture-key"]
        defaults.set(original, forKey: key)
        require(MovieSourceDirectory.cdnGateway(defaults: defaults) == nil, "A missing CDN announcement never invents a default gateway")
        ProviderProtocol.reset()
        try ProviderProtocol.setDirectory(["cdn": "announced-cdn.example"])
        await MovieSourceDirectory.refresh(session: session, defaults: defaults)
        require(MovieSourceDirectory.cdnGateway(defaults: defaults)?.absoluteString == "https://announced-cdn.example", "Authenticated directory CDN metadata is normalized to HTTPS")
        var saved = defaults.dictionary(forKey: key) as! [String: String]
        require(original.allSatisfy { saved[$0.key] == $0.value }, "Adding a CDN announcement preserves Core, both Free catalogs and their existing API configuration")
        require(ProviderProtocol.captured().count == 1 && ProviderProtocol.captured().allSatisfy {
            $0.url?.host == "rip.cryboiz.workers.dev" && $0.value(forHTTPHeaderField: "API-KEY") == nil
        }, "Reading announced CDN metadata never requests that CDN or forwards Core credentials")
        try ProviderProtocol.setDirectory(["free1": "new-free.example"])
        await MovieSourceDirectory.refresh(session: session, defaults: defaults)
        saved = defaults.dictionary(forKey: key) as! [String: String]
        require(MovieSourceDirectory.cdnGateway(defaults: defaults)?.host == "announced-cdn.example" && saved["free1"] == "https://new-free.example"
                && saved["api"] == original["api"] && saved["free2"] == original["free2"], "Partial bootstrap updates preserve the last announced CDN and unrelated catalogs")
        for invalid in ["http://insecure.example", "https://cdn.example/?token=fixture", "https://user:password@cdn.example"] {
            try ProviderProtocol.setDirectory(["cdn": invalid])
            await MovieSourceDirectory.refresh(session: session, defaults: defaults)
            require(MovieSourceDirectory.cdnGateway(defaults: defaults)?.host == "announced-cdn.example", "Invalid CDN metadata cannot erase the last valid announcement")
        }
        try ProviderProtocol.setDirectory(["cdn": "unverified-cdn.example"], tampered: true)
        await MovieSourceDirectory.refresh(session: session, defaults: defaults)
        require(MovieSourceDirectory.cdnGateway(defaults: defaults)?.host == "announced-cdn.example", "An unauthenticated directory envelope cannot replace CDN metadata")
        ProviderProtocol.reset()
    }
}
