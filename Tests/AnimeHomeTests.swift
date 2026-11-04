import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The CLI harness uses the actual AnimeService, resolver and on-disk store;
// only unrelated movie/WebKit/UI frameworks are replaced.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
@MainActor final class WebsiteSession {
    private(set) static var initializationCount = 0
    var loadCount = 0
    init() { Self.initializationCount += 1 }
    func load(_ url: URL, waitForEpisodes: Bool = false) async throws -> (String, URL) {
        loadCount += 1
        throw AnimeServiceError.verificationRequired(url)
    }
}
@MainActor final class MovieProvider {
    let baseURL = URL(string: "https://unused.example")!
    let categories: [AnimeCategory] = []
    let notice = ""
    init(source: ContentSource) {}
    func invalidate() {}
    func home(_ partial: @escaping ([AnimeSection]) -> Void) async throws -> [AnimeSection] { [] }
    func list(path: String, page: Int) async throws -> [Anime] { [] }
    func search(_ value: String) async throws -> [Anime] { [] }
    func detail(_ value: Anime) async throws -> AnimeDetail { throw AnimeServiceError.emptyData }
    func resolve(_ value: Episode, refresh: Bool) async throws -> ResolvedPlayback { throw AnimeServiceError.emptyData }
}

final class HomeProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URL] = []
    private static var waiting: [HomeProtocol] = []
    private static var body = ""
    private static var gated = false
    private static var responseURL: URL?
    private static var failureHost: String?
    static func reset(html: String, gated: Bool = false, responseURL: URL? = nil, failureHost: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        requests = []; waiting = []; body = html; self.gated = gated; self.responseURL = responseURL; self.failureHost = failureHost
    }
    static func captured() -> [URL] { lock.lock(); defer { lock.unlock() }; return requests }
    static func release() {
        lock.lock(); let pending = waiting; waiting = []; gated = false; lock.unlock()
        pending.forEach { $0.deliver() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        if let url = request.url { Self.requests.append(url) }
        if request.url?.host == Self.failureHost {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if Self.gated { Self.waiting.append(self); Self.lock.unlock(); return }
        Self.lock.unlock(); deliver()
    }
    private func deliver() {
        Self.lock.lock(); let html = Self.body; let url = Self.responseURL ?? request.url!; Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.lock.lock(); Self.waiting.removeAll { $0 === self }; Self.lock.unlock()
    }
}

@main struct AnimeHomeTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fatalError("FAIL: " + message) }
        print("PASS: " + message)
    }
    static func card(_ title: String) -> String {
        "<section><h2>Mới cập nhật</h2><article class='TPost'><a href='/phim/test-a1/'><img src='/image.jpg' alt='\(title)'></a><h2 class='Title'>\(title)</h2></article></section>"
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "AnPinime.HomeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeProtocol.self]
        let session = URLSession(configuration: configuration)
        let resolver = DomainResolver(defaultsSuiteName: defaultsName)
        let store = AnimeHomeStore(directory: directory)
        HomeProtocol.reset(html: card("First catalog"))
        let first = AnimeService(session: session, resolver: resolver, homeStore: store)
        check(WebsiteSession.initializationCount == 0, "Creating an anime/movie service does not create a verification browser")
        let coldStart = Date()
        await first.loadHome()
        let coldMS = Int(Date().timeIntervalSince(coldStart) * 1000)
        check(first.homeSections.first?.items.first?.title == "First catalog", "Cold Home returns parsed cards")
        check(HomeProtocol.captured().map(\.path) == ["/"], "Cold Home makes one catalog request, with zero shortlink or legacy detail probes")
        check(WebsiteSession.initializationCount == 0, "An ordinary cold Home never instantiates the WebKit verification path")
        check(defaults.string(forKey: "AnyAnime.VerifiedBaseURL.v2")?.contains("animevietsub.news") == true,
              "Only successful parsed Home becomes a verified domain")
        let snapshot = await store.load(configuration: nil)
        check(snapshot?.sections == first.homeSections, "Parsed Home survives a new service instance without HTML or cookies")

        // Hold the fresh request indefinitely. The warm service must publish the
        // disk snapshot before the network is allowed to complete.
        HomeProtocol.reset(html: card("Fresh catalog"), gated: true)
        let second = AnimeService(session: session, resolver: DomainResolver(defaultsSuiteName: defaultsName), homeStore: store)
        let warmStart = Date()
        let refresh = Task { await second.loadHome() }
        let deadline = Date().addingTimeInterval(5)
        while second.homeSections.isEmpty || HomeProtocol.captured().isEmpty {
            guard Date() < deadline else { fatalError("Warm Home waited on the gated network") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let warmMS = Int(Date().timeIntervalSince(warmStart) * 1000)
        check(second.homeSections.first?.items.first?.title == "First catalog" && !second.homeLoading,
              "Warm Home is usable while its refresh response remains gated")
        check(WebsiteSession.initializationCount == 0, "Displaying warm cached cards does not instantiate a verification browser")
        HomeProtocol.release()
        await refresh.value
        check(second.homeSections.first?.items.first?.title == "Fresh catalog", "The real network response replaces the cached cards")
        check(HomeProtocol.captured().count == 1, "Warm refresh also avoids duplicate domain/catalog requests")
        check(WebsiteSession.initializationCount == 0, "Refreshing ordinary warm Home still does not instantiate a verification browser")

        let manual = URL(string: "https://custom.example")!
        check(await store.load(configuration: manual) == nil, "A manual catalog never displays the automatic catalog snapshot")
        let manualStore = AnimeHomeStore(directory: directory.appendingPathComponent("manual"))
        let manualItem = Anime(title: "Manual catalog", url: URL(string: "https://custom.example/phim/test-a1/")!,
                               imageURL: nil, episodeText: "Tập 2", quality: "HD", score: "8")
        await manualStore.save(sections: [.init(title: "Manual", items: [manualItem])],
                               baseURL: URL(string: "https://custom.example/")!, configuration: manual)
        check(await manualStore.load(configuration: manual)?.sections.first?.items.first == manualItem,
              "Manual Home persists despite origin trailing-slash differences")
        let automaticManualSnapshot = await manualStore.load(configuration: nil)
        let otherManualSnapshot = await manualStore.load(configuration: URL(string: "https://different.example")!)
        check(automaticManualSnapshot == nil && otherManualSnapshot == nil,
              "A manual snapshot is isolated from automatic and other manual catalogs")
        check(await store.load(configuration: nil, now: Date().addingTimeInterval(25 * 3600)) == nil,
              "An expired Home snapshot cannot remain visible forever")
        await store.save(sections: second.homeSections, baseURL: second.baseURL, configuration: nil, at: Date().addingTimeInterval(3600))
        check(await store.load(configuration: nil) == nil, "A future-dated snapshot is rejected")
        await store.save(sections: second.homeSections, baseURL: second.baseURL, configuration: nil)
        var movie = second.homeSections[0].items[0]; movie.source = .film4k
        await store.save(sections: [.init(title: "Wrong source", items: [movie])], baseURL: second.baseURL, configuration: nil)
        check(await store.load(configuration: nil)?.sections.first?.title == "Mới cập nhật", "Movie sources cannot overwrite anime Home")

        HomeProtocol.reset(html: "<title>Just a moment...</title><form id='challenge-form'></form>")
        let challengeDirectory = directory.appendingPathComponent("challenge")
        let challengeStore = AnimeHomeStore(directory: challengeDirectory)
        let challengeDefaults = UserDefaults(suiteName: defaultsName + ".challenge")!
        defer { challengeDefaults.removePersistentDomain(forName: defaultsName + ".challenge") }
        let challenge = AnimeService(session: session, resolver: DomainResolver(defaultsSuiteName: defaultsName + ".challenge"), homeStore: challengeStore)
        await challenge.loadHome()
        check(challenge.homeSections.isEmpty && WebsiteSession.initializationCount == 1 && challenge.website.loadCount == 1,
              "A challenged Home lazily creates exactly one browser and uses the existing verification flow")
        let challengeBrowser = challenge.website
        check(challenge.website === challengeBrowser && WebsiteSession.initializationCount == 1,
              "Repeated access preserves the same verification browser instance")
        check(await challengeStore.load(configuration: nil) == nil && challengeDefaults.object(forKey: "AnyAnime.VerifiedBaseURL.v2") == nil,
              "A challenge is never persisted as cards or a verified domain")
        let discoveryName = defaultsName + ".discovery"
        let discoveryDefaults = UserDefaults(suiteName: discoveryName)!
        defer { discoveryDefaults.removePersistentDomain(forName: discoveryName) }
        discoveryDefaults.set("https://animevietsub.old", forKey: "AnyAnime.VerifiedBaseURL.v2")
        discoveryDefaults.set(Date().addingTimeInterval(-7 * 3600), forKey: "AnyAnime.VerifiedBaseURL.updatedAt")
        let recoveryResolver = DomainResolver(defaultsSuiteName: discoveryName, load: { request in
            let host = request.url!.host!
            if host == "bit.ly" {
                return (Data(), HTTPURLResponse(url: URL(string: "https://animevietsub.news/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            guard host == "animevietsub.news" else { throw URLError(.cannotFindHost) }
            return (Data("<h1>Current Anime</h1><a>Xem phim</a>".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        HomeProtocol.reset(html: card("Recovered catalog"), failureHost: "animevietsub.old")
        let recoveryStore = AnimeHomeStore(directory: directory.appendingPathComponent("recovery"))
        let recovery = AnimeService(session: session, resolver: recoveryResolver, homeStore: recoveryStore)
        await recovery.loadHome()
        check(HomeProtocol.captured().map { $0.host! } == ["animevietsub.old", "animevietsub.news"],
              "A dead stale automatic host triggers discovery then one request to the new host")
        check(recovery.baseURL.host == "animevietsub.news" && recovery.homeSections.first?.items.first?.title == "Recovered catalog",
              "Domain recovery publishes the current Home and rebases its cards")
        check(recovery.homeSections.first?.items.first?.url.host == "animevietsub.news",
              "Recovered catalog identities never retain the obsolete hostname")
        HomeProtocol.reset(html: card("Untrusted redirect"), responseURL: URL(string: "https://other.example/")!)
        let untrusted = AnimeService(session: session, resolver: DomainResolver(defaultsSuiteName: defaultsName),
                                     homeStore: AnimeHomeStore(directory: directory.appendingPathComponent("untrusted")))
        await untrusted.loadHome()
        check(untrusted.homeSections.isEmpty, "An unexpected third-party Home redirect is never shown as anime")

        let previousManual = UserDefaults.standard.object(forKey: AnimeSiteConfiguration.customURLKey)
        defer {
            if let previousManual { UserDefaults.standard.set(previousManual, forKey: AnimeSiteConfiguration.customURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AnimeSiteConfiguration.customURLKey) }
        }
        UserDefaults.standard.set(manual.absoluteString, forKey: AnimeSiteConfiguration.customURLKey)
        let manualDefaultsName = defaultsName + ".manual"
        let manualDefaults = UserDefaults(suiteName: manualDefaultsName)!
        defer { manualDefaults.removePersistentDomain(forName: manualDefaultsName) }
        manualDefaults.set(manual.absoluteString, forKey: AnimeSiteConfiguration.customURLKey)
        HomeProtocol.reset(html: card("Wrong manual origin"), responseURL: URL(string: "https://animevietsub.news/")!)
        let manualService = AnimeService(session: session, resolver: DomainResolver(defaultsSuiteName: manualDefaultsName),
                                          homeStore: AnimeHomeStore(directory: directory.appendingPathComponent("manual-redirect")))
        await manualService.loadHome()
        check(manualService.homeSections.isEmpty && HomeProtocol.captured().allSatisfy { $0.host == manual.host },
              "A selected manual Home cannot silently redirect to the automatic catalog")
        HomeProtocol.reset(html: "<title>Just a moment...</title><form id='challenge-form'></form>")
        let manualChallenge = AnimeService(session: session, resolver: DomainResolver(defaultsSuiteName: manualDefaultsName),
                                            homeStore: AnimeHomeStore(directory: directory.appendingPathComponent("manual-challenge")))
        let browserCountBeforeManualChallenge = WebsiteSession.initializationCount
        await manualChallenge.loadHome()
        check(manualChallenge.homeSections.isEmpty && WebsiteSession.initializationCount == browserCountBeforeManualChallenge + 1 &&
              manualChallenge.website.loadCount == 1 && HomeProtocol.captured().allSatisfy { $0.host == manual.host },
              "A manual-source challenge creates its browser on demand without switching catalogs")
        print("ANIME_HOME_FIXTURE cold_content_ms=\(coldMS) warm_content_ms=\(warmMS) cold_requests=1 warm_requests=1; local fixture timings only")
    }
}
