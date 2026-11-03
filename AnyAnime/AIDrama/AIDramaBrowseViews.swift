import SwiftUI

@MainActor
struct AIDramaTrendingView: View {
    @ObservedObject var store: AIDramaCatalogStore
    let open: (AIDramaSeries) -> Void
    @State private var ranking = AIDramaRanking.hot

    private var query: AIDramaCatalogQuery { .trending(ranking) }
    private var state: AIDramaCatalogState { store.snapshot(for: query) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker("Bảng xếp hạng", selection: $ranking) {
                    Text("Nóng nhất").tag(AIDramaRanking.hot)
                    Text("Mới nhất").tag(AIDramaRanking.latest)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                .accessibilityIdentifier("aidrama.ranking.mode")
                if state.series.isEmpty {
                    AIDramaCatalogMessage(loading: state.isLoading, message: state.error,
                                          retry: { Task { await store.refresh(query: query) } })
                } else {
                    ForEach(Array(state.series.enumerated()), id: \.element.id) { index, item in
                        AIDramaRankedRow(series: item, rank: index + 1, loading: store.loadingPlaylistID == item.id, open: open)
                        if index < state.series.count - 1 { Divider().overlay(Color.white.opacity(0.04)) }
                    }
                    AIDramaPagingFooter(loading: state.isLoadingMore, canLoadMore: state.canLoadMore,
                                        error: state.error, loadMore: { await store.loadMore(query: query) })
                }
            }.padding(16)
        }
        .accessibilityIdentifier("aidrama.ranking.results")
        .background(AIDramaTheme.background.ignoresSafeArea())
        .refreshable { await store.refresh(query: query) }
        .task(id: query) { await store.load(query: query) }
    }
}

@MainActor
struct AIDramaNewWorksView: View {
    @ObservedObject var store: AIDramaCatalogStore
    let open: (AIDramaSeries) -> Void
    private var state: AIDramaCatalogState { store.snapshot(for: .newWorks) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                AIDramaCatalogGrid(series: state.series, availableWidth: max(1, geometry.size.width - 32),
                                   loadingID: store.loadingPlaylistID, open: open) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Mới ra mắt").font(.title2.bold())
                        Text("Tác phẩm mới trong 7 ngày qua").font(.subheadline).foregroundColor(.secondary)
                        if state.series.isEmpty {
                            AIDramaCatalogMessage(loading: state.isLoading, message: state.error,
                                                  retry: { Task { await store.refresh(query: .newWorks) } })
                        }
                    }
                } footer: {
                    if !state.series.isEmpty {
                        AIDramaPagingFooter(loading: state.isLoadingMore, canLoadMore: state.canLoadMore,
                                            error: state.error, loadMore: { await store.loadMore(query: .newWorks) })
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("aidrama.new.results")
            .refreshable { await store.refresh(query: .newWorks) }
        }
        .background(AIDramaTheme.background.ignoresSafeArea())
        .task { await store.load(query: .newWorks) }
    }
}

@MainActor
struct AIDramaCategoriesView: View {
    @ObservedObject var store: AIDramaCatalogStore
    let open: (AIDramaSeries) -> Void
    @State private var selection = AIDramaCategorySelection()

    private var query: AIDramaCatalogQuery { .categories(selection) }
    private var state: AIDramaCatalogState { store.snapshot(for: query) }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    AIDramaCatalogGrid(series: state.series, availableWidth: max(1, geometry.size.width - 32),
                                       loadingID: store.loadingPlaylistID, open: open) {
                        VStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 0).id("aidrama.categories.top")
                            if let metadata = store.metadata {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(metadata.filterGroups, id: \.kind) { group in
                                        filterRow(group)
                                    }
                                }
                                .padding(.vertical, 4)
                            } else if store.metadataLoading {
                                ProgressView("Đang tải danh mục…").tint(.anpinimeAccent)
                                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                            } else if let error = store.metadataError {
                                Text(error).font(.footnote).foregroundColor(.secondary)
                                Button("Tải lại danh mục") { Task { await store.refreshMetadata() } }
                            }
                            Divider().overlay(Color.white.opacity(0.04))
                            Text("Khám phá phim").font(.headline)
                            if state.series.isEmpty {
                                AIDramaCatalogMessage(loading: state.isLoading, message: state.error,
                                                      retry: { Task { await store.refresh(query: query) } })
                            }
                        }
                    } footer: {
                        if !state.series.isEmpty {
                            AIDramaPagingFooter(loading: state.isLoadingMore, canLoadMore: state.canLoadMore,
                                                error: state.error, loadMore: { await store.loadMore(query: query) })
                        }
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("aidrama.categories.results")
                .refreshable {
                    await store.refreshMetadata()
                    await store.refresh(query: query)
                }
                .onChange(of: selection) { _ in proxy.scrollTo("aidrama.categories.top", anchor: .top) }
            }
        }
        .background(AIDramaTheme.background.ignoresSafeArea())
        .task { await store.loadMetadataIfNeeded() }
        .task(id: query) { await store.load(query: query) }
    }

    private func filterRow(_ group: AIDramaFilterGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(group.options) { option in
                    let selected = isSelected(option, in: group.kind)
                    Button { select(option, in: group.kind) } label: {
                        Text(option.title).font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundColor(selected ? .white : .white.opacity(0.72))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(selected ? Color.anpinimeAccent : AIDramaTheme.surface, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aidrama.filter." + group.kind.rawValue + "." + option.id)
                    .accessibilityLabel(group.title + ", " + option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }


    private func isSelected(_ option: AIDramaFilterOption, in kind: AIDramaFilterGroup.Kind) -> Bool {
        switch kind {
        case .background: return selection.backgroundID == option.categoryID
        case .character: return selection.characterID == option.categoryID
        case .story: return selection.storyID == option.categoryID
        case .releaseTime: return selection.recentDays == (option.recentDays ?? 0)
        }
    }

    private func select(_ option: AIDramaFilterOption, in kind: AIDramaFilterGroup.Kind) {
        switch kind {
        case .background: selection.backgroundID = option.categoryID
        case .character: selection.characterID = option.categoryID
        case .story: selection.storyID = option.categoryID
        case .releaseTime: selection.recentDays = option.recentDays ?? 0
        }
    }
}


enum AIDramaExploreSection: String, CaseIterable {
    case trending = "Thịnh hành", categories = "Danh mục", newWorks = "Mới"
}

@MainActor
struct AIDramaExploreView: View {
    @ObservedObject var store: AIDramaCatalogStore
    @Binding var selection: AIDramaExploreSection
    let open: (AIDramaSeries) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Khám phá", selection: $selection) {
                ForEach(AIDramaExploreSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(12).accessibilityIdentifier("aidrama.explore.mode")
            switch selection {
            case .trending: AIDramaTrendingView(store: store, open: open)
            case .categories: AIDramaCategoriesView(store: store, open: open)
            case .newWorks: AIDramaNewWorksView(store: store, open: open)
            }
        }
        .background(AIDramaTheme.background.ignoresSafeArea())
    }
}
