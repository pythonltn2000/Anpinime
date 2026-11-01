import SwiftUI

struct AIDramaTabView: View {
    @ObservedObject var store: AIDramaCatalogStore
    @State private var presentation: PlaylistPresentation?
    @State private var openingTask: Task<Void, Never>?
    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.series.isEmpty && store.isLoading {
                ProgressView("Đang tải Phim AI…").tint(.white)
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if store.series.isEmpty { emptyState }
                        else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                                ForEach(store.series) { series in
                                    Button { open(series) } label: {
                                        seriesCard(series)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("aidrama.series." + series.id)
                                    .disabled(store.loadingPlaylistID == series.id)
                                }
                            }
                        }
                        if let error = store.error, !store.series.isEmpty {
                            Text(error).font(.footnote).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if store.isLoadingMore {
                            ProgressView("Đang tải thêm…").tint(.white)
                        } else if store.canLoadMore {
                            Button("Tải thêm phim") { Task { await store.loadMore() } }
                                .buttonStyle(.bordered).tint(.anpinimeAccent)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
        }
        .foregroundColor(.white)
        .navigationTitle("Phim AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isLoading || store.isLoadingMore)
                    .accessibilityLabel("Làm mới Phim AI")
            }
        }
        .task { await store.loadInitialIfNeeded() }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            store.cancelPlaylistLoading()
        }
        .alert("Chưa mở được phim", isPresented: Binding(get: { store.playlistError != nil }, set: { if !$0 { store.clearPlaylistError() } })) {
            Button("Đóng") { store.clearPlaylistError() }
        } message: { Text(store.playlistError ?? "") }
        .fullScreenCover(item: $presentation) { item in
            AIDramaPlayerView(playlist: item.playlist, provider: store.provider, initialEpisodeID: nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.error == nil ? "film.stack" : "wifi.exclamationmark")
                .font(.system(size: 36)).foregroundColor(.secondary)
            Text(store.error == nil ? "Chưa có phim để hiển thị" : "Chưa tải được Phim AI")
                .font(.headline)
            if let error = store.error {
                Text(error).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button("Thử lại") { Task { await store.refresh() } }
                .buttonStyle(.borderedProminent).tint(.anpinimeAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private func seriesCard(_ series: AIDramaSeries) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.white.opacity(0.07)
                AsyncImage(url: series.coverURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "film").font(.system(size: 28)).foregroundColor(.secondary) }
                }
                if store.loadingPlaylistID == series.id {
                    Color.black.opacity(0.55)
                    VStack(spacing: 9) {
                        ProgressView().tint(.white)
                        Text("Đang tải danh sách tập…").font(.caption).multilineTextAlignment(.center)
                    }.padding(12)
                }
            }
            .aspectRatio(0.68, contentMode: .fit)
            .clipped()
            .cornerRadius(14)
            Text(series.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count = series.episodeCount {
                Text("\(count) tập").font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func open(_ series: AIDramaSeries) {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            guard let playlist = await store.loadPlaylist(for: series), !Task.isCancelled else { return }
            presentation = PlaylistPresentation(playlist: playlist)
        }
    }

    private struct PlaylistPresentation: Identifiable {
        let id = UUID()
        let playlist: AIDramaPlaylist
    }
}
