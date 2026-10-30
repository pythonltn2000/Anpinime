#if DEBUG
import SwiftUI

enum PlaybackSmokeTest {
    static var enabled: Bool {
        animeSmoke || mpvFixture || ProcessInfo.processInfo.arguments.contains("--playback-smoke") || webOnly || movieSource != nil
    }
    static var mpvFixture: Bool { ProcessInfo.processInfo.arguments.contains("--mpv-playback-smoke") && !source2Diagnostic && !animeSmoke }
    static var animeFixture: Bool { ProcessInfo.processInfo.arguments.contains("--anime-provider-smoke") }
    static var liveAnime: Bool { ProcessInfo.processInfo.arguments.contains("--anime-live-smoke") }
    static var animeSmoke: Bool { animeFixture || liveAnime }
    static var source2HLS: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-hls-smoke") }
    static var liveVIP: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-vip-smoke") }
    static var source2Diagnostic: Bool { liveSource2 || source2HLS || liveVIP }
    static var webOnly: Bool { ProcessInfo.processInfo.arguments.contains("--web-playback-smoke") }
    static var providerFixture: Bool { source2HLS || ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") }
    static var movieSource: ContentSource? {
        if ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") || source2Diagnostic { return .phim4k }
        if ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || liveMovie { return .film4k }
        return nil
    }
    static var liveMovie: Bool { ProcessInfo.processInfo.arguments.contains("--film4k-live-smoke") }
    static var liveSource2: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-live-smoke") }
    static var resultName: String? { animeFixture ? "anime-provider" : liveAnime ? "anime-live" : liveMovie ? "film4k-live" : liveSource2 ? "phim4k-live" : liveVIP ? "phim4k-vip" : source2HLS ? "phim4k-hls" : movieSource?.rawValue }
    @MainActor static var animeEpisodeCount = 0
    @MainActor static var selectedAnimeEpisodeNumber: Int?
    @MainActor private static var firstVideoTime: Double?
    @MainActor private static var events: [[String: Any]] = []
    @MainActor static func diagnostic(_ event: String, fields: [String: Any]) {
        guard source2Diagnostic || animeSmoke else { return }
        var entry = fields
        // libmpv warnings may contain upstream or loopback URLs. Never retain
        // signed queries, cookies, tickets or the relay's per-playback IDs.
        for (key, value) in fields {
            if let value = value as? String {
                entry[key] = value.replacingOccurrences(of: #"https?://[^\s\"'<>]+"#, with: "[URL]", options: .regularExpression)
                    .replacingOccurrences(of: #"(?i)(cookie|authorization|api-key|token|x-f4k-pt)\s*[:=][^\r\n]*"#,
                                          with: "$1=[redacted]", options: .regularExpression)
            }
        }
        entry["event"] = event
        if event == "mpv-state", events.last?["event"] as? String == event { events.removeLast() }
        events.append(entry)
        if events.count > 120 { events.removeFirst(events.count - 120) }
        write(["events": events], name: "\(resultName!)-diagnostics")
    }
    @MainActor private static func write(_ result: [String: Any], name: String) {
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("playback-\(name).json"), options: .atomic)
        }
    }
    @MainActor static func record(time: Double, backend: String, size: CGSize, playback: PlaybackState? = nil, videoSize: CGSize = .zero) {
        guard enabled, time > 1, size.width > size.height else { return }
        if animeSmoke {
            guard let playback, playback.playing, videoSize.width > 0, videoSize.height > 0,
                  selectedAnimeEpisodeNumber == 1, animeEpisodeCount >= (animeFixture ? 2 : 1) else { return }
        }
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
            if source2Diagnostic || animeSmoke {
                guard backend == "mpv", playback.playing, videoSize.width > 0, videoSize.height > 0 else { return }
                if firstVideoTime == nil { firstVideoTime = time }
                guard time - firstVideoTime! >= 1 else { return }
                result["sample"] = liveSource2 ? "Phim4K Free1 / thuong-nguyen-do" : liveVIP ? "Core Wakanda / 10403 / 31937" : "Local source-2 HLS through relay"
                result["mediaInfo"] = playback.mediaInfo
                result["videoWidth"] = videoSize.width
                result["videoHeight"] = videoSize.height
                result["advancingVideoVerified"] = true
                if animeSmoke {
                    result["sample"] = liveAnime ? "AnimeVietsub .news / Bleach a5985" : "Local anime metadata → dynamic episodes → player"
                    result["episodeCount"] = animeEpisodeCount
                    result["selectedEpisodeNumber"] = selectedAnimeEpisodeNumber ?? 0
                }
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
        write(result, name: resultName ?? backend)
    }
}

struct PlaybackSmokeView: View {
    private let episode = Episode(title: "Tập kiểm thử", url: URL(string: "http://127.0.0.1:8765/episode.html")!, number: 1, season: "Phần 1")
    var body: some View {
        if PlaybackSmokeTest.animeSmoke { AnimeSmokeView() }
        else if PlaybackSmokeTest.mpvFixture {
            let media = URL(string: "http://127.0.0.1:8765/multitrack.mkv")!
            let item = Episode(title: "MKV · Hai âm thanh · Hai phụ đề", url: media, number: 1, season: "Kiểm thử", source: .kkphim,
                               playback: .directStream(url: media, webURL: nil, isWeb: false, referer: media))
            PlayerView(episode: item, title: "Kiểm thử mpv", artworkURL: nil, episodes: [item])
        } else if let source = PlaybackSmokeTest.movieSource { MovieSmokeView(source: source) }
        else { PlayerView(episode: episode, title: "Kiểm thử phát video", artworkURL: nil, episodes: [episode]) }
    }
}

private struct AnimeSmokeView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var detail: AnimeDetail?
    @State private var error = ""
    var body: some View {
        ZStack {
            if let detail, let episode = detail.episodes.first(where: { $0.number == 1 }) {
                PlayerView(episode: episode, title: detail.title, artworkURL: detail.posterURL, episodes: detail.episodes)
            } else {
                Text(error.isEmpty ? "Kiểm thử Anime: thông tin → tập → video" : error)
                    .task {
                        do {
                            service.selectSource(.anime)
                            let item: Anime
                            if PlaybackSmokeTest.animeFixture {
                                await service.loadHome(forceDomainRefresh: true)
                                guard let first = service.homeSections.flatMap(\.items).first else { throw AnimeServiceError.emptyData }
                                item = first
                            } else {
                                item = Anime(title: "Bleach", url: URL(string: "https://animevietsub.news/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/")!,
                                             imageURL: nil, episodeText: "", quality: "", score: "")
                            }
                            let meta = try await service.detailMetadata(for: item, forceRefresh: true)
                            let episodes = try await service.loadEpisodes(for: item, initialDetail: meta, forceRefresh: true)
                            guard let selected = episodes.first(where: { $0.number == 1 }) else { throw AnimeServiceError.emptyData }
                            PlaybackSmokeTest.animeEpisodeCount = episodes.count
                            PlaybackSmokeTest.selectedAnimeEpisodeNumber = selected.number
                            PlaybackSmokeTest.diagnostic("anime-episodes", fields: ["episodeCount": episodes.count,
                                "selectedEpisodeNumber": selected.number ?? 0, "host": selected.url.host ?? "", "path": selected.url.path])
                            detail = AnimeDetail(title: meta.title, posterURL: meta.posterURL, bannerURL: meta.bannerURL,
                                                 summary: meta.summary, info: meta.info, episodes: episodes)
                        } catch {
                            self.error = error.localizedDescription
                            PlaybackSmokeTest.diagnostic("failure", fields: ["stage": "anime-episodes", "message": self.error])
                        }
                    }
            }
            VerificationGate(browser: service.website)
        }
    }
}

