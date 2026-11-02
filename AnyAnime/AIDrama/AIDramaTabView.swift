import SwiftUI

/// Home within the independent Phim AI library.
@MainActor
struct AIDramaTabView: View {
    @ObservedObject var store: AIDramaCatalogStore
    @ObservedObject private var history = AIDramaHistoryStore.shared
    let selectTab: (Int) -> Void
    let open: (AIDramaSeries, String?) -> Void

    private var home: AIDramaCatalogState { store.snapshot(for: .home) }
    private var hot: AIDramaCatalogState { store.snapshot(for: .trending(.hot)) }
    private var newWorks: AIDramaCatalogState { store.snapshot(for: .newWorks) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if !home.series.isEmpty {
                        AIDramaHeroCarousel(series: home.series, width: geometry.size.width,
                                            loadingID: store.loadingPlaylistID, canLoadMore: home.canLoadMore,
                                            loadingMore: home.isLoadingMore, error: home.error,
                                            loadMore: { await store.loadMore(query: .home) }, open: { open($0, nil) })
                    } else {
                        AIDramaCatalogMessage(loading: home.isLoading, message: home.error,
                                              retry: { Task { await store.refresh(query: .home) } })
                    }
                    if !hot.series.isEmpty {
                        AIDramaHorizontalRow(title: "Thịnh hành", series: hot.series, loadingID: store.loadingPlaylistID,
                                             identifierPrefix: "aidrama.home.trending.", more: { selectTab(1) },
                                             canLoadMore: hot.canLoadMore, loadingMore: hot.isLoadingMore, error: hot.error,
                                             loadMore: { await store.loadMore(query: .trending(.hot)) }, open: { open($0, nil) })
                    } else if hot.error != nil {
                        sectionError(title: "Thịnh hành", state: hot, query: .trending(.hot))
                    }
                    if !newWorks.series.isEmpty {
                        AIDramaHorizontalRow(title: "Mới ra mắt", series: newWorks.series, loadingID: store.loadingPlaylistID,
                                             identifierPrefix: "aidrama.home.new.", more: { selectTab(3) },
                                             canLoadMore: newWorks.canLoadMore, loadingMore: newWorks.isLoadingMore, error: newWorks.error,
                                             loadMore: { await store.loadMore(query: .newWorks) }, open: { open($0, nil) })
                    } else if newWorks.error != nil {
                        sectionError(title: "Mới ra mắt", state: newWorks, query: .newWorks)
                    }
                    historyRow
                }
                .padding(.bottom, 24)
            }
            .refreshable { await refresh() }
        }
        .background(AIDramaTheme.background.ignoresSafeArea())
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(home.isLoading)
                    .accessibilityLabel("Làm mới Phim AI")
            }
        }
    }

    private var historyRow: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Đã xem").font(.title3.bold()).padding(.horizontal, 16)
            if history.entries.isEmpty {
                Text("Những bộ phim bạn xem sẽ xuất hiện ở đây.")
                    .font(.subheadline).foregroundColor(.secondary).padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(history.entries, id: \.series.id) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                AIDramaSeriesButton(series: entry.series, width: 132,
                                                    loading: store.loadingPlaylistID == entry.series.id,
                                                    identifierPrefix: "aidrama.history.", open: { _ in open(entry.series, entry.episodeID) })
                                if entry.duration > 0 {
                                    ProgressView(value: min(1, max(0, entry.position / entry.duration)))
                                        .tint(.anpinimeAccent).frame(width: 132)
                                }
                                if let number = entry.episodeNumber {
                                    Text("Tiếp tục tập \(number)").font(.caption).foregroundColor(.anpinimeAccent)
                                }
                            }
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionError(title: String, state: AIDramaCatalogState, query: AIDramaCatalogQuery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            Text(state.error ?? "").font(.footnote).foregroundColor(.secondary)
            Button("Thử lại") { Task { await store.refresh(query: query) } }.font(.subheadline)
        }.padding(.horizontal, 16)
    }

    private func load() async {
        async let home: Void = store.load(query: .home)
        async let hot: Void = store.load(query: .trending(.hot))
        async let newWorks: Void = store.load(query: .newWorks)
        _ = await (home, hot, newWorks)
    }

    private func refresh() async {
        async let home: Void = store.refresh(query: .home)
        async let hot: Void = store.refresh(query: .trending(.hot))
        async let newWorks: Void = store.refresh(query: .newWorks)
        _ = await (home, hot, newWorks)
    }
}
