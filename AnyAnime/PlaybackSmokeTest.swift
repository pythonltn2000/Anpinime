#if DEBUG
import SwiftUI

enum PlaybackSmokeTest {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--playback-smoke") || webOnly || movieSource != nil
    }
    static var webOnly: Bool { ProcessInfo.processInfo.arguments.contains("--web-playback-smoke") }
    static var providerFixture: Bool { ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") }
    static var movieSource: ContentSource? {
        if ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") { return .phim4k }
        if ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || liveMovie { return .film4k }
        return nil
    }
    static var liveMovie: Bool { ProcessInfo.processInfo.arguments.contains("--film4k-live-smoke") }
    static var resultName: String? { liveMovie ? "film4k-live" : movieSource?.rawValue }
    @MainActor static func record(time: Double, backend: String, size: CGSize) {
        guard enabled, time > 1, size.width > size.height else { return }
        let result: [String: Any] = ["time": time, "backend": backend, "landscape": true,
                                     "width": size.width, "height": size.height]
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("playback-\(resultName ?? backend).json"), options: .atomic)
        }
    }
}

struct PlaybackSmokeView: View {
    private let episode = Episode(title: "Tập kiểm thử", url: URL(string: "http://127.0.0.1:8765/episode.html")!, number: 1, season: "Phần 1")
    var body: some View {
        if let source = PlaybackSmokeTest.movieSource { MovieSmokeView(source: source) }
        else { PlayerView(episode: episode, title: "Kiểm thử phát video", artworkURL: nil, episodes: [episode]) }
    }
}

private struct MovieSmokeView: View {
    @EnvironmentObject private var service: AnimeService
    let source: ContentSource
    @State private var detail: AnimeDetail?
    @State private var error = ""
    var body: some View {
        Group {
            if let detail, let episode = detail.episodes.first {
                PlayerView(episode: episode, title: detail.title, artworkURL: detail.posterURL, episodes: detail.episodes)
            } else {
                Text(error.isEmpty ? "Kiểm thử danh sách → chi tiết → video" : error)
                    .task {
                        do {
                            service.selectSource(source)
                            await service.loadHome()
                            guard let item = service.homeSections.first?.items.first else { throw MovieSourceError.unavailable(service.status) }
                            detail = try await service.detail(for: item)
                        } catch { self.error = error.localizedDescription }
                    }
            }
        }
    }
}
#endif