private struct MovieSmokeView: View {
    @EnvironmentObject private var service: AnimeService
    let source: ContentSource
    @State private var detail: AnimeDetail?
    @State private var error = ""
    private var selectedEpisode: Episode? {
        if PlaybackSmokeTest.liveVIP {
            return detail?.episodes.first {
                if case .phim4kCore(_, _, let id) = $0.playback { return id == "31937" }
                return false
            }
        }
        return detail?.episodes.first
    }
    var body: some View {
        Group {
            if let detail, let episode = selectedEpisode {
                PlayerView(episode: episode, title: detail.title, artworkURL: detail.posterURL, episodes: detail.episodes)
            } else {
                Text(error.isEmpty ? "Kiểm thử danh sách → chi tiết → video" : error)
                    .task {
                        do {
                            service.selectSource(source)
                            let items: [Anime]
                            if PlaybackSmokeTest.liveVIP {
                                items = [Anime(title: "Wakanda Forever", url: URL(string: "https://api.phim4k.space/rest-api/v130/single_details?type=movie&id=10403")!,
                                               imageURL: nil, episodeText: "", quality: "", score: "", source: .phim4k)]
                            } else if PlaybackSmokeTest.liveSource2 {
                                // Fixed public Free1 sample. This is never used as a production fallback for VIP.
                                items = try await service.search("Thương Nguyên Đồ", source: .phim4k).filter {
                                    $0.catalogLabel == "Phim4K · Free1" && $0.url.lastPathComponent == "thuong-nguyen-do"
                                }
                            } else {
                                await service.loadHome()
                                items = service.homeSections.flatMap(\.items)
                            }
                            guard let item = items.first else { throw MovieSourceError.unavailable(service.status) }
                            detail = try await service.detail(for: item)
                            if selectedEpisode == nil { throw MovieSourceError.noVideo }
                        } catch {
                            self.error = error.localizedDescription
                            PlaybackSmokeTest.diagnostic("failure", fields: ["stage": "catalog-detail", "message": self.error])
                        }
                    }
            }
        }
    }
}
#endif
