#if DEBUG
import SwiftUI

/// Deterministic simulator-only screenshots; never included in Release IPA.
struct InterfacePreview: View {
    static var mode: String { ProcessInfo.processInfo.arguments.last ?? "loading" }
    private let episodes = (1...24).map { (number: Int) -> Episode in
        Episode(title: "Tập \(number)", url: URL(string: "https://preview.invalid/phim/tap-\(number)")!, number: number, season: "Phần 1")
    }
    var body: some View {
        if Self.mode == "choice" {
            LibraryChoiceView { _ in }
        } else if Self.mode == "intro" {
            IntroVideoView(finished: {}).ignoresSafeArea()
        } else if Self.mode == "switch" {
            LibraryTransition(from: "AppLogo", to: "MovieLogo", intro: false)
        } else if Self.mode == "movie-search-hit" {
            MovieSearchHitPreview()
        } else if Self.mode == "movies" {
            MovieHomePreview()
        } else if Self.mode == "list" {
            LoadingView(text: "Đang tải danh sách anime…")
        } else if Self.mode == "movie-loading" {
            MovieLoaderPreview()
        } else if Self.mode == "app-settings" {
            NavigationView { AppSettingsView() }.tint(.anpinimeAccent)
        } else {
            PlayerView(episode: episodes[3], title: "Hành trình dưới bầu trời sao", artworkURL: nil, episodes: episodes)
        }
    }
}

private struct MovieLoaderPreview: View {
    @EnvironmentObject private var service: AnimeService
    var body: some View {
        LoadingView(text: "Đang tải danh sách phim…").onAppear { service.selectSource(.film4k) }
    }
}

private struct MovieHomePreview: View {
    @EnvironmentObject private var service: AnimeService
    var body: some View {
        NavigationView { HomeView() }
            .task { service.selectSource(.film4k); await service.loadHome() }
    }
}

private struct MovieSearchHitPreview: View {
    @State private var selected = ""
    private let items = (1...3).map { index in
        Anime(title: "Kết quả tìm kiếm \(index)", subtitle: "Bản độc lập \(index)",
              url: URL(string: "https://preview.invalid/movie/search-\(index)")!, imageURL: nil,
              episodeText: "Phim lẻ", quality: "1080p", score: "8.0", source: .phim4k)
    }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text(selected.isEmpty ? "Chưa chọn" : selected)
                    .accessibilityIdentifier("search-hit.selected")
                    .frame(maxWidth: .infinity, minHeight: 36)
                MovieSearchResultsList(items: items) { selected = $0.id }
            }.navigationTitle("Kiểm thử tìm kiếm")
        }.navigationViewStyle(.stack)
    }
}

#endif
