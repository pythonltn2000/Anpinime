import SwiftUI

/// A complete library with its own navigation and player presentation.
@MainActor
struct AIDramaLibraryView: View {
    @ObservedObject var store: AIDramaCatalogStore
    let onChooseLibrary: () -> Void
    @State private var selectedTab = 0
    @State private var exploreSection = AIDramaExploreSection.trending
    @State private var presentation: PlaylistPresentation?
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            AIDramaTabView(store: store, explore: { section in
                exploreSection = section; selectedTab = 2
            }, open: open)
            .overlay(alignment: .topLeading) { libraryButton.padding(.leading, 16).padding(.top, 4) }
            .tabItem { Label("Trang chủ", systemImage: "house.fill") }.tag(0)

            AIDramaShortsView(provider: store.provider, active: selectedTab == 1 && presentation == nil,
                              openAll: { series, episode, ready in open(series, episode, whenReady: ready) })
                .overlay(alignment: .topLeading) { libraryButton.padding(.leading, 16).padding(.top, 4) }
                .tabItem { Label("Phim ngắn", systemImage: "play.rectangle.fill") }.tag(1)

            NavigationView {
                AIDramaExploreView(store: store, selection: $exploreSection, open: { open($0, nil) })
                    .modifier(AIDramaLibraryNavigation(title: "Khám phá", onChooseLibrary: onChooseLibrary))
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Khám phá", systemImage: "square.grid.2x2.fill") }.tag(2)

            NavigationView {
                AIDramaSettingsView(store: store, onChooseLibrary: onChooseLibrary)
                    .modifier(AIDramaLibraryNavigation(title: "Cài đặt", onChooseLibrary: onChooseLibrary))
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
            .tag(3)
        }
        .tint(.anpinimeAccent)
        .onChange(of: selectedTab) { _ in cancelOpening() }
        .onDisappear { cancelOpening() }
        .alert("Chưa mở được phim", isPresented: Binding(get: { store.playlistError != nil }, set: { if !$0 { store.clearPlaylistError() } })) {
            Button("Đóng") { store.clearPlaylistError() }
        } message: { Text(store.playlistError ?? "") }
        .fullScreenCover(item: $presentation) { item in
            AIDramaPlayerView(playlist: item.playlist, provider: store.provider, initialEpisodeID: item.initialEpisodeID)
        }
    }

    private var libraryButton: some View {
        Button(action: onChooseLibrary) {
            Label("Thư viện", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13).padding(.vertical, 11)
                .foregroundColor(.white).background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("Đổi thư viện").accessibilityIdentifier("aidrama.library.choose")
    }

    private func open(_ series: AIDramaSeries, _ episodeID: String?) {
        open(series, episodeID, whenReady: nil)
    }

    private func open(_ series: AIDramaSeries, _ episodeID: String?, whenReady: (() -> Void)?) {
        openingTask?.cancel()
        openingTask = Task { @MainActor in
            guard let playlist = await store.loadPlaylist(for: series), !Task.isCancelled else { return }
            whenReady?()
            presentation = PlaylistPresentation(playlist: playlist, initialEpisodeID: episodeID)
        }
    }

    private func cancelOpening() {
        openingTask?.cancel()
        openingTask = nil
        store.cancelPlaylistLoading()
    }

    private struct PlaylistPresentation: Identifiable {
        let id = UUID()
        let playlist: AIDramaPlaylist
        let initialEpisodeID: String?
    }
}

private struct AIDramaLibraryNavigation: ViewModifier {
    let title: String
    let onChooseLibrary: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onChooseLibrary) {
                        Label("Thư viện", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Đổi thư viện")
                    .accessibilityIdentifier("aidrama.library.choose")
                }
            }
    }
}

@MainActor
private struct AIDramaSettingsView: View {
    @ObservedObject var store: AIDramaCatalogStore
    @ObservedObject private var history = AIDramaHistoryStore.shared
    let onChooseLibrary: () -> Void
    @State private var confirmingHistoryClear = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles.tv").font(.largeTitle).foregroundColor(.anpinimeAccent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Phim AI").font(.title2.bold())
                        Text("AnPinime").font(.subheadline).foregroundColor(.secondary)
                    }
                }.padding(.vertical, 10)
                Button(action: onChooseLibrary) { Label("Đổi thư viện", systemImage: "square.stack") }
            }
            Section("Dữ liệu") {
                Button("Làm mới danh sách phim") {
                    Task {
                        await store.refresh(query: .home)
                        await store.refresh(query: .trending(.hot))
                        await store.refresh(query: .newWorks)
                        await store.refreshMetadata()
                    }
                }
                HStack {
                    Text("Lịch sử xem")
                    Spacer()
                    Text("\(history.entries.count) phim").foregroundColor(.secondary)
                }
                Button("Xóa lịch sử xem", role: .destructive) { confirmingHistoryClear = true }
                    .disabled(history.entries.isEmpty)
            }
            Section("Giới thiệu") {
                HStack {
                    Text("Phiên bản")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                        .foregroundColor(.secondary)
                }
                Text("Khám phá những câu chuyện AI, theo dõi tập mới và tiếp tục bộ phim đang xem.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .confirmationDialog("Xóa lịch sử xem Phim AI?", isPresented: $confirmingHistoryClear, titleVisibility: .visible) {
            Button("Xóa lịch sử", role: .destructive) { history.clear() }
            Button("Hủy", role: .cancel) { }
        }
    }
}

