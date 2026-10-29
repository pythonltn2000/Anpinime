import Foundation

/// Anime's chosen website is independent of all three movie providers.
enum AnimeSiteConfiguration {
    static let customURLKey = "AnPinime.animeURL"
    static func normalizedBase(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.first != "-" && $0.last != "-" }) else { return nil }
        var components = URLComponents(); components.scheme = "https"; components.host = host; components.port = url.port
        return components.url
    }
    static func selectedURL(defaults: UserDefaults = .standard) -> URL? {
        defaults.string(forKey: customURLKey).flatMap(normalizedBase)
    }
    @discardableResult
    static func migrateMisplacedURL(defaults: UserDefaults = .standard) -> Bool {
        guard selectedURL(defaults: defaults) == nil,
              let old = defaults.string(forKey: "AnPinime.phim4kURL"), let url = normalizedBase(old), isAutomaticHost(url.host) else { return false }
        defaults.set(url.absoluteString, forKey: customURLKey)
        defaults.removeObject(forKey: "AnPinime.phim4kURL")
        return true
    }
    static func isAutomaticHost(_ host: String?) -> Bool {
        guard let labels = host?.lowercased().split(separator: ".") else { return false }
        return (labels.count == 2 && labels[0] == "animevietsub") ||
            (labels.count == 3 && labels[0] == "www" && labels[1] == "animevietsub")
    }
    static func allows(_ url: URL, baseURL: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return url.host?.lowercased() == baseURL.host?.lowercased() || isAutomaticHost(url.host)
    }
}
