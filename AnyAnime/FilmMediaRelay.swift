import Foundation
import Network

private final class FilmRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var request = request
        if response.url?.host != request.url?.host { request.setValue(nil, forHTTPHeaderField: "X-F4K-PT") }
        completionHandler(request)
    }
}

/// An in-process, loopback-only HLS adapter. URLs are opaque per-playback IDs;
/// callers cannot pass arbitrary upstream URLs. No movie files are written to disk.
@MainActor
final class FilmMediaRelay {
    var onQualities: (([PlaybackQuality]) -> Void)?
    private let origin: URL
    private let headers: [String: String]
    private let preserveMediaExtensions: Bool
    private let secret = UUID().uuidString
    private let queue = DispatchQueue(label: "AnPinime.FilmMediaRelay")
    private let session: URLSession
    private var listener: NWListener?
    private var endpoint: URL?
    private var ready: CheckedContinuation<Void, Error>?
    private var urls: [String: URL] = [:]
    private var identifiers: [URL: String] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private var requests: [UUID: Task<Void, Never>] = [:]
    private let mediaCache = NSCache<NSURL, NSData>()

    init(origin: URL, headers: [String: String], preserveMediaExtensions: Bool = false) {
        self.origin = origin; self.headers = headers
        self.preserveMediaExtensions = preserveMediaExtensions
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 12
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: FilmRedirectPolicy(), delegateQueue: nil)
        mediaCache.totalCostLimit = 96 * 1024 * 1024
        mediaCache.countLimit = 24
    }

    func start(_ url: URL) async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ready = continuation
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port else { return }
                        self.endpoint = URL(string: "http://127.0.0.1:\(port.rawValue)")!
                        self.ready?.resume(); self.ready = nil
                    case .failed(let error): self.ready?.resume(throwing: error); self.ready = nil
                    case .cancelled: self.ready?.resume(throwing: CancellationError()); self.ready = nil
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
        }
        try Task.checkCancellation()
        return localURL(url)
    }

    func stop() {
        listener?.cancel(); listener = nil
        ready?.resume(throwing: CancellationError()); ready = nil
        for task in requests.values { task.cancel() }
        requests.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        session.invalidateAndCancel()
        mediaCache.removeAllObjects()
        urls.removeAll(); identifiers.removeAll()
    }

    private func localURL(_ url: URL) -> URL {
        if let key = identifiers[url] { return endpoint!.appendingPathComponent(key) }
        let suffix = preserveMediaExtensions ? Phim4KRelayNaming.suffix(for: url)
            : (url.pathExtension == "m3u8" || url.path.hasSuffix("/stream/hls") ? "m3u8" : "bin")
        let key = "\(secret)/\(UUID().uuidString).\(suffix)"
        identifiers[url] = key; urls[key] = url
        return endpoint!.appendingPathComponent(key)
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, connections.count < 32 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.count > 16384 { self.close(id); return }
                if let end = buffer.range(of: Data("\r\n\r\n".utf8)),
                   let header = String(data: buffer[..<end.lowerBound], encoding: .utf8) {
                    self.requests[id] = Task { [weak self] in
                        guard let self else { return }
                        await self.serve(header, id: id)
                    }
                } else if complete || error != nil { self.close(id) }
                else { self.receive(connection, id: id, buffer: buffer) }
            }
        }
    }

    private func serve(_ header: String, id: UUID) async {
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, ["GET", "HEAD"].contains(String(parts[0])),
              let url = urls[String(parts[1].dropFirst())] else {
            send(id, status: 404, body: Data()); return
        }
        do {
            var request = URLRequest(url: url)
            for (name, value) in headers where name != "X-F4K-PT" || url.host == origin.host {
                request.setValue(value, forHTTPHeaderField: name)
            }
            // Range is applied AFTER removing the envelope, never to wrapped upstream bytes.
            let data: Data, response: URLResponse
            if let cached = mediaCache.object(forKey: url as NSURL) {
                data = cached as Data
                response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            } else {
                (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   !data.starts(with: Data("#EXTM3U".utf8)), data.count < 32 * 1024 * 1024 {
                    mediaCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
                }
            }
            try Task.checkCancellation()
            #if DEBUG
            if PlaybackSmokeTest.source2Diagnostic {
                PlaybackSmokeTest.diagnostic("relay-response", fields: ["host": url.host ?? "", "extension": url.pathExtension,
                    "status": (response as? HTTPURLResponse)?.statusCode ?? 0, "bytes": data.count,
                    "type": response.mimeType ?? ""])
            }
            #endif
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                send(id, status: (response as? HTTPURLResponse)?.statusCode ?? 502, body: Data()); return
            }
            guard data.count <= 128 * 1024 * 1024 else { send(id, status: 502, body: Data()); return }
            let body: Data, type: String
            if data.starts(with: Data("#EXTM3U".utf8)), let text = String(data: data, encoding: .utf8) {
                if text.contains("#EXT-X-STREAM-INF:") { onQualities?(FilmMediaTransform.qualities(text)) }
                body = Data(FilmMediaTransform.playlist(text, base: http.url ?? url, map: localURL).utf8)
                type = "application/vnd.apple.mpegurl"
            } else {
                body = FilmMediaTransform.unwrap(data)
                type = body.starts(with: Data("WEBVTT".utf8)) ? "text/vtt" : (body != data ? "video/mp4" : http.mimeType ?? "application/octet-stream")
            }
            let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }?.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if let rangeHeader {
                guard let range = FilmMediaTransform.byteRange(rangeHeader, count: body.count) else {
                    send(id, status: 416, body: Data(), extra: "Content-Range: bytes */\(body.count)\r\n"); return
                }
                send(id, status: 206, body: body.subdata(in: range), type: type, head: parts[0] == "HEAD",
                     extra: "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)\r\n")
            } else { send(id, status: 200, body: body, type: type, head: parts[0] == "HEAD") }
        } catch {
            #if DEBUG
            if PlaybackSmokeTest.source2Diagnostic { PlaybackSmokeTest.diagnostic("relay-error", fields: ["code": (error as NSError).code]) }
            #endif
            if connections[id] != nil { send(id, status: 502, body: Data()) }
        }
    }

    private func send(_ id: UUID, status: Int, body: Data, type: String = "text/plain", head: Bool = false, extra: String = "") {
        guard let connection = connections[id] else { return }
        var response = Data("HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\(extra)\r\n".utf8)
        if !head { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        requests.removeValue(forKey: id)?.cancel()
    }
}
