import SwiftUI

@MainActor
final class ArtworkLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var loading = false
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private var lastURL: URL?
    private var requestID = UUID()

    func load(_ source: URL?, baseURL: URL, revision: Int) async {
        let token = UUID()
        requestID = token
        guard let source else { image = nil; return }
        let url = Self.currentURL(source, baseURL: baseURL)
        if lastURL != url { image = Self.cache.object(forKey: url as NSURL) }
        lastURL = url
        if revision == 0, image != nil { return }
        loading = true
        defer { if requestID == token { loading = false } }
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, cachePolicy: revision > 0 ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: 25)
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/png,image/jpeg,image/webp,image/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard requestID == token, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), let decoded = UIImage(data: data) else { return }
            Self.cache.setObject(decoded, forKey: url as NSURL,
                                 cost: Int(decoded.size.width * decoded.size.height * 4))
            image = decoded
        } catch { /* Keep the last successful image during connection refresh. */ }
    }

    private static func currentURL(_ url: URL, baseURL: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host.hasPrefix("animevietsub.") || host.hasPrefix("www.animevietsub."),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.host = baseURL.host
        components.scheme = baseURL.scheme
        return components.url ?? url
    }
}
