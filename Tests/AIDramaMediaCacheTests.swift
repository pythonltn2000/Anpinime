import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor CacheFixtureProvider: AIDramaProviding {
    let base: URL
    private var counts: [String: Int] = [:]
    init(base: URL) { self.base = base }
    func discover(cursor: String?) async throws -> AIDramaCatalogPage { throw AIDramaError.unavailable("unused") }
    func catalog(query: AIDramaCatalogQuery, cursor: String?, loadedSeriesIDs: [String]) async throws -> AIDramaCatalogPage { throw AIDramaError.unavailable("unused") }
    func catalogMetadata() async throws -> AIDramaCatalogMetadata { throw AIDramaError.unavailable("unused") }
    func shortFeed(loadedVideoIDs: [String]) async throws -> AIDramaShortFeedPage { throw AIDramaError.unavailable("unused") }
    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist { throw AIDramaError.unavailable("unused") }
    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream {
        counts[episode.id, default: 0] += 1
        try await Task.sleep(nanoseconds: 60_000_000)
        let path: String
        switch episode.number {
        case 99: path = "not-a-video.mp4"
        case 98: path = "media/episode-03.mp4"
        case 97: path = "media/episode-40.mp4"
        default: path = "media/episode-01.mp4"
        }
        return AIDramaStream(url: URL(string: path + "?clip_id=" + episode.id, relativeTo: base)!)
    }
    func count(_ id: String) -> Int { counts[id] ?? 0 }
}

@main struct MediaCacheChecks {
    static func check(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain: "AIDramaMediaCacheTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: " + message)
    }
    static func main() async throws {
        let base = URL(string: ProcessInfo.processInfo.environment["ANPINIME_AI_CACHE_URL"] ?? "http://127.0.0.1:8769/")!
        let provider = CacheFixtureProvider(base: base)
        let cache = AIDramaMediaCache(provider: provider)
        let episodes = (1...10).map { AIDramaEpisode(id: "clip-\($0)", seriesID: "series-\($0)", number: $0) }
        await cache.prepare(next: Array(episodes.prefix(5)), previous: [], current: "watching")
        var files: [String: URL] = [:]
        for _ in 0..<100 {
            for episode in episodes.prefix(5) {
                let stream = try await cache.resolve(episode)
                if stream.url.isFileURL { files[episode.id] = stream.url }
            }
            if files.count == 5 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try check(files.count == 5, "Five actual movie files are ready, not only metadata")
        for episode in episodes.prefix(5) { try check(await provider.count(episode.id) == 1, "Concurrent active/cache resolution coalesces for \(episode.id)") }
        let original = try Data(contentsOf: files[episodes[0].id]!)
        try check(original.count > 64 && String(data: original.subdata(in: 4..<8), encoding: .ascii) == "ftyp", "Cached data contains the complete MP4 fixture")

        await cache.prepare(next: episodes, previous: [], current: "watching")
        var tenReady = false
        for _ in 0..<100 {
            var ready = 0
            for episode in episodes { if try await cache.resolve(episode).url.isFileURL { ready += 1 } }
            if ready == 10 { tenReady = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try check(tenReady, "All ten upcoming videos can be cached in the same window")
        await cache.prepare(next: Array(episodes.dropFirst(5)), previous: Array(episodes.prefix(4)), current: episodes[4].id)
        try check(try await cache.resolve(episodes[0]).url == files[episodes[0].id], "A reverse swipe reuses the previous exact movie file")
        for _ in 0..<100 {
            var ready = 0
            for episode in episodes.dropFirst(5) { if try await cache.resolve(episode).url.isFileURL { ready += 1 } }
            if ready == 5 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let last = try await cache.resolve(episodes[9])
        try check(last.url.isFileURL, "The ten-video window can prepare later recommendations")
        await cache.stop(purge: true)
        try check(try await cache.resolve(episodes[4]).url.isFileURL, "Memory cleanup preserves the currently playing local file")
        try check(!FileManager.default.fileExists(atPath: files[episodes[0].id]!.path), "Cleanup removes unpinned previous movie data")

        let broken = AIDramaEpisode(id: "broken", seriesID: "broken", number: 99)
        await cache.prepare(next: [broken], previous: [], current: episodes[4].id)
        try await Task.sleep(nanoseconds: 700_000_000)
        try check(!(try await cache.resolve(broken)).url.isFileURL, "An HTTP/HTML failure is never handed to the player as a cached video")
        let failures = await provider.count(broken.id)
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(await provider.count(broken.id) == failures, "A failed preload does not enter an automatic retry loop")

        let oversized = AIDramaEpisode(id: "oversized", seriesID: "oversized", number: 98)
        let html = AIDramaEpisode(id: "html", seriesID: "html", number: 97)
        await cache.prepare(next: [oversized, html], previous: [], current: episodes[4].id)
        // The fixture serves a 25 MiB movie through a valid HTTP range. The cache
        // requests at most 24 MiB and must reject that incomplete movie.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        try check(!(try await cache.resolve(oversized)).url.isFileURL, "A partial oversized movie never becomes a local playback URL")
        try check(!(try await cache.resolve(html)).url.isFileURL, "An HTML body with HTTP 200 is never cached as MP4")
        await cache.stop()
        let interrupted = AIDramaEpisode(id: "interrupted", seriesID: "interrupted", number: 96)
        let pending = Task { try await cache.resolve(interrupted) }
        try await Task.sleep(nanoseconds: 10_000_000)
        await cache.stop()
        do {
            _ = try await pending.value
            throw NSError(domain: "AIDramaMediaCacheTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "A stopped resolution unexpectedly completed"])
        } catch is CancellationError {
            try check(true, "Leaving cancels an unfinished resolution")
        }
        _ = try await cache.resolve(interrupted)
        try check(await provider.count(interrupted.id) == 2, "Returning after cancellation starts a fresh usable resolution")
        print("All media preloading checks passed")
    }
}
