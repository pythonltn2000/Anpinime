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
    private static func smokeArgument(_ name: String, fallback: String, pattern: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name) else { return fallback }
        guard index + 1 < args.count, args[index + 1].range(of: pattern, options: .regularExpression) != nil else { return "" }
        return args[index + 1]
    }
    static var liveVIPMovieID: String { smokeArgument("--phim4k-core-id", fallback: "10403", pattern: "^[0-9]{1,20}$") }
    static var liveVIPServerID: String { smokeArgument("--phim4k-server-id", fallback: "31937", pattern: "^[0-9]{1,20}$") }
    static var liveVIPResultName: String { smokeArgument("--phim4k-result", fallback: "phim4k-vip", pattern: "^[a-z0-9-]{1,80}$") }
    static var gatewaySmoke: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-gateway-smoke") }
    static var source2Diagnostic: Bool { liveSource2 || source2HLS || liveVIP || gatewaySmoke }
    static var webOnly: Bool { ProcessInfo.processInfo.arguments.contains("--web-playback-smoke") }
    static var providerFixture: Bool { source2HLS || ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") }
    static var movieSource: ContentSource? {
        if ProcessInfo.processInfo.arguments.contains("--phim4k-provider-smoke") || source2Diagnostic { return .phim4k }
        if ProcessInfo.processInfo.arguments.contains("--movie-provider-smoke") || liveMovie { return .film4k }
        return nil
    }
    static var liveMovie: Bool { ProcessInfo.processInfo.arguments.contains("--film4k-live-smoke") }
    static var liveSource2: Bool { ProcessInfo.processInfo.arguments.contains("--phim4k-live-smoke") }
    static var resultName: String? {
        if animeFixture { return "anime-provider" }
        if liveAnime { return "anime-live" }
        if liveMovie { return "film4k-live" }
        if liveSource2 { return "phim4k-live" }
        if liveVIP { return liveVIPResultName }
        if gatewaySmoke { return "phim4k-gateway" }
        if source2HLS { return "phim4k-hls" }
        return movieSource?.rawValue
    }
    @MainActor static var animeEpisodeCount = 0
    @MainActor static var selectedAnimeEpisodeNumber: Int?
    @MainActor static var cancelledAnimeLoadVerified = false
    @MainActor static var replayedCoreServerIDs: [String] = []
    @MainActor static var liveGatewayPrepared = false
    @MainActor private static var firstVideoTime: Double?
    @MainActor private static var events: [[String: Any]] = []
    @MainActor private static var diagnosticStartedAt: TimeInterval?
    @MainActor private static var firstDecodedVideoRecorded = false
    @MainActor private static var fileLoadedRecorded = false
    @MainActor private static var firstDecodedVideoElapsed: TimeInterval?
    @MainActor private static var fileLoadedElapsed: TimeInterval?
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
        let now = ProcessInfo.processInfo.systemUptime
        if diagnosticStartedAt == nil { diagnosticStartedAt = now }
        entry["elapsedSeconds"] = now - diagnosticStartedAt!
        entry["event"] = event
        if source2Diagnostic, event == "mpv-state" {
            // Preserve startup milestones before later snapshots are coalesced.
            if !fileLoadedRecorded, fields["loaded"] as? Bool == true {
                fileLoadedRecorded = true
                fileLoadedElapsed = now - diagnosticStartedAt!
                var milestone = entry
                milestone["event"] = "source2-file-loaded"
                events.append(milestone)
            }
            if !firstDecodedVideoRecorded, fields["playing"] as? Bool == true,
               (fields["time"] as? Double ?? 0) > 0,
               (fields["videoWidth"] as? Double ?? 0) > 0,
               (fields["videoHeight"] as? Double ?? 0) > 0 {
                firstDecodedVideoRecorded = true
                firstDecodedVideoElapsed = now - diagnosticStartedAt!
                var milestone = entry
                milestone["event"] = "source2-first-decoded-video"
                events.append(milestone)
            }
        }
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
                guard playback.pipSmokeFrames >= 8, playback.pipSmokeSeekPauseRestored else { return }
                result["pipSoftwareVisibleFrames"] = playback.pipSmokeFrames
                result["pipSeekPauseRestoreVerified"] = playback.pipSmokeSeekPauseRestored
                result["pipSystemWindowOnDeviceVerified"] = false
                result["mkvAudioAndDualSubtitlesVerified"] = true
                result["autoplayVerified"] = true
            }
            if source2Diagnostic || animeSmoke {
                guard backend == "mpv" || (animeSmoke && backend == "web"), playback.playing, videoSize.width > 0, videoSize.height > 0 else { return }
                if firstVideoTime == nil { firstVideoTime = time }
                guard time - firstVideoTime! >= 1 else { return }
                result["sample"] = liveSource2 ? "Phim4K Free1 / thuong-nguyen-do" : liveVIP ? "Core Wakanda / 10403 / 31937" : "Local source-2 HLS through relay"
                result["mediaInfo"] = playback.mediaInfo
                result["videoWidth"] = videoSize.width
                result["videoHeight"] = videoSize.height
                result["advancingVideoVerified"] = true
                if source2Diagnostic {
                    result["videoCodec"] = playback.mediaInfo.components(separatedBy: " · ").dropFirst().first ?? ""
                    if let elapsed = firstDecodedVideoElapsed { result["firstDecodedVideoElapsedSeconds"] = elapsed }
                    if let elapsed = fileLoadedElapsed { result["fileLoadedElapsedSeconds"] = elapsed }
                    result["startupTimingResolutionSeconds"] = 0.25
                }
                if liveVIP {
                    result["sample"] = "Core movie \(liveVIPMovieID) / server \(liveVIPServerID)"
                    result["selectedCoreMovieID"] = liveVIPMovieID
                    result["selectedServerID"] = liveVIPServerID
                    result["coreMetadataReplayed"] = false
                    result["fullCoreLive"] = true
                }
                if gatewaySmoke {
                    guard liveGatewayPrepared,
                          Set(replayedCoreServerIDs) == Set(["31937", "33090", "27463", "31938", "31939"]) else { return }
                    result["sample"] = "Replayed Core metadata / Wakanda 10403 / server 31937 / live gateway and media"
                    result["coreMetadataReplayed"] = true
                    result["liveGateway"] = true
                    result["metadataServerCount"] = replayedCoreServerIDs.count
                    result["selectedServerID"] = "31937"
                    result["replayedCoreServerIDs"] = replayedCoreServerIDs
                }
                if animeSmoke {
                    result["sample"] = liveAnime ? "AnimeVietsub .news / Bleach a5985" : "Local anime metadata → dynamic episodes → player"
                    result["episodeCount"] = animeEpisodeCount
                    result["selectedEpisodeNumber"] = selectedAnimeEpisodeNumber ?? 0
                    if animeFixture {
                        guard cancelledAnimeLoadVerified else { return }
                        result["cancelledEpisodeLoadVerified"] = true
                    }
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
                            if PlaybackSmokeTest.animeFixture {
                                let cancelledLoad = Task { try await service.loadEpisodes(for: item, initialDetail: meta, forceRefresh: true) }
                                try await Task.sleep(nanoseconds: 500_000_000)
                                cancelledLoad.cancel()
                                do {
                                    _ = try await cancelledLoad.value
                                    throw AnimeServiceError.emptyData
                                } catch is CancellationError { }
                                guard service.cachedDetail(for: item.id) == nil else { throw AnimeServiceError.emptyData }
                                PlaybackSmokeTest.cancelledAnimeLoadVerified = true
                                PlaybackSmokeTest.diagnostic("cancelled-episode-load", fields: ["partialCacheAbsent": true])
                            }
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
                if case .phim4kCore(_, _, let id) = $0.playback { return id == PlaybackSmokeTest.liveVIPServerID }
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
                            if PlaybackSmokeTest.gatewaySmoke {
                                detail = try await prepareGatewayPlayback()
                                return
                            }
                            service.selectSource(source)
                            let items: [Anime]
                            if PlaybackSmokeTest.liveVIP {
                                let movieID = PlaybackSmokeTest.liveVIPMovieID
                                let serverID = PlaybackSmokeTest.liveVIPServerID
                                guard !movieID.isEmpty, !serverID.isEmpty, !PlaybackSmokeTest.liveVIPResultName.isEmpty else {
                                    throw MovieSourceError.invalidData
                                }
                                PlaybackSmokeTest.diagnostic("vip-smoke-start", fields: ["selectedCoreMovieID": movieID,
                                    "selectedServerID": serverID, "coreMetadataReplayed": false])
                                let url = MovieCatalog.route(Phim4KCatalog.prefix + "single_details", base: URL(string: "https://api.phim4k.space")!,
                                    query: [.init(name: "type", value: "movie"), .init(name: "id", value: movieID)])
                                items = [Anime(title: "Core movie " + movieID, url: url,
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

    /// Replays only the captured Core metadata. The authenticated directory,
    /// production provider/resolver, returned URL and native playback stay live.
    @MainActor private func prepareGatewayPlayback() async throws -> AnimeDetail {
        let namespace = "AnPinime.GatewaySmoke." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: namespace) else { throw MovieSourceError.invalidData }
        defer { defaults.removePersistentDomain(forName: namespace) }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        PlaybackSmokeTest.diagnostic("gateway-smoke-start", fields: ["coreMetadataReplayed": true,
            "selectedServerID": "31937"])
        await MovieSourceDirectory.refresh(session: session, defaults: defaults)
        try Task.checkCancellation()
        guard let gateway = MovieSourceDirectory.cdnGateway(defaults: defaults) else {
            throw Phim4KVIPResolver.Failure.missingGateway
        }
        PlaybackSmokeTest.diagnostic("gateway-smoke-scope", fields: ["coreMetadataReplayed": true,
            "gatewayDirectoryAuthenticated": true, "gatewayHost": gateway.host ?? "", "selectedServerID": "31937"])
        let localCore = URL(string: "http://127.0.0.1:8767")!
        let detailURL = MovieCatalog.route(Phim4KCatalog.prefix + "single_details", base: localCore,
            query: [.init(name: "type", value: "movie"), .init(name: "id", value: "10403")])
        let item = Anime(title: "Wakanda Forever", url: detailURL, imageURL: nil,
                         episodeText: "", quality: "", score: "", source: .phim4k)
        let configuration = Phim4KProvider.Configuration(core: .init(baseURL: localCore, apiKey: ""),
                                                        catalogs: [], gateway: gateway)
        let provider = Phim4KProvider(session: session, configuration: configuration)
        let captured = try await provider.detail(item)
        let serverIDs = captured.episodes.compactMap { episode -> String? in
            if case .phim4kCore(_, nil, let id) = episode.playback { return id }
            return nil
        }
        guard serverIDs.count == 5,
              Set(serverIDs) == Set(["31937", "33090", "27463", "31938", "31939"]),
              let selected = captured.episodes.first(where: {
                  if case .phim4kCore(_, nil, let id) = $0.playback { return id == "31937" }
                  return false
              }) else { throw MovieSourceError.invalidData }
        let resolved = try await provider.resolveCore(detailURL: detailURL, seasonID: nil, episodeID: "31937")
        try Task.checkCancellation()
        guard !resolved.isWeb, !Phim4KVIPResolver.requiresGateway(resolved.url) else {
            throw Phim4KVIPResolver.Failure.invalidMediaURL
        }
        PlaybackSmokeTest.replayedCoreServerIDs = serverIDs
        PlaybackSmokeTest.liveGatewayPrepared = true
        PlaybackSmokeTest.diagnostic("gateway-smoke-resolved", fields: ["coreMetadataReplayed": true,
            "liveGateway": true, "metadataServerCount": serverIDs.count,
            "selectedServerID": "31937", "mediaHost": resolved.url.host ?? ""])
        let direct = Episode(title: selected.title, url: detailURL, number: selected.number,
                             season: selected.season, qualityBadge: selected.qualityBadge, source: .phim4k,
                             playback: .directStream(url: resolved.url, webURL: nil, isWeb: false, referer: nil))
        return AnimeDetail(title: captured.title + " · Core metadata replay", posterURL: nil,
                           bannerURL: nil, summary: "", info: "", episodes: [direct])
    }
}
#endif
