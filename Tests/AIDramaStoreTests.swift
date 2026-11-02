import Foundation

/// macOS CLI (SwiftUI/Combine are supplied by the two production stores):
/// swiftc -parse-as-library AnyAnime/AIDrama/AIDramaModels.swift \
///   AnyAnime/AIDrama/PineDramaProvider.swift AnyAnime/AIDrama/AIDramaHistoryStore.swift \
///   AnyAnime/AIDrama/AIDramaCatalogStore.swift Tests/AIDramaStoreTests.swift \
///   -o /tmp/aidrama-store-tests && /tmp/aidrama-store-tests
@main
struct AIDramaStoreTests {
    enum TestFailure: Error { case missingPendingRequest, timeout(String) }

    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: " + message) }
        print("PASS: " + message)
    }

    static func item(_ number: Int, title: String? = nil) -> AIDramaSeries {
        AIDramaSeries(id: String(7_100_000_000_000_000_000 + Int64(number)),
                      title: title ?? "Store fixture \(number)", episodeCount: 5)
    }

    static func page(_ items: [AIDramaSeries], cursor: String? = nil, more: Bool = false) -> AIDramaCatalogPage {
        AIDramaCatalogPage(series: items, nextCursor: cursor, hasMore: more)
    }

    static func waitForCalls(_ provider: ControlledDramaProvider, _ count: Int) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await provider.requestIsReady(count - 1)) {
            guard Date() < deadline else { throw TestFailure.timeout("catalog request \(count)") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    static func waitForCancellation(_ provider: ControlledDramaProvider, _ request: Int) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await provider.wasCancelled(request)) {
            guard Date() < deadline else { throw TestFailure.timeout("request \(request) cancellation") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @MainActor
    static func testHomeContinuation() async throws {
        let provider = ControlledDramaProvider()
        let store = AIDramaCatalogStore(provider: provider)
        let first = Task { await store.load(query: .home) }
        try await waitForCalls(provider, 1)
        let initial = await provider.call(0)
        check(initial.query == .home && initial.cursor == nil && initial.loadedIDs.isEmpty,
              "Initial home request has no fabricated cursor or loaded identities")
        try await provider.succeed(0, page([item(1), item(2)], more: true))
        await first.value
        check(store.snapshot(for: .home).canLoadMore, "Native home has_more can continue with an empty server cursor")

        let second = Task { await store.loadMore(query: .home) }
        try await waitForCalls(provider, 2)
        let continuation = await provider.call(1)
        check(continuation.cursor == nil && continuation.loadedIDs == [item(1).id, item(2).id],
              "Home continuation sends the exact ordered IDs actually loaded")
        try await provider.succeed(1, page([item(2, title: "Updated metadata"), item(3), item(3, title: "Latest duplicate")], more: true))
        await second.value
        let appended = store.snapshot(for: .home)
        check(appended.series.map(\.id) == [item(1).id, item(2).id, item(3).id],
              "Overlapping and duplicate rows append once by exact Int64 string identity")
        check(appended.series[1].title == "Updated metadata" && appended.series[2].title == "Latest duplicate",
              "Repeated identities refresh metadata without changing feed order")

        let third = Task { await store.loadMore(query: .home) }
        try await waitForCalls(provider, 3)
        let accumulated = await provider.call(2)
        check(accumulated.loadedIDs == appended.series.map(\.id), "Later home requests use all unique accumulated IDs")
        try await provider.succeed(2, page([item(2), item(3)], more: true))
        await third.value
        check(!store.snapshot(for: .home).canLoadMore && store.series.count == 3,
              "Home stops when native continuation adds no new identities")
        await store.loadMore(query: .home)
        check(await provider.callCount() == 3, "A no-progress home feed cannot request indefinitely")
    }

    @MainActor
    static func testCursorLoopAndIndependentFeeds() async throws {
        let provider = ControlledDramaProvider()
        let store = AIDramaCatalogStore(provider: provider)
        let query = AIDramaCatalogQuery.trending(.hot)
        let first = Task { await store.load(query: query) }
        try await waitForCalls(provider, 1)
        try await provider.succeed(0, page([item(11)], cursor: "native-a", more: true))
        await first.value

        let second = Task { await store.loadMore(query: query) }
        try await waitForCalls(provider, 2)
        check(await provider.call(1).cursor == "native-a", "Ranking forwards the first real server cursor unchanged")
        try await provider.succeed(1, page([item(12)], cursor: "native-b", more: true))
        await second.value
        let third = Task { await store.loadMore(query: query) }
        try await waitForCalls(provider, 3)
        check(await provider.call(2).cursor == "native-b", "Ranking forwards the advancing server cursor unchanged")
        try await provider.succeed(2, page([item(13)], cursor: "native-a", more: true))
        await third.value
        let loop = store.snapshot(for: query)
        check(loop.series.map(\.id) == [item(11).id, item(12).id, item(13).id] && !loop.canLoadMore && loop.error != nil,
              "A true server-cursor cycle retains valid new items and stops with a visible error")
        await store.loadMore(query: query)
        check(await provider.callCount() == 3, "Repeated server cursors cannot trigger another request")

        let latest = Task { await store.load(query: .trending(.latest)) }
        try await waitForCalls(provider, 4)
        try await provider.succeed(3, page([item(14)], more: true))
        await latest.value
        check(!store.snapshot(for: .trending(.latest)).canLoadMore,
              "A cursor-driven feed cannot invent continuation from has_more alone")
        check(store.snapshot(for: query).series.count == 3 && store.snapshot(for: .home).series.isEmpty,
              "Ranking modes and Home keep independent catalog state")
    }

    @MainActor
    static func testRetryPreservesPage() async throws {
        let provider = ControlledDramaProvider()
        let store = AIDramaCatalogStore(provider: provider)
        let first = Task { await store.load(query: .newWorks) }
        try await waitForCalls(provider, 1)
        try await provider.succeed(0, page([item(21)], cursor: "retry-this-native-cursor", more: true))
        await first.value
        let failed = Task { await store.loadMore(query: .newWorks) }
        try await waitForCalls(provider, 2)
        try await provider.fail(1, URLError(.timedOut))
        await failed.value
        let preserved = store.snapshot(for: .newWorks)
        check(preserved.series.map(\.id) == [item(21).id] && preserved.error != nil && preserved.canLoadMore,
              "A failed next page preserves prior items and remains retryable")
        check(!preserved.isLoading && !preserved.isLoadingMore, "Failed pagination releases both loading flags")

        let retry = Task { await store.loadMore(query: .newWorks) }
        try await waitForCalls(provider, 3)
        let failedCall = await provider.call(1)
        let retryCall = await provider.call(2)
        check(retryCall.cursor == failedCall.cursor && retryCall.cursor == "retry-this-native-cursor" && retryCall.loadedIDs == [item(21).id],
              "Retry uses the same unconsumed server cursor and existing exact IDs")
        try await provider.succeed(2, page([item(22)]))
        await retry.value
        let recovered = store.snapshot(for: .newWorks)
        check(recovered.series.map(\.id) == [item(21).id, item(22).id] && recovered.error == nil && !recovered.canLoadMore,
              "Successful retry appends the recovered page and clears its old error")
    }

    @MainActor
    static func testRapidCategorySelection() async throws {
        let provider = ControlledDramaProvider()
        let store = AIDramaCatalogStore(provider: provider)
        let oldQuery = AIDramaCatalogQuery.categories(.init(backgroundID: "7628991192537158672"))
        let newQuery = AIDramaCatalogQuery.categories(.init(characterID: "7628991193891820560", recentDays: 7))
        let old = Task { await store.load(query: oldQuery) }
        try await waitForCalls(provider, 1)
        let current = Task { await store.load(query: newQuery) }
        try await waitForCalls(provider, 2)
        try await waitForCancellation(provider, 0)
        check(await provider.wasCancelled(0), "Changing category selection cancels the previous provider task")
        try await provider.succeed(1, page([item(32)], cursor: "new-selection-cursor", more: true))
        await current.value
        // This provider deliberately ignores cancellation and returns the stale
        // reply afterward, so generation protection must reject it independently.
        try await provider.succeed(0, page([item(31)], cursor: "stale-selection-cursor", more: true))
        await old.value
        let state = store.snapshot(for: newQuery)
        check(state.series.map(\.id) == [item(32).id] && state.error == nil && state.canLoadMore,
              "A late cancelled reply never contaminates the current category result")
        check(store.snapshot(for: oldQuery).series.isEmpty && !store.snapshot(for: oldQuery).hasLoaded && !store.snapshot(for: oldQuery).isLoading,
              "Cancelled category generation cannot populate its stale cache or leave loading stuck")

        let pending = Task { await store.load(query: oldQuery) }
        try await waitForCalls(provider, 3)
        await store.load(query: newQuery) // Already cached: cancellation must still happen.
        try await waitForCancellation(provider, 2)
        check(await provider.callCount() == 3, "Returning to a cached category cancels pending work without refetching its cached page")
        try await provider.succeed(2, page([item(33)]))
        await pending.value
        check(store.snapshot(for: newQuery).series.map(\.id) == [item(32).id] && store.snapshot(for: oldQuery).series.isEmpty,
              "Cached-category navigation rejects the cancelled background completion")
    }

    @MainActor
    static func testHistoryPersistenceAndIsolation() throws {
        let suiteName = "AnPinime.AIDrama.StoreTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("Cannot create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let historyKey = "AnPinime.AIDrama.history.v1"
        let history = AIDramaHistoryStore(defaults: defaults)
        let series = AIDramaSeries(id: "7100000000000009001", title: "History fixture",
                                   coverURL: URL(string: "https://images.example/cover.jpg"), episodeCount: 5)
        let first = AIDramaEpisode(id: "7100000000000009101", seriesID: series.id, number: 1)
        let second = AIDramaEpisode(id: "7100000000000009102", seriesID: series.id, number: 2)
        history.record(series: series, episode: first, position: 47.5, duration: 120)
        history.record(series: series, episode: second, position: 64.25, duration: 130)
        let reloaded = AIDramaHistoryStore(defaults: defaults)
        check(reloaded.entries.count == 1 && reloaded.entries[0].id == series.id && reloaded.entries[0].episodeID == second.id,
              "History round-trip retains exact series/episode IDs and updates one entry per series")
        check(reloaded.entries[0].episodeNumber == 2 && reloaded.entries[0].position == 64.25 && reloaded.entries[0].duration == 130,
              "History round-trip retains the selected episode number and actual progress")
        let saved = defaults.data(forKey: historyKey)!
        let rows = try JSONSerialization.jsonObject(with: saved) as! [[String: Any]]
        let allowedKeys: Set<String> = ["series", "episodeID", "episodeNumber", "position", "duration", "updatedAt"]
        check(Set(rows[0].keys) == allowedKeys && !String(decoding: saved, as: UTF8.self).contains("streamURL") && rows[0]["episodeID"] as? String == second.id,
              "History schema contains stable identities/progress and no resolved stream field")
        let refreshed = AIDramaSeries(id: series.id, title: "Fresh catalog title", episodeCount: 5, viewCount: 1234, genreText: "Native genre")
        reloaded.refreshMetadata(for: [refreshed])
        let metadataReload = AIDramaHistoryStore(defaults: defaults)
        check(metadataReload.entries[0].series.title == refreshed.title && metadataReload.entries[0].episodeID == second.id && metadataReload.entries[0].position == 64.25,
              "Refreshing history artwork/title metadata preserves stable episode identity and progress")

        history.record(series: series, episode: AIDramaEpisode(id: first.id, seriesID: item(99).id, number: 1), position: 8, duration: 10)
        history.record(series: series, episode: first, position: .nan, duration: 10)
        history.record(series: series, episode: first, position: 8, duration: .infinity)
        check(history.entries.count == 1 && history.entries[0].episodeID == second.id, "Invalid parent identities or nonfinite progress cannot replace valid history")

        for index in 1...205 {
            let item = Self.item(1000 + index)
            let episode = AIDramaEpisode(id: String(7_200_000_000_000_000_000 + Int64(index)), seriesID: item.id, number: 1)
            history.record(series: item, episode: episode, position: Double(index), duration: 300)
        }
        let limited = AIDramaHistoryStore(defaults: defaults)
        let expected = Set((6...205).map { item(1000 + $0).id })
        check(history.entries.count == 200 && limited.entries.count == 200 && Set(limited.entries.map(\.id)) == expected,
              "Persisted history keeps the newest 200 distinct series and evicts older entries")
        limited.remove(seriesID: item(1205).id)
        check(AIDramaHistoryStore(defaults: defaults).entries.count == 199 && !limited.entries.contains { $0.id == item(1205).id },
              "Removing one AI history entry persists without removing other series")

        let progressKeys = ["AnPinime.AIDrama.positions." + series.id, "AnPinime.AIDrama.selected." + series.id, "AnPinime.AIDrama.paused." + series.id]
        for key in progressKeys { defaults.set("AI progress sentinel", forKey: key) }
        let unrelated = ["AnPinime.history.anime", "AnPinime.history.movie", "AnPinime.animeURL", "AnPinime.movieSource", "AnPinime.phim4kURL", "AnPinime.selectedLibrary", "AnPinime.AIDrama.catalog.preference"]
        for key in unrelated { defaults.set("preserve:" + key, forKey: key) }
        limited.clear()
        check(limited.entries.isEmpty && AIDramaHistoryStore(defaults: defaults).entries.isEmpty && defaults.object(forKey: historyKey) == nil && progressKeys.allSatisfy { defaults.object(forKey: $0) == nil },
              "Clearing AI history removes AI entries and saved position/selection/pause keys")
        check(unrelated.allSatisfy { defaults.string(forKey: $0) == "preserve:" + $0 },
              "Clearing AI history preserves independent anime/movie history, sources, selected library and unrelated preferences")
    }

    @MainActor
    static func main() async throws {
        try await testHomeContinuation()
        try await testCursorLoopAndIndependentFeeds()
        try await testRetryPreservesPage()
        try await testRapidCategorySelection()
        try testHistoryPersistenceAndIsolation()
        print("All AI catalog/history store regressions passed")
    }
}

/// Every completion is manually gated. Cancellation is observed but deliberately
/// ignored until completion, exercising the production store's generation guard.
actor ControlledDramaProvider: AIDramaProviding {
    struct Call: Sendable {
        let query: AIDramaCatalogQuery
        let cursor: String?
        let loadedIDs: [String]
    }
    private var calls: [Call] = []
    private var pending: [Int: CheckedContinuation<AIDramaCatalogPage, Error>] = [:]
    private var cancelled = Set<Int>()

    func catalog(query: AIDramaCatalogQuery, cursor: String?, loadedSeriesIDs: [String]) async throws -> AIDramaCatalogPage {
        let index = calls.count
        calls.append(Call(query: query, cursor: cursor, loadedIDs: loadedSeriesIDs))
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        }, onCancel: {
            Task { await self.noteCancellation(index) }
        })
    }

    private func noteCancellation(_ index: Int) { cancelled.insert(index) }
    func wasCancelled(_ index: Int) -> Bool { cancelled.contains(index) }
    func requestIsReady(_ index: Int) -> Bool { index < calls.count && pending[index] != nil }
    func callCount() -> Int { calls.count }
    func call(_ index: Int) -> Call { calls[index] }

    func succeed(_ index: Int, _ page: AIDramaCatalogPage) throws {
        guard let continuation = pending.removeValue(forKey: index) else { throw AIDramaStoreTests.TestFailure.missingPendingRequest }
        continuation.resume(returning: page)
    }

    func fail(_ index: Int, _ error: Error) throws {
        guard let continuation = pending.removeValue(forKey: index) else { throw AIDramaStoreTests.TestFailure.missingPendingRequest }
        continuation.resume(throwing: error)
    }

    func discover(cursor: String?) async throws -> AIDramaCatalogPage {
        try await catalog(query: .home, cursor: cursor, loadedSeriesIDs: [])
    }
    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist { throw AIDramaError.incompletePlaylist }
    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream { throw AIDramaError.missingEpisode }
}
