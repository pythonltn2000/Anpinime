import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor DomainResolver {
    static let shared = DomainResolver()
    private let shortLink = URL(string: "https://bit.ly/animevietsubtv")!
    // These hosts are advertised by the source or were its known shortlink destination.
    private let fallbacks = ["https://animevietsub.news/", "https://animevietsub.xyz/", "https://animevietsub.fan/", "https://animevietsub.bio/", "https://animevietsub.vip/", "https://animevietsub.sale/"]
    private let cacheKey = "AnyAnime.VerifiedBaseURL.v2"
    private let oldCacheKey = "AnyAnime.ResolvedBaseURL"
    private let cacheDateKey = "AnyAnime.VerifiedBaseURL.updatedAt"
    private var selectedConfiguration: String?
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var resolvedThisLaunch: URL?
    private let defaults: UserDefaults
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let load: Loader

    init(defaultsSuiteName: String? = nil, load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) {
        defaults = defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.load = load
    }

    func invalidate() { resolvedThisLaunch = nil }

    /// Home can validate the real catalog request itself. Do not make it wait for
    /// a shortlink plus an unrelated detail-page probe before requesting cards.
    func homeCandidate() -> URL {
        #if DEBUG
        if PlaybackSmokeTest.animeFixture { return URL(string: "http://127.0.0.1:8765/")! }
        if PlaybackSmokeTest.liveAnime { return URL(string: "https://animevietsub.news/")! }
        #endif
        refreshSelectedConfiguration()
        if let custom = AnimeSiteConfiguration.selectedURL(defaults: defaults) { return custom }
        if let resolvedThisLaunch { return resolvedThisLaunch }
        return cachedURL(key: cacheKey) ?? URL(string: fallbacks[0])!
    }

    /// Called only after an actual successful Home response was parsed. The
    /// candidate/challenge alone is never recorded as a verified website.
    func acceptHomeURL(_ url: URL, sections: [AnimeSection]) -> URL? {
        guard let base = normalizedBase(url), isExpectedHost(base), !sections.isEmpty,
              sections.allSatisfy({ !$0.items.isEmpty && $0.items.allSatisfy {
                  $0.source == .anime && $0.url.host == base.host && $0.url.path.contains("phim")
              } }) else { return nil }
        if let custom = AnimeSiteConfiguration.selectedURL(defaults: defaults), custom.host != base.host { return nil }
        persistVerifiedBase(base)
        return base
    }

    private func refreshSelectedConfiguration() {
        let configuration = defaults.string(forKey: AnimeSiteConfiguration.customURLKey) ?? ""
        if selectedConfiguration != configuration { resolvedThisLaunch = nil; selectedConfiguration = configuration }
    }

    private func persistVerifiedBase(_ base: URL) {
        defaults.set(base.absoluteString, forKey: cacheKey)
        defaults.set(Date(), forKey: cacheDateKey)
        resolvedThisLaunch = base
    }

    func resolve(force: Bool = false) async -> URL {
        #if DEBUG
        if PlaybackSmokeTest.animeFixture { return URL(string: "http://127.0.0.1:8765/")! }
        if PlaybackSmokeTest.liveAnime { return URL(string: "https://animevietsub.news/")! }
        #endif
        refreshSelectedConfiguration()
        // An explicit user choice always wins over automatic/cache discovery.
        // Do not probe a legacy Bleach URL on a site that may use another catalog.
        if let custom = AnimeSiteConfiguration.selectedURL(defaults: defaults) {
            resolvedThisLaunch = custom
            return custom
        }
        if !force, let resolvedThisLaunch { return resolvedThisLaunch }
        // A previously verified page remains useful; later actual fetches still
        // detect 403/verification and retain the interactive WebKit flow.
        if !force, let cached = cachedURL(key: cacheKey),
           let date = defaults.object(forKey: cacheDateKey) as? Date,
           Date().timeIntervalSince(date) < 6 * 3600 {
            resolvedThisLaunch = cached; return cached
        }
        var request = URLRequest(url: shortLink, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        var redirect: URL?
        do {
            let (_, response) = try await load(request)
            if let final = response.url, let base = normalizedBase(final), isExpectedHost(base) { redirect = base }
            #if DEBUG
            print("[AnimeDomain] shortlink_status=\((response as? HTTPURLResponse)?.statusCode ?? 0) redirect_host=\(redirect?.host ?? "")")
            #endif
        } catch {
            #if DEBUG
            print("[AnimeDomain] shortlink_status=network_error")
            #endif
        }
        var candidates: [URL] = []
        for url in [redirect, cachedURL(key: cacheKey), cachedURL(key: oldCacheKey)] + fallbacks.map({ URL(string: $0) }) {
            if let url, !candidates.contains(url) { candidates.append(url) }
        }
        let agent = userAgent
        let load = self.load
        let verified = await withTaskGroup(of: (Int, URL?).self, returning: URL?.self) { group in
            for (index, base) in candidates.enumerated() {
                group.addTask {
                    var req = URLRequest(url: base.appendingPathComponent("phim/bleach-sennen-kessen-hen-kashin-tan-a5985/"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
                    req.setValue(agent, forHTTPHeaderField: "User-Agent")
                    do {
                        let (data, response) = try await load(req)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 3_000_000,
                              let final = http.url, final.host?.lowercased() == base.host?.lowercased(),
                              let html = String(data: data, encoding: .utf8), HTMLParser.isVerifiedAnimeDetail(html, url: final) else { return (index, nil) }
                        return (index, base)
                    } catch { return (index, nil) }
                }
            }
            var options: [(Int, URL)] = []
            for await (index, url) in group { if let url { options.append((index, url)) } }
            return options.sorted { $0.0 < $1.0 }.first?.1
        }
        if let verified {
            defaults.set(verified.absoluteString, forKey: cacheKey)
            defaults.set(Date(), forKey: cacheDateKey)
            resolvedThisLaunch = verified
            #if DEBUG
            print("[AnimeDomain] selected_host=\(verified.host ?? "") verified_anime_page=true")
            #endif
            return verified
        }
        // Do not persist an unverified result. Its challenge may require the
        // existing visible verification sheet on the user's own connection.
        let provisional = redirect ?? URL(string: fallbacks[0])!
        resolvedThisLaunch = provisional
        #if DEBUG
        print("[AnimeDomain] selected_host=\(provisional.host ?? "") verified_anime_page=false failure_reason=unavailable_or_verification")
        #endif
        return provisional
    }

    func acceptResolvedURL(_ url: URL, html: String) -> URL? {
        guard let base = normalizedBase(url), isExpectedHost(base), HTMLParser.isVerifiedAnimeDetail(html, url: url) else { return nil }
        if let custom = AnimeSiteConfiguration.selectedURL(defaults: defaults) {
            // The user selected this catalog; never let an old-domain response
            // or redirect silently switch it back to automatic discovery.
            guard custom.host == base.host else { return nil }
            resolvedThisLaunch = custom
            return custom
        }
        defaults.set(base.absoluteString, forKey: cacheKey)
        defaults.set(Date(), forKey: cacheDateKey)
        resolvedThisLaunch = base
        #if DEBUG
        print("[AnimeDomain] selected_host=\(base.host ?? "") verified_anime_page=true")
        #endif
        return base
    }
    private func cachedURL(key: String) -> URL? {
        guard let value = defaults.string(forKey: key), let url = URL(string: value), isExpectedHost(url) else { return nil }
        return normalizedBase(url)
    }
    private func normalizedBase(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        var components = URLComponents(); components.scheme = "https"; components.host = host; components.port = url.port
        return components.url
    }
    private func isExpectedHost(_ url: URL) -> Bool {
        if let custom = AnimeSiteConfiguration.selectedURL(defaults: defaults), url.host == custom.host { return true }
        return AnimeSiteConfiguration.isAutomaticHost(url.host)
    }
}
