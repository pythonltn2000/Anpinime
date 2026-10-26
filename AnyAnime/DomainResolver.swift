import Foundation

actor DomainResolver {
    static let shared = DomainResolver()

    private let shortLink = URL(string: "https://bit.ly/animevietsubtv")!
    private let fallbacks = [
        "https://animevietsub.vip/",
        "https://animevietsub.sale/",
        "https://animevietsub.xyz/"
    ]
    private let cacheKey = "AnyAnime.ResolvedBaseURL"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var resolvedThisLaunch: URL?

    func resolve(force: Bool = false) async -> URL {
        if !force, let resolvedThisLaunch { return resolvedThisLaunch }
        if !force, let cached = cachedURL() {
            resolvedThisLaunch = cached
            return cached
        }

        var request = URLRequest(url: shortLink, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let final = response.url, let base = normalizedBase(final), isExpectedHost(base) {
                UserDefaults.standard.set(base.absoluteString, forKey: cacheKey)
                resolvedThisLaunch = base
                return base
            }
        } catch {
            // Cached and known domains below deliberately remain available offline.
        }

        if let cached = cachedURL() {
            resolvedThisLaunch = cached
            return cached
        }
        for value in fallbacks {
            if let url = URL(string: value) {
                resolvedThisLaunch = url
                return url
            }
        }
        return URL(string: "https://animevietsub.vip/")!
    }

    func acceptResolvedURL(_ url: URL) -> URL? {
        guard let base = normalizedBase(url), isExpectedHost(base) else { return nil }
        UserDefaults.standard.set(base.absoluteString, forKey: cacheKey)
        resolvedThisLaunch = base
        return base
    }

    private func cachedURL() -> URL? {
        guard let value = UserDefaults.standard.string(forKey: cacheKey),
              let url = URL(string: value), isExpectedHost(url) else { return nil }
        return normalizedBase(url)
    }

    private func normalizedBase(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url
    }

    private func isExpectedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let labels = host.split(separator: ".")
        return labels.first == "animevietsub" ||
            (labels.count > 1 && labels[0] == "www" && labels[1] == "animevietsub")
    }
}
