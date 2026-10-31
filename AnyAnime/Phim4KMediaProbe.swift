import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads only a small prefix, even if a server ignores Range and returns 200.
/// A new ephemeral session keeps the caller's protocol/cookie configuration;
/// the response body is never buffered as an entire movie.
final class Phim4KMediaProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result {
        let response: HTTPURLResponse
        let prefix: Data
        let wasTruncated: Bool
    }
    private let lock = NSLock()
    private let limit: Int
    private var continuation: CheckedContinuation<Result, Error>?
    private var response: HTTPURLResponse?
    private var prefix = Data()
    private var stoppedAtLimit = false
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var allowLoopbackHTTP = false
    private var sameOriginOnly = false
    private var allowRemoteHTTP = false
    private var redirectCount = 0

    init(limit: Int = 2048) { self.limit = max(1, min(limit, 65_536)) }

    func inspect(_ url: URL, headers: [String: String], configuration: URLSessionConfiguration,
                 allowLoopbackHTTP: Bool = false, sendRange: Bool = true, sameOriginOnly: Bool = false,
                 allowRemoteHTTP: Bool = false) async throws -> Result {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.allowLoopbackHTTP = allowLoopbackHTTP
                self.sameOriginOnly = sameOriginOnly
                self.allowRemoteHTTP = allowRemoteHTTP
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.httpMethod = "GET"
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                if sendRange { request.setValue("bytes=0-\(limit - 1)", forHTTPHeaderField: "Range") }
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { [weak self] in self?.cancel() })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); redirectCount += 1; let count = redirectCount; lock.unlock()
        guard count <= 5, let original = response.url, let destination = request.url,
              !sameOriginOnly || Phim4KTransportPolicy.sameOrigin(original, destination) else {
            completionHandler(nil); return
        }
        completionHandler(Phim4KTransportPolicy.redirectedRequest(request, from: original, allowLoopbackHTTP: allowLoopbackHTTP,
                                                                 allowRemoteHTTP: allowRemoteHTTP))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); self.response = response as? HTTPURLResponse; lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let remaining = max(0, limit - prefix.count)
        prefix.append(data.prefix(remaining))
        let done = prefix.count >= limit
        if done { stoppedAtLimit = true }
        lock.unlock()
        if done { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation; self.continuation = nil
        let response = self.response, prefix = self.prefix, stopped = stoppedAtLimit, cancelled = self.cancelled
        self.task = nil; self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        guard let continuation else { return }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        else if let error, !stopped { continuation.resume(throwing: error) }
        else if let response { continuation.resume(returning: Result(response: response, prefix: prefix, wasTruncated: stopped)) }
        else { continuation.resume(throwing: URLError(.badServerResponse)) }
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = self.task; lock.unlock()
        task?.cancel()
    }
}
