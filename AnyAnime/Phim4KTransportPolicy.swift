import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source-2 transport rules. Callers must opt in explicitly for local fixtures;
/// production Core/gateway endpoints always require HTTPS.
enum Phim4KTransportPolicy {
    private static func origin(_ url: URL) -> (String, String, Int)? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port) else { return nil }
        return (scheme, host, port)
    }

    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let left = origin(first), let right = origin(second) else { return false }
        return left == right
    }

    static func permitsEndpoint(_ url: URL, allowLoopbackHTTP: Bool = false) -> Bool {
        guard let value = origin(url), url.fragment == nil else { return false }
        if value.0 == "https" { return true }
        return allowLoopbackHTTP && ["127.0.0.1", "localhost", "::1", "[::1]"].contains(value.1)
    }

    /// The original gateway can return an HTTP media URL. This exception is
    /// for media only, never Core API or gateway transport.
    static func permitsMediaEndpoint(_ url: URL, allowLoopbackHTTP: Bool = false) -> Bool {
        guard let value = origin(url), url.fragment == nil else { return false }
        if value.0 == "https" { return true }
        if ["127.0.0.1", "localhost", "::1", "[::1]"].contains(value.1) { return allowLoopbackHTTP }
        return true
    }

    /// Checks authority only; the provider must still validate its Core API path.
    static func permitsCoreRequest(_ url: URL, baseURL: URL, allowLoopbackHTTP: Bool = false) -> Bool {
        permitsEndpoint(url, allowLoopbackHTTP: allowLoopbackHTTP)
            && permitsEndpoint(baseURL, allowLoopbackHTTP: allowLoopbackHTTP)
            && sameOrigin(url, baseURL)
    }

    static func redirectedRequest(_ proposed: URLRequest, from original: URL,
                                  allowLoopbackHTTP: Bool = false, allowRemoteHTTP: Bool = false) -> URLRequest? {
        func permits(_ url: URL) -> Bool {
            allowRemoteHTTP ? permitsMediaEndpoint(url, allowLoopbackHTTP: allowLoopbackHTTP)
                : permitsEndpoint(url, allowLoopbackHTTP: allowLoopbackHTTP)
        }
        guard let destination = proposed.url,
              permits(original), permits(destination),
              !(original.scheme?.lowercased() == "https" && destination.scheme?.lowercased() == "http") else { return nil }
        var next = proposed
        if !sameOrigin(original, destination) {
            let mediaHeaders = ["accept", "accept-encoding", "range", "user-agent"]
            for name in (next.allHTTPHeaderFields ?? [:]).keys where !mediaHeaders.contains(name.lowercased()) {
                next.setValue(nil, forHTTPHeaderField: name)
            }
            next.httpShouldHandleCookies = false
        }
        return next
    }
}

/// A dedicated source-2 delegate; it never changes other providers' sessions.
final class Phim4KRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    enum Mode { case sameOriginOnly, media }
    private let mode: Mode
    private let allowLoopbackHTTP: Bool
    private let allowRemoteHTTP: Bool
    private let maxRedirects: Int
    private let lock = NSLock()
    private struct TaskKey: Hashable {
        let session: ObjectIdentifier
        let identifier: Int
    }
    private final class RedirectCount {
        weak var task: URLSessionTask?
        let count: Int
        init(task: URLSessionTask, count: Int) { self.task = task; self.count = count }
    }
    private var redirectCounts: [TaskKey: RedirectCount] = [:]

    init(mode: Mode, allowLoopbackHTTP: Bool = false, allowRemoteHTTP: Bool = false, maxRedirects: Int = 5) {
        self.mode = mode
        self.allowLoopbackHTTP = allowLoopbackHTTP
        self.allowRemoteHTTP = mode == .media && allowRemoteHTTP
        self.maxRedirects = max(0, min(maxRedirects, 10))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        // Object addresses can be reused after a completed data(for:) request.
        // Session task identifiers remain unique; weak entries also clean up
        // completion-handler tasks that do not call the completion delegate.
        redirectCounts = redirectCounts.filter { $0.value.task != nil }
        let taskKey = TaskKey(session: ObjectIdentifier(session), identifier: task.taskIdentifier)
        let count = (redirectCounts[taskKey]?.count ?? 0) + 1
        redirectCounts[taskKey] = RedirectCount(task: task, count: count)
        lock.unlock()
        guard count <= maxRedirects, let original = response.url, let destination = request.url,
              mode == .media || Phim4KTransportPolicy.sameOrigin(original, destination) else {
            completionHandler(nil); return
        }
        completionHandler(Phim4KTransportPolicy.redirectedRequest(request, from: original,
                          allowLoopbackHTTP: allowLoopbackHTTP, allowRemoteHTTP: allowRemoteHTTP))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskKey = TaskKey(session: ObjectIdentifier(session), identifier: task.taskIdentifier)
        lock.lock(); redirectCounts.removeValue(forKey: taskKey); lock.unlock()
    }
}
