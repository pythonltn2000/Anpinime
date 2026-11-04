import Foundation

/// Resolves and caches actual movie bytes, not just recommendation JSON. Files are
/// private temporary data; the current/nearby clips are kept within a 256 MiB budget.
actor AIDramaMediaCache: AIDramaProviding {
    private struct Entry {
        let stream: AIDramaStream
        let resolvedAt: Date
        var file: URL?
        var bytes = 0
    }
    private let provider: AIDramaProviding
    private let folder: URL
    private var entries: [String: Entry] = [:]
    private var resolving: [String: (id: UUID, task: Task<AIDramaStream, Error>)] = [:]
    private var failed = Set<String>()
    private var filling: [String: Task<Void, Never>] = [:]
    private var desired: [AIDramaEpisode] = []
    private var priority: [String] = []
    private var currentID: String?
    private var generation = UUID()
    private let perClipLimit: Int64 = 24 * 1024 * 1024
    private let totalLimit = 256 * 1024 * 1024

    init(provider: AIDramaProviding) {
        self.provider = provider
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnPinime-AI-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func shortFeed(loadedVideoIDs: [String]) async throws -> AIDramaShortFeedPage { try await provider.shortFeed(loadedVideoIDs: loadedVideoIDs) }
    func discover(cursor: String?) async throws -> AIDramaCatalogPage { try await provider.discover(cursor: cursor) }
    func catalog(query: AIDramaCatalogQuery, cursor: String?, loadedSeriesIDs: [String]) async throws -> AIDramaCatalogPage { try await provider.catalog(query: query, cursor: cursor, loadedSeriesIDs: loadedSeriesIDs) }
    func catalogMetadata() async throws -> AIDramaCatalogMetadata { try await provider.catalogMetadata() }
    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist { try await provider.playlist(for: series) }

    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream {
        try Task.checkCancellation()
        if let entry = entries[episode.id] {
            if let file = entry.file, FileManager.default.fileExists(atPath: file.path) { return AIDramaStream(url: file) }
            if Date().timeIntervalSince(entry.resolvedAt) < 40 { return entry.stream }
        }
        if let pending = resolving[episode.id] { return try await pending.task.value }
        let task = Task { [provider] in try await provider.resolve(episode) }
        let resolutionID = UUID()
        resolving[episode.id] = (resolutionID, task)
        do {
            let stream = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard resolving[episode.id]?.id == resolutionID else { throw CancellationError() }
            resolving[episode.id] = nil
            entries[episode.id] = Entry(stream: stream, resolvedAt: Date())
            return stream
        } catch {
            if resolving[episode.id]?.id == resolutionID { resolving[episode.id] = nil }
            throw error
        }
    }

    /// Request-order is preserved. A reverse swipe reuses the previous clip and its
    /// saved position; it never fetches a random replacement recommendation.
    func prepare(next: [AIDramaEpisode], previous: [AIDramaEpisode], current: String?) {
        if currentID != current { failed.removeAll() }
        currentID = current
        desired = next.filter { !$0.isLocked }
        priority = ([current].compactMap { $0 }) + desired.map(\.id) + previous.map(\.id)
        let wanted = Set(priority)
        for id in Array(filling.keys) where !wanted.contains(id) { filling.removeValue(forKey: id)?.cancel() }
        for id in Array(resolving.keys) where !wanted.contains(id) { resolving.removeValue(forKey: id)?.task.cancel() }
        trim()
        pump()
    }

    func stop(purge: Bool = false) {
        generation = UUID()
        filling.values.forEach { $0.cancel() }; filling.removeAll()
        resolving.values.forEach { $0.task.cancel() }; resolving.removeAll()
        desired = []
        if purge {
            for id in Array(entries.keys) where id != currentID {
                if let file = entries.removeValue(forKey: id)?.file { try? FileManager.default.removeItem(at: file) }
            }
            priority = [currentID].compactMap { $0 }
        }
    }

    private func pump() {
        guard filling.count < 2 else { return }
        let token = generation
        for episode in desired where filling[episode.id] == nil && entries[episode.id]?.file == nil {
            guard filling.count < 2 else { break }
            // Failed/oversized clips are retried on a later window, not in a hot loop.
            if failed.contains(episode.id) || entries[episode.id]?.bytes == -1 { continue }
            filling[episode.id] = Task { [weak self] in
                guard let self else { return }
                await self.fill(episode, token: token)
            }
        }
    }

    private func fill(_ episode: AIDramaEpisode, token: UUID) async {
        do {
            let stream = try await resolve(episode)
            try Task.checkCancellation()
            guard stream.url.scheme == "https" || stream.url.host == "127.0.0.1" else { throw URLError(.unsupportedURL) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            configuration.httpMaximumConnectionsPerHost = 2
            let budget = AIDramaDownloadBudget(limit: perClipLimit)
            let session = URLSession(configuration: configuration, delegate: budget, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: stream.url)
            stream.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            request.setValue("bytes=0-\(perClipLimit - 1)", forHTTPHeaderField: "Range")
            let (temporary, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard generation == token, priority.contains(episode.id),
                  let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else { throw URLError(.cancelled) }
            let size = (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size > 16, Int64(size) <= perClipLimit else { throw URLError(.dataLengthExceedsMaximum) }
            if http.statusCode == 206 {
                let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                guard range.hasPrefix("bytes 0-"), let total = range.split(separator: "/").last.flatMap({ Int($0) }), total == size else { throw URLError(.dataLengthExceedsMaximum) }
            } else if response.expectedContentLength > 0 {
                guard Int64(size) == response.expectedContentLength else { throw URLError(.cannotDecodeContentData) }
            }
            let handle = try FileHandle(forReadingFrom: temporary)
            let prefix = try handle.read(upToCount: 64) ?? Data(); try? handle.close()
            // Do not cache an HTML error, encrypted manifest or partial MP4 as a movie.
            guard prefix.count >= 12, String(data: prefix.subdata(in: 4..<8), encoding: .ascii) == "ftyp" else { throw URLError(.cannotDecodeContentData) }
            let file = folder.appendingPathComponent(UUID().uuidString + ".mp4")
            try FileManager.default.moveItem(at: temporary, to: file)
            guard var entry = entries[episode.id] else { try? FileManager.default.removeItem(at: file); throw URLError(.cancelled) }
            entry.file = file; entry.bytes = size; entries[episode.id] = entry
        } catch {
            if generation == token { failed.insert(episode.id) }
            if generation == token, var entry = entries[episode.id], !(error is CancellationError) { entry.bytes = -1; entries[episode.id] = entry }
        }
        guard generation == token else { return }
        filling[episode.id] = nil
        trim(); pump()
    }

    private func trim() {
        let wanted = Set(priority)
        for id in Array(entries.keys) where !wanted.contains(id) {
            if let file = entries.removeValue(forKey: id)?.file { try? FileManager.default.removeItem(at: file) }
        }
        var bytes = entries.values.reduce(0) { $0 + max(0, $1.bytes) }
        for id in priority.reversed() where bytes > totalLimit && id != currentID {
            guard var entry = entries[id], let file = entry.file else { continue }
            try? FileManager.default.removeItem(at: file); bytes -= max(0, entry.bytes)
            entry.file = nil; entry.bytes = -1; entries[id] = entry
        }
    }

    deinit {
        filling.values.forEach { $0.cancel() }; resolving.values.forEach { $0.task.cancel() }
        try? FileManager.default.removeItem(at: folder)
    }
}

private final class AIDramaDownloadBudget: NSObject, URLSessionDownloadDelegate {
    let limit: Int64
    init(limit: Int64) { self.limit = limit }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
}
