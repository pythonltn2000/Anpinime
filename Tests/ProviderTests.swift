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
    static var directoryEnvelope = Data()
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
        let directoryEnvelope = Self.directoryEnvelope
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
        if host == "vip.example", request.httpMethod == "GET" {
            let body = mediaGetType.contains("json") ? Data("{\"error\":true}".utf8) : Data([0,0,0,24,0x66,0x74,0x79,0x70,0x69,0x73,0x6f,0x6d])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: mediaGetStatus, httpVersion: nil, headerFields: ["Content-Type": mediaGetType, "Content-Range": "bytes 0-11/12285989889"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if host == "vip.example", request.httpMethod == "HEAD" {
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
                body = ["videos_id": "41", "title": "Core movie 4K", "videos": [
                    ["video_file_id": "a", "label": "VIP 2160P REMUX", "file_type": "mkv", "file_url": "https://vip.example/original.mkv"],
                    ["video_file_id": "b", "label": "1080P", "file_type": "mp4", "file_url": "https://vip.example/original.mp4"]]]
            default: body = [movie]
            }
        } else if host == "free1.example", path.hasPrefix("/phim/") {
            body = ["movie": ["name": "Free1 original"], "episodes": [["server_name": "Vietsub", "server_data": [
                ["name": "Tập 01", "slug": "tap-01", "link": "https://stream.example/api/content/stream/hls?movie=shared-slug&server=Vietsub&slug=tap-01"]]]]]
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
    }
    static func captured() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderProtocol.self]
        let session = URLSession(configuration: config)
        try await verifyDirectoryMetadata(session: session)
        let source2 = Phim4KProvider.Configuration(core: .init(baseURL: URL(string: "https://core.example")!, apiKey: "fixture-key"), catalogs: [
            .init(id: "free1", url: URL(string: "https://free1.example")!, format: .free1),
            .init(id: "free2", url: URL(string: "https://free2.example")!, format: .free2)
        ])
        let overridden = try Phim4KProvider.applyingCatalogOverride("https://custom-free.example", format: .free1, to: source2)
        require(overridden.core?.baseURL == source2.core?.baseURL && overridden.catalogs.map(\.id) == ["free1", "free2"], "Manual Free override preserves Core and both original catalog identities")
        require(overridden.catalogs[0].url.host == "custom-free.example" && overridden.catalogs[1].url.host == "free2.example", "Manual Free override replaces only its selected catalog")
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
        let freeDetail = try await app.detail(search[1])
        let freePlayback = try await app.resolve(freeDetail.episodes[0])
        require(!freePlayback.isWeb && freePlayback.url.host == "stream.example" && freePlayback.url.path == "/api/content/stream/hls", "Free1 uses its actual app HLS endpoint rather than an embed")
        require(URLComponents(url: freePlayback.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "slug" })?.value == "tap-01", "Free1 preserves the selected server and episode query")
        require(freePlayback.headers["Origin"] == "https://free1.example" && freePlayback.headers["API-KEY"] == nil, "Free playback keeps its catalog origin without leaking Core credentials")
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
        print("All provider routing regressions passed")
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS: " + message)
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
