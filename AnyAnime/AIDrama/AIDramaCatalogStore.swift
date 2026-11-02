import SwiftUI

struct AIDramaCatalogState {
    var series: [AIDramaSeries] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var hasLoaded = false
    fileprivate var nextCursor: String?
    fileprivate var hasMore = false
    fileprivate var canContinueWithoutCursor = false

    var canLoadMore: Bool {
        hasLoaded && hasMore && (nextCursor != nil || canContinueWithoutCursor)
            && !isLoading && !isLoadingMore
    }
}

/// Each native feed/filter selection owns its pagination and generation. No AI
/// request changes the selected movie/anime provider or that provider's cache.
@MainActor
final class AIDramaCatalogStore: ObservableObject {
    let provider: AIDramaProviding
    @Published private var states: [AIDramaCatalogQuery: AIDramaCatalogState] = [:]
    @Published private(set) var metadata: AIDramaCatalogMetadata?
    @Published private(set) var metadataLoading = false
    @Published private(set) var metadataError: String?
    @Published private(set) var loadingPlaylistID: String?
    @Published private(set) var playlistError: String?

    private var tasks: [AIDramaCatalogQuery: Task<AIDramaCatalogPage, Error>] = [:]
    private var generations: [AIDramaCatalogQuery: UUID] = [:]
    private var visitedCursors: [AIDramaCatalogQuery: Set<String>] = [:]
    private var metadataTask: Task<AIDramaCatalogMetadata, Error>?
    private var metadataGeneration = UUID()
    private var playlistGeneration = UUID()
    private var playlistTask: Task<AIDramaPlaylist, Error>?
    private var playlistCache: [String: (Date, AIDramaPlaylist)] = [:]
    private let playlistCacheLifetime: TimeInterval = 300

    init(provider: AIDramaProviding = PineDramaProvider()) { self.provider = provider }

    func snapshot(for query: AIDramaCatalogQuery) -> AIDramaCatalogState { states[query] ?? AIDramaCatalogState() }

    // Compatibility for the original standalone catalog and existing callers.
    var series: [AIDramaSeries] { snapshot(for: .home).series }
    var isLoading: Bool { snapshot(for: .home).isLoading }
    var isLoadingMore: Bool { snapshot(for: .home).isLoadingMore }
    var error: String? { snapshot(for: .home).error }
    var canLoadMore: Bool { snapshot(for: .home).canLoadMore }
    func loadInitialIfNeeded() async { await load(query: .home) }
    func refresh() async { playlistCache.removeAll(); await refresh(query: .home) }
    func loadMore() async { await loadMore(query: .home) }

    func load(query: AIDramaCatalogQuery) async {
        cancelOtherCategoryRequests(keeping: query)
        let state = snapshot(for: query)
        guard !state.hasLoaded, !state.isLoading, !state.isLoadingMore else { return }
        await fetch(query: query, replacing: true)
    }

    func refresh(query: AIDramaCatalogQuery) async {
        cancelOtherCategoryRequests(keeping: query)
        await fetch(query: query, replacing: true)
    }

    func loadMore(query: AIDramaCatalogQuery) async {
        guard snapshot(for: query).canLoadMore else { return }
        await fetch(query: query, replacing: false)
    }

    private func cancelOtherCategoryRequests(keeping query: AIDramaCatalogQuery) {
        guard case .categories = query else { return }
        for old in Array(tasks.keys) where old != query {
            guard case .categories = old else { continue }
            tasks.removeValue(forKey: old)?.cancel()
            generations[old] = UUID()
            if var state = states[old] {
                state.isLoading = false; state.isLoadingMore = false
                states[old] = state
            }
        }
        // Keep the four primary feeds and a bounded number of recent filter combinations.
        if states.count >= 20, states[query] == nil {
            for old in Array(states.keys) where old != query && tasks[old] == nil {
                if case .categories = old { states.removeValue(forKey: old); visitedCursors.removeValue(forKey: old) }
            }
        }
    }

    private func fetch(query: AIDramaCatalogQuery, replacing: Bool) async {
        tasks[query]?.cancel()
        let generation = UUID()
        generations[query] = generation
        var initial = snapshot(for: query)
        let cursor = replacing ? nil : initial.nextCursor
        let existingIDs = replacing ? [] : initial.series.map(\.id)
        initial.error = nil
        initial.isLoading = replacing
        initial.isLoadingMore = !replacing
        states[query] = initial
        let provider = provider
        let task = Task { try await provider.catalog(query: query, cursor: cursor, loadedSeriesIDs: existingIDs) }
        tasks[query] = task
        defer {
            if generations[query] == generation {
                tasks[query] = nil
                var state = snapshot(for: query)
                state.isLoading = false; state.isLoadingMore = false
                states[query] = state
            }
        }
        do {
            let page = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard generations[query] == generation else { return }
            guard page.series.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw AIDramaError.invalidResponse
            }
            var state = snapshot(for: query)
            if replacing { state.series = []; visitedCursors[query] = [] }
            let oldCount = state.series.count
            var indexes = Dictionary(uniqueKeysWithValues: state.series.enumerated().map { ($0.element.id, $0.offset) })
            for item in page.series {
                if let index = indexes[item.id] { state.series[index] = item }
                else { indexes[item.id] = state.series.count; state.series.append(item) }
            }
            if let cursor { visitedCursors[query, default: []].insert(cursor) }
            state.hasLoaded = true
            state.nextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            state.hasMore = page.hasMore
            state.canContinueWithoutCursor = query == .home
            if let next = state.nextCursor, visitedCursors[query, default: []].contains(next) {
                state.hasMore = false
                state.error = "Nguồn phim đang lặp lại trang đã tải. Hãy thử làm mới."
            }
            // Recommendation pages may overlap. Stop rather than request forever
            // when the native continuation adds no new actual series identities.
            if !replacing && state.series.count == oldCount { state.hasMore = false }
            states[query] = state
            AIDramaHistoryStore.shared.refreshMetadata(for: page.series)
        } catch {
            guard generations[query] == generation, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            var state = snapshot(for: query)
            state.error = error.localizedDescription
            states[query] = state
        }
    }

    func loadMetadataIfNeeded() async {
        guard metadata == nil, !metadataLoading else { return }
        await refreshMetadata()
    }

    func refreshMetadata() async {
        metadataTask?.cancel()
        let generation = UUID()
        metadataGeneration = generation
        metadataLoading = true; metadataError = nil
        let provider = provider
        let task = Task { try await provider.catalogMetadata() }
        metadataTask = task
        defer {
            if metadataGeneration == generation { metadataTask = nil; metadataLoading = false }
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard metadataGeneration == generation else { return }
            metadata = result
        } catch {
            guard metadataGeneration == generation, !Task.isCancelled,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            metadataError = error.localizedDescription
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
