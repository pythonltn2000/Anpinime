#if DEBUG
import SwiftUI

enum PlaybackSmokeTest {
    static var enabled: Bool {
        mpvFixture || ProcessInfo.processInfo.arguments.contains("--playback-smoke") || webOnly || movieSource != nil
    }
    static var mpvFixture: Bool { ProcessInfo.processInfo.arguments.contains("--mpv-playback-smoke") }
    static var webOnly: Bool { ProcessInfo.processInfo.arguments.contains("--web-playback-smoke") }
    static var providerFixture: Bool { ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") }
    static var movieSource: ContentSource? {
        if ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") || liveSource2 { return .phim4k }
        if ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || liveMovie { return .film4k }
        return nil
    }
    static var liveMovie: Bool { ProcessInfo.processInfo.arguments.contains("--film4k-live-smoke") }
    static var liveSource2: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-live-smoke") }
    static var resultName: String? { liveMovie ? "film4k-live" : liveSource2 ? "phim4k-live" : movieSource?.rawValue }
    @MainActor static func record(time: Double, backend: String, size: CGSize, playback: PlaybackState? = nil) {
        guard enabled, time > 1, size.width > size.height else { return }
        var result: [String: Any] = ["time": time, "backend": backend, "landscape": true,
                                     "width": size.width, "height": size.height]
        if let playback {
            if mpvFixture {
                guard backend == "mpv", playback.playing, playback.audioTracks.count == 2, playback.subtitleTracks.count >= 3 else { return }
                let audio = playback.audioTracks.last!, subtitles = playback.subtitleTracks.filter { $0.id != "off" }
                playback.chooseOption?("audio", audio.id)
                playback.chooseOption?("subtitles", subtitles[0].id)
                playback.chooseOption?("secondarySubtitles", subtitles[1].id)
                guard playback.audioTrack == audio.id, playback.subtitleTrack == subtitles[0].id,
                      playback.secondarySubtitleTrack == subtitles[1].id else { return }
                result["mkvAudioAndDualSubtitlesVerified"] = true
                result["autoplayVerified"] = true
            }
            result["audioChoices"] = playback.audioTracks.count
            result["subtitleChoices"] = playback.subtitleTracks.count
            result["qualityChoices"] = playback.qualities.count
            if providerFixture, movieSource == .film4k {
                guard playback.subtitleTracks.count >= 3, playback.qualities.count >= 2,
                      let last = playback.subtitleTracks.last, let quality = playback.qualities.last else { return }
                playback.chooseOption?("subtitles", last.id)
                guard playback.subtitleTrack == last.id else { return }
                playback.chooseOption?("subtitles", "stale-option-from-old-video")
                guard playback.subtitleTrack == last.id else { return }
                playback.chooseOption?("subtitles", "off")
                guard playback.subtitleTrack == "off" else { return }
                playback.chooseOption?("quality", quality.id)
                guard playback.quality == quality.id else { return }
                result["stableSelectionAndOffVerified"] = true
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("playback-\(resultName ?? backend).json"), options: .atomic)
        }
    }
}

struct PlaybackSmokeView: View {
    private let episode = Episode(title: "Tập kiểm thử", url: URL(string: "http://127.0.0.1:8765/episode.html")!, number: 1, season: "Phần 1")
    var body: some View {
        if PlaybackSmokeTest.mpvFixture {
            let media = URL(string: "http://127.0.0.1:8765/multitrack.mkv")!
            let item = Episode(title: "MKV · Hai âm thanh · Hai phụ đề", url: media, number: 1, season: "Kiểm thử", source: .kkphim,
                               playback: .directStream(url: media, webURL: nil, isWeb: false, referer: media))
            PlayerView(episode: item, title: "Kiểm thử mpv", artworkURL: nil, episodes: [item])
        } else if let source = PlaybackSmokeTest.movieSource { MovieSmokeView(source: source) }
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
                            let items = service.homeSections.flatMap(\.items)
                            // An explicit repeatable live sample, not a silent fallback in production.
                            let sample = PlaybackSmokeTest.liveSource2 ? items.first(where: { $0.url.lastPathComponent == "thuong-nguyen-do" }) : items.first
                            guard let item = sample else { throw MovieSourceError.unavailable(service.status) }
                            detail = try await service.detail(for: item)
                        } catch { self.error = error.localizedDescription }
                    }
            }
        }
    }
}
#endif
