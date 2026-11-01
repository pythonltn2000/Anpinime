import SwiftUI

/// Catalog and complete playlists for Phim AI have their own lifetime/cache;
/// they never alter the selected anime/movie source or its provider state.
@MainActor
final class AIDramaCatalogStore: ObservableObject {
    let provider: AIDramaProviding
    @Published private(set) var series: [AIDramaSeries] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var loadingPlaylistID: String?
    @Published private(set) var playlistError: String?

    private var loadedInitial = false
    private var nextCursor: String?
    private var visitedCursors = Set<String>()
    private var catalogGeneration = UUID()
    private var catalogTask: Task<AIDramaCatalogPage, Error>?
    private var playlistGeneration = UUID()
    private var playlistTask: Task<AIDramaPlaylist, Error>?
    private var playlistCache: [String: (Date, AIDramaPlaylist)] = [:]
    private let playlistCacheLifetime: TimeInterval = 300

    var canLoadMore: Bool { nextCursor != nil && !isLoading && !isLoadingMore }

    init(provider: AIDramaProviding = PineDramaProvider()) { self.provider = provider }

    func loadInitialIfNeeded() async {
        guard !loadedInitial, !isLoading, !isLoadingMore else { return }
        await loadCatalog(cursor: nil, replacing: true)
    }

    func refresh() async {
        playlistCache.removeAll()
        await loadCatalog(cursor: nil, replacing: true)
    }

    func loadMore() async {
        guard canLoadMore, let cursor = nextCursor else { return }
        await loadCatalog(cursor: cursor, replacing: false)
    }

    private func loadCatalog(cursor: String?, replacing: Bool) async {
        catalogTask?.cancel()
        let generation = UUID()
        catalogGeneration = generation
        error = nil
        isLoading = replacing
        isLoadingMore = !replacing
        let provider = provider
        let task = Task { try await provider.discover(cursor: cursor) }
        catalogTask = task
        defer {
            if catalogGeneration == generation {
                catalogTask = nil
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let page = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard catalogGeneration == generation else { return }
            guard page.series.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw AIDramaError.invalidResponse
            }
            if replacing {
                series = []
                visitedCursors.removeAll()
            }
            var indexes = Dictionary(uniqueKeysWithValues: series.enumerated().map { ($0.element.id, $0.offset) })
            for item in page.series {
                if let index = indexes[item.id] { series[index] = item }
                else { indexes[item.id] = series.count; series.append(item) }
            }
            if let cursor { visitedCursors.insert(cursor) }
            loadedInitial = true
            nextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            if let nextCursor, visitedCursors.contains(nextCursor) {
                self.nextCursor = nil
                error = "Nguồn phim đang lặp lại trang đã tải. Hãy làm mới danh sách."
            }
        } catch {
            guard catalogGeneration == generation, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }

    /// Return only a validated complete playlist. Resolve media later in the
    /// player, so expiring stream URLs are never stored as catalog data.
    func loadPlaylist(for item: AIDramaSeries) async -> AIDramaPlaylist? {
        playlistTask?.cancel()
        let generation = UUID()
        playlistGeneration = generation
        playlistError = nil
        loadingPlaylistID = item.id
        defer {
            if playlistGeneration == generation {
                playlistTask = nil
                loadingPlaylistID = nil
            }
        }
        if let (date, cached) = playlistCache[item.id], Date().timeIntervalSince(date) < playlistCacheLifetime,
           item.episodeCount == nil || item.episodeCount == cached.episodes.count {
            guard !Task.isCancelled else { return nil }
            return cached
        }
        let provider = provider
        let task = Task { try await provider.playlist(for: item) }
        playlistTask = task
        do {
            let playlist = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard playlistGeneration == generation else { return nil }
            guard playlist.series.id == item.id, !playlist.episodes.isEmpty,
                  playlist.episodes.allSatisfy({ !$0.id.isEmpty && $0.seriesID == item.id }),
                  Set(playlist.episodes.map(\.id)).count == playlist.episodes.count else { throw AIDramaError.incompletePlaylist }
            if let total = playlist.reportedTotal ?? playlist.series.episodeCount ?? item.episodeCount,
               total != playlist.episodes.count { throw AIDramaError.incompletePlaylist }
            if playlistCache.count >= 20 { playlistCache.removeAll() }
            playlistCache[item.id] = (Date(), playlist)
            return playlist
        } catch {
            guard playlistGeneration == generation, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return nil }
            playlistError = error.localizedDescription
            return nil
        }
    }

    func clearPlaylistError() { playlistError = nil }

    func cancelPlaylistLoading() {
        playlistGeneration = UUID()
        playlistTask?.cancel()
        playlistTask = nil
        loadingPlaylistID = nil
        playlistError = nil
    }
}
