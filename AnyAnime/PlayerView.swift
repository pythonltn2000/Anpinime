import SwiftUI
import WebKit
import AVKit

struct PlayerControllerView: UIViewControllerRepresentable {
    let episode: Episode
    let service: AnimeService
    let playback: PlaybackState

    func makeUIViewController(context: Context) -> AnimePlayerViewController {
        AnimePlayerViewController(episode: episode, service: service, playback: playback)
    }

    func updateUIViewController(_ uiViewController: AnimePlayerViewController, context: Context) { }
    static func dismantleUIViewController(_ uiViewController: AnimePlayerViewController, coordinator: ()) {
        uiViewController.shutdown()
    }
}

@MainActor
final class AnimePlayerViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private static let episodeSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    private let episodeURL: URL
    private let baseURL: URL
    private let episode: Episode
    private let service: AnimeService
    private let playback: PlaybackState
    private var active = true
    private var requestTask: Task<Void, Never>?
    private var nativeTimer: Timer?
    private var endedObserver: NSObjectProtocol?
    private var webEnded = false
    private var verificationTimer: Timer?
    private var nativeSource: URL?
    private var failedNativeSources = Set<URL>()
    private var nativeStartedAt = Date()
    private var preparingNative = false
    private var directWebView: WKWebView?
    private var fallbackWebView: WKWebView?
    private var playerController: AVPlayerViewController?
    private var fallbackTimer: Timer?
    private var revealTimer: Timer?
    private var fallbackLoadedURL: URL?
    private let loadingLabel = UILabel()
    private var providerHeaders: [String: String] = [:]
    private var providerWebURL: URL?
    private var providerRefreshAttempted = false
    private var resumeAfterRefresh = 0.0
    private var mediaTracksLoaded = false
    private var filmRelay: FilmMediaRelay?
    private var trackTask: Task<Void, Never>?
    private var audioOptions: [String: AVMediaSelectionOption] = [:]
    private var subtitleOptions: [String: AVMediaSelectionOption] = [:]

    init(episode: Episode, service: AnimeService, playback: PlaybackState) {
        self.episode = episode
        self.service = service
        self.episodeURL = episode.url
        self.baseURL = service.baseURL
        self.playback = playback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        loadingLabel.text = "Đang tải thông tin video…"
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.isHidden = true
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        playback.command = { [weak self] name, value in self?.perform(name, value: value) }
        playback.chooseOption = { [weak self] kind, id in self?.chooseOption(kind, id: id) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            Task { @MainActor in
                if InterfacePreview.mode != "loading" {
                    self.playback.loading = false
                    self.playback.duration = 1440
                    self.playback.currentTime = 325
                    self.playback.playing = true
                    self.playback.audioTracks = [.init(id: "vi", title: "Tiếng Việt"), .init(id: "en", title: "English · Stereo")]
                    self.playback.audioTrack = "vi"
                    self.playback.subtitleTracks = [.init(id: "off", title: "Tắt phụ đề")] + (1...35).map { .init(id: "subtitle-\($0)", title: "Phụ đề ngôn ngữ \($0)") }
                    self.playback.subtitleTrack = "subtitle-12"
                    self.playback.qualities = [.automatic, .init(id: "1080", title: "1080p", bandwidth: 4000000, width: 1920, height: 1080)]
                }
            }
            return
        }
        #endif
        if episode.source.isMovie { attemptProviderPlayer() }
        else { attemptDirectPlayer() }
    }

    func shutdown() {
        guard active else { return }
        active = false
        requestTask?.cancel()
        filmRelay?.stop(); filmRelay = nil
        trackTask?.cancel()
        fallbackTimer?.invalidate()
        revealTimer?.invalidate()
        nativeTimer?.invalidate()
        verificationTimer?.invalidate()
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }
        playerController?.player?.pause()
        playerController?.player?.replaceCurrentItem(with: nil)
        for webView in [directWebView, fallbackWebView] {
            webView?.evaluateJavaScript("document.querySelectorAll('video').forEach(v=>v.pause())")
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            ["videoFound", "iframeFound", "playerReady", "playerError", "mediaState"].forEach {
                webView?.configuration.userContentController.removeScriptMessageHandler(forName: $0)
            }
        }
    }

    private func perform(_ name: String, value: Double) {
        guard active else { return }
        if let player = playerController?.player {
            switch name {
            case "play": player.playImmediately(atRate: Float(playback.rate))
            case "pause": player.pause()
            case "seek":
                let target = min(max(0, value), max(0, playback.duration))
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            case "rate": if player.rate != 0 { player.rate = Float(value) }
            case "volume": player.volume = Float(value)
            case "fit": playerController?.videoGravity = value == 1 ? .resizeAspectFill : .resizeAspect
            case "subtitleSize", "subtitleBackground": applySubtitleStyle()
            default: break
            }
        } else {
            let payload: [String: Any] = ["type": "AnPinimeCommand", "name": name, "value": value]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            fallbackWebView?.evaluateJavaScript("window.postMessage(\(json),'*')")
        }
    }

    private func attemptProviderPlayer(refresh: Bool = false) {
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await self.service.resolvePlayback(self.episode, refresh: refresh)
                try Task.checkCancellation()
                guard self.active else { return }
                self.providerHeaders = resolved.headers
                self.providerWebURL = resolved.webURL
                if resolved.isWeb { self.startFallback(url: resolved.url) }
                else if self.shouldUseMediaRelay(for: resolved.url) {
                    self.filmRelay?.stop()
                    let relay = FilmMediaRelay(origin: self.baseURL, headers: resolved.headers)
                    relay.onQualities = { [weak self] options in
                        guard let self, self.active else { return }
                        if self.playback.qualities != options { self.playback.qualities = options }
                    }
                    self.filmRelay = relay
                    let localURL = try await relay.start(resolved.url)
                    try Task.checkCancellation()
                    self.showNativePlayer(url: localURL)
                } else { self.showNativePlayer(url: resolved.url) }
            } catch {
                guard self.active, !Task.isCancelled else { return }
                if refresh, let url = self.providerWebURL { self.startFallback(url: url) }
                else { self.playback.error = error.localizedDescription }
            }
        }
    }

    private func attemptDirectPlayer() {
        var request = URLRequest(url: episodeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await Self.episodeSession.data(for: request)
                guard self.active, !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                      let html = String(data: data, encoding: .utf8),
                      let values = HTMLParser.playerParameters(from: html) else {
                    self.startFallback()
                    return
                }
                self.startDirect(parameters: PlayerParameters(filmID: values.filmID, hash: values.hash))
            } catch {
                guard self.active, !Task.isCancelled else { return }
                self.startFallback()
            }
        }
    }

    private func startDirect(parameters: PlayerParameters) {
        guard active else { return }
        loadingLabel.text = "Đang giải mã luồng phát…"
        let configuration = playerConfiguration(injectFallbackScript: false)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = AnimeService.userAgent
        webView.isHidden = true
        view.addSubview(webView)
        directWebView = webView

        let hash64 = Data(parameters.hash.utf8).base64EncodedString()
        let film64 = Data(parameters.filmID.utf8).base64EncodedString()
        let key64 = Data("dm_thang_suc_vat_get_link_an_dbt".utf8).base64EncodedString()
        let html = directPlayerHTML(hash64: hash64, film64: film64, key64: key64)
        webView.loadHTMLString(html, baseURL: baseURL)

        fallbackTimer?.invalidate()
        // The direct endpoint normally answers in a few seconds. Move on quickly when
        // its player contract has changed instead of keeping the viewer on the loader.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 9, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.startFallback() }
        }
    }

    private func startFallback(url requestedURL: URL? = nil) {
        guard active, playerController == nil else { return }
        fallbackTimer?.invalidate()
        ["videoFound", "iframeFound", "playerReady", "playerError", "mediaState"].forEach {
            directWebView?.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
        directWebView?.stopLoading()
        directWebView?.removeFromSuperview()
        directWebView = nil

        let targetURL = requestedURL ?? providerWebURL ?? episodeURL
        if let webView = fallbackWebView {
            guard fallbackLoadedURL?.absoluteString != targetURL.absoluteString else { return }
            fallbackLoadedURL = targetURL
            loadingLabel.text = "Đang mở trình phát toàn màn hình…"
            webView.isHidden = true
            loadWebPlayer(webView, url: targetURL)
            scheduleFallbackReveal(for: webView)
            return
        }

        loadingLabel.text = "Đang tải trình phát website…"
        let configuration = playerConfiguration(injectFallbackScript: true)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = AnimeService.userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        view.insertSubview(webView, belowSubview: loadingLabel)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        fallbackWebView = webView
        verificationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectVerification() }
        }
        fallbackLoadedURL = targetURL
        loadWebPlayer(webView, url: targetURL)
        scheduleFallbackReveal(for: webView)
    }

    private func loadWebPlayer(_ webView: WKWebView, url: URL) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            for cookie in HTTPCookieStorage.shared.cookies ?? [] {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
            guard self.active, self.fallbackLoadedURL == url else { return }
            webView.load(self.playerRequest(for: url))
        }
    }

    private func playerRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(episodeURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    private func scheduleFallbackReveal(for webView: WKWebView) {
        revealTimer?.invalidate()
        revealTimer = Timer.scheduledTimer(withTimeInterval: 35, repeats: false) { [weak self, weak webView] _ in
            Task { @MainActor in
                guard let self, let webView, self.active, webView === self.fallbackWebView,
                      self.playback.loading, !self.playback.verification else { return }
                self.playback.error = "Chưa thể phát tập này. Hãy thử tải lại luồng phát."
            }
        }
    }

    private func playerConfiguration(injectFallbackScript: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        ["videoFound", "iframeFound", "playerReady", "playerError", "mediaState"].forEach {
            configuration.userContentController.add(self, name: $0)
        }
        if injectFallbackScript {
            configuration.userContentController.addUserScript(WKUserScript(
                source: fallbackJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        return configuration
    }

    private func shouldUseMediaRelay(for url: URL) -> Bool {
        guard episode.source.isMovie else { return false }
        let ext = url.pathExtension.lowercased()
        if case .film4k = episode.playback {
            return ext == "m3u8" || url.path.hasSuffix("/stream/hls")
        }
        // For Nguồn phim 2 (.phim4k), standard .m3u8/.mp4 streams play directly from CDN via HTTP/2 for maximum speed.
        // Extensionless HLS endpoints (like /api/content/stream/hls) use FilmMediaRelay so AVPlayer receives a .m3u8 URL.
        return url.path.contains("/stream/hls") || (ext.isEmpty && url.path.lowercased().contains("hls"))
    }

    private func showNativePlayer(url: URL, referer: URL? = nil) {
        guard active, playerController == nil else { return }
        fallbackTimer?.invalidate()
        nativeSource = url
        nativeStartedAt = Date()
        playback.loading = true
        playback.error = nil
        var headers = ["User-Agent": AnimeService.userAgent, "Referer": (referer ?? episodeURL).absoluteString]
        if episode.source.isMovie {
            headers.merge(providerHeaders) { _, provider in provider }
            if let referer {
                headers["Referer"] = referer.absoluteString
                if let scheme = referer.scheme, let host = referer.host { headers["Origin"] = scheme + "://" + host }
            }
            // A provider's session ticket must never be forwarded to a third-party iframe/CDN.
            if url.host != baseURL.host { headers.removeValue(forKey: "X-F4K-PT") }
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers,
                                                  AVURLAssetHTTPCookiesKey: cookies])
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable", "availableMediaCharacteristicsWithMediaSelectionOptions"])
        // Fast start for heavy high-bitrate/4K streams: start decoding with a small initial forward buffer,
        // then expand buffer once playback is active.
        playerItem.preferredForwardBufferDuration = 4.0
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(preferredLanguages: ["vi", "en"], preferredMediaCharacteristics: nil), forMediaCharacteristic: .audible)
        mediaTracksLoaded = false
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = playback.fill ? .resizeAspectFill : .resizeAspect
        player.volume = Float(playback.volume)
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(controller.view, at: 0)
        controller.didMove(toParent: self)
        playerController = controller
        applySubtitleStyle()
        if filmRelay == nil, url.pathExtension.lowercased() == "m3u8" {
            trackTask?.cancel()
            trackTask = Task { [weak self] in
                var request = URLRequest(url: url)
                headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                guard let (data, _) = try? await Self.episodeSession.data(for: request),
                      let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U"),
                      let self, self.active, !Task.isCancelled, self.playerController?.player === player else { return }
                self.playback.qualities = FilmMediaTransform.qualities(text)
            }
        }
        loadingLabel.isHidden = true
        revealTimer?.invalidate()
        directWebView?.removeFromSuperview()
        // Do not let a hidden HTML video keep downloading alongside AVPlayer.
        fallbackWebView?.evaluateJavaScript("window.postMessage({type:'AnPinimeCommand',name:'pause',value:0},'*')")
        fallbackWebView?.isHidden = true
        player.playImmediately(atRate: Float(playback.rate))
        endedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.playback.playing = false
                self.playback.endCount += 1
            }
        }
        nativeTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateNativeState() }
        }
    }

    private func updateNativeState() {
        guard active, let player = playerController?.player, let item = player.currentItem else { return }
        if item.status == .failed || (playback.loading && Date().timeIntervalSince(nativeStartedAt) > 25) {
            if let nativeSource { failedNativeSources.insert(nativeSource) }
            nativeTimer?.invalidate()
            if let endedObserver { NotificationCenter.default.removeObserver(endedObserver); self.endedObserver = nil }
            player.pause()
            playerController?.willMove(toParent: nil)
            playerController?.view.removeFromSuperview()
            playerController?.removeFromParent()
            playerController = nil
            playback.loading = true
            playback.buffering = false
            playback.audioTracks = []; playback.subtitleTracks = []
            if episode.source.isMovie && !providerRefreshAttempted {
                providerRefreshAttempted = true
                resumeAfterRefresh = playback.currentTime
                attemptProviderPlayer(refresh: true)
                return
            }
            if let webView = fallbackWebView {
                webView.isHidden = false
                perform("play", value: 0)
                scheduleFallbackReveal(for: webView)
            } else if !episode.source.isMovie || providerWebURL != nil { startFallback() }
            else { playback.error = "Không phát được định dạng video này từ nguồn đã chọn." }
            return
        }
        if item.status == .readyToPlay && !mediaTracksLoaded {
            mediaTracksLoaded = true
            loadMediaTracks(item)
            if resumeAfterRefresh > 0 {
                player.seek(to: CMTime(seconds: resumeAfterRefresh, preferredTimescale: 600))
                resumeAfterRefresh = 0
            }
        }
        let duration = item.duration.seconds
        let time = player.currentTime().seconds
        if duration.isFinite { playback.duration = max(0, duration) }
        if time.isFinite { playback.currentTime = max(0, time) }
        playback.playing = player.timeControlStatus == .playing
        playback.buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if player.timeControlStatus == .playing || time > 0 {
            playback.loading = false; playback.error = nil
            if time > 2.5, item.preferredForwardBufferDuration < 12.0 {
                item.preferredForwardBufferDuration = 16.0
                player.automaticallyWaitsToMinimizeStalling = true
            }
        }
        #if DEBUG
        PlaybackSmokeTest.record(time: time, backend: "native", size: view.bounds.size, playback: playback)
        #endif
    }

    private func loadMediaTracks(_ item: AVPlayerItem) {
        let generation = UUID().uuidString
        audioOptions = [:]; subtitleOptions = [:]
        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            let selected = item.currentMediaSelection.selectedMediaOption(in: group)
            playback.audioTracks = group.options.enumerated().map { index, option in
                let id = "\(generation)-audio-\(index)"
                audioOptions[id] = option
                if option == selected { playback.audioTrack = id }
                return PlaybackChoice(id: id, title: option.displayName)
            }
        }
        if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            let selected = item.currentMediaSelection.selectedMediaOption(in: group)
            playback.subtitleTrack = "off"
            playback.subtitleTracks = [.init(id: "off", title: "Tắt phụ đề")] + group.options.enumerated().map { index, option in
                let id = "\(generation)-subtitle-\(index)"
                subtitleOptions[id] = option
                if option == selected { playback.subtitleTrack = id }
                return PlaybackChoice(id: id, title: option.displayName)
            }
        }
    }

    private func chooseOption(_ kind: String, id: String) {
        guard active, let item = playerController?.player?.currentItem else { return }
        if kind == "quality", let option = playback.qualities.first(where: { $0.id == id }) {
            item.preferredPeakBitRate = option.bandwidth
            item.preferredMaximumResolution = CGSize(width: option.width, height: option.height)
            playback.quality = id
            return
        }
        let characteristic: AVMediaCharacteristic = kind == "audio" ? .audible : .legible
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }
        if kind == "subtitles", id == "off" { item.select(nil, in: group); playback.subtitleTrack = "off" }
        else if kind == "subtitles", let option = subtitleOptions[id], group.options.contains(option) {
            item.select(option, in: group); playback.subtitleTrack = id
        } else if kind == "audio", let option = audioOptions[id], group.options.contains(option) {
            item.select(option, in: group); playback.audioTrack = id
        }
    }

    private func applySubtitleStyle() {
        let attributes: [String: Any] = [
            kCMTextMarkupAttribute_RelativeFontSize as String: playback.subtitleSize,
            kCMTextMarkupAttribute_BackgroundColorARGB as String: [playback.subtitleBackground ? 0.7 : 0.0, 0.0, 0.0, 0.0]
        ]
        if let rule = AVTextStyleRule(textMarkupAttributes: attributes) { playerController?.player?.currentItem?.textStyleRules = [rule] }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard active else { return }
        switch message.name {
        case "videoFound":
            #if DEBUG
            if PlaybackSmokeTest.webOnly { return }
            #endif
            let details = message.body as? [String: String]
            guard let value = message.body as? String ?? details?["url"], let url = resolvedURL(from: value),
                  !failedNativeSources.contains(url), playerController == nil, !preparingNative else { return }
            let referer = details?["referer"].flatMap(URL.init(string:)) ?? message.frameInfo.request.url ?? episodeURL
            preparingNative = true
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, self.active else { return }
                for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
                self.preparingNative = false
                self.showNativePlayer(url: url, referer: referer)
            }
        case "iframeFound":
            guard let value = message.body as? String, let url = resolvedURL(from: value) else { return }
            startFallback(url: url)
        case "playerReady":
            guard playerController == nil else { return }
            fallbackWebView?.isHidden = false
        case "mediaState":
            guard playerController == nil, let state = message.body as? [String: Any] else { return }
            if let time = state["time"] as? Double, time.isFinite { playback.currentTime = max(0, time) }
            if let duration = state["duration"] as? Double, duration.isFinite { playback.duration = max(0, duration) }
            playback.playing = (state["paused"] as? Bool) == false && (state["ready"] as? Bool) == true
            playback.buffering = (state["buffering"] as? Bool) == true
            if (state["ready"] as? Bool) == true {
                let wasLoading = playback.loading
                playback.loading = false; playback.verification = false; playback.error = nil
                revealTimer?.invalidate()
                fallbackWebView?.isHidden = false
                if wasLoading {
                    perform("rate", value: playback.rate)
                    perform("volume", value: playback.volume)
                    perform("fit", value: playback.fill ? 1 : 0)
                }
            }
            let ended = (state["ended"] as? Bool) == true
            if ended && !webEnded { playback.endCount += 1 }
            webEnded = ended
            #if DEBUG
            PlaybackSmokeTest.record(time: playback.currentTime, backend: "web", size: view.bounds.size)
            #endif
        case "playerError":
            if let detail = message.body as? String { print("[AnPinime Player] \(detail)") }
            startFallback()
        default:
            break
        }
    }

    private func resolvedURL(from value: String) -> URL? {
        let cleaned = value
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned, relativeTo: fallbackLoadedURL ?? episodeURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === fallbackWebView else { return }
        webView.evaluateJavaScript("window.__anyanimeFocusPlayer && window.__anyanimeFocusPlayer()")
        inspectVerification()
    }

    private func inspectVerification() {
        guard active, playerController == nil, let webView = fallbackWebView, !webView.isLoading else { return }
        webView.evaluateJavaScript(WebsiteSession.pageInspection) { [weak self, weak webView] result, _ in
            guard let self, self.active, let webView, let page = result as? [String: Any], let html = page["html"] as? String else { return }
            let challenge = HTMLParser.containsVerification(html)
            if challenge && (page["interactive"] as? Bool) == true {
                self.playback.verification = true
                webView.isHidden = false
                webView.scrollView.isScrollEnabled = true
            } else if !challenge && self.playback.verification {
                self.playback.verification = false
                webView.scrollView.isScrollEnabled = false
                webView.scrollView.contentInsetAdjustmentBehavior = .never
                self.scheduleFallbackReveal(for: webView)
                webView.evaluateJavaScript("window.__anyanimeFocusPlayer && window.__anyanimeFocusPlayer()")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard active, (error as NSError).code != NSURLErrorCancelled else { return }
        if webView === directWebView { startFallback() }
        else { playback.error = "Không tải được video: \(error.localizedDescription)" }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.host == episodeURL.host { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let normalized = message.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN")).lowercased()
        if normalized.contains("neu ban khong the truy cap animevietsub") {
            completionHandler()
            return
        }
        let alert = UIAlertController(title: "Trình phát", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    private func directPlayerHTML(hash64: String, film64: String, key64: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width"><style>body{background:#000}</style>
        <script src="/js/pako.min.js"></script></head><body><script>
        function bytes(s){return Uint8Array.from(atob(s),c=>c.charCodeAt(0));}
        function source(data){
          function item(v){return typeof v==='string'?v:(v&&(v.file||v.src||v.url));}
          try {
            var j=JSON.parse(data), first=j.sources&&j.sources[0], nested=j.player&&j.player.sources&&j.player.sources[0];
            var direct=item(first)||item(nested)||item(j.data)||item(j.link)||item(j.file)||item(j.url);
            if(direct)return {kind:/\\.(?:m3u8|mp4)(?:$|[?#])/i.test(direct)?'video':'iframe',url:direct};
          } catch(e) {}
          var doc=new DOMParser().parseFromString(data,'text/html');
          var media=doc.querySelector('video[src],source[src]');
          if(media)return {kind:'video',url:media.getAttribute('src')};
          var frame=doc.querySelector('iframe[src]');
          if(frame)return {kind:'iframe',url:frame.getAttribute('src')};
          var normalized=data.replace(/\\\\\\//g,'/');
          var m=normalized.match(/https?:\\/\\/[^\\s\"'<>]+\\.(?:m3u8|mp4)(?:[^\\s\"'<>]*)?/i);
          if(m)return {kind:'video',url:m[0]};
          var u=normalized.match(/https?:\\/\\/[^\\s\"'<>]+/i);
          return u&&{kind:'iframe',url:u[0]};
        }
        async function start(){
          try {
            if(typeof pako==='undefined'){await new Promise((ok,no)=>{var s=document.createElement('script');s.src='https://cdnjs.cloudflare.com/ajax/libs/pako/2.1.0/pako.min.js';s.onload=ok;s.onerror=no;document.head.appendChild(s);});}
            var hash=atob('\(hash64)'), id=atob('\(film64)'), keyText=atob('\(key64)');
            var digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(keyText));
            var key=await crypto.subtle.importKey('raw',digest,{name:'AES-CBC'},false,['decrypt']);
            var form=new FormData(); form.append('link',hash); form.append('id',id);
            var response=await fetch('/ajax/player',{method:'POST',headers:{'X-Requested-With':'XMLHttpRequest'},body:form,credentials:'include'});
            if(!response.ok) throw Error('HTTP '+response.status);
            var value=await response.text(), encrypted=value;
            try { var json=JSON.parse(value); encrypted=json.data||json.link||json.html||value; } catch(e) {}
            encrypted=encrypted.replace(/-/g,'+').replace(/_/g,'/'); while(encrypted.length%4)encrypted+='=';
            var raw=bytes(encrypted);
            var clear=await crypto.subtle.decrypt({name:'AES-CBC',iv:raw.slice(0,16)},key,raw.slice(16));
            var text; try{text=pako.inflateRaw(new Uint8Array(clear),{to:'string'});}catch(e){text=new TextDecoder().decode(clear);}
            var found=source(text); if(!found||!found.url) throw Error('Không tìm thấy nguồn video');
            var absolute=new URL(found.url,location.href).href;
            window.webkit.messageHandlers[found.kind==='video'?'videoFound':'iframeFound'].postMessage(absolute);
          } catch(e) {
            var detail=(e&&e.message)||String(e);
            document.title='ERROR:'+detail;
            window.webkit.messageHandlers.playerError.postMessage(detail);
          }
        }
        // The local script tag is blocking: pako is ready here, or start() immediately
        // loads the CDN fallback. Polling for three seconds only slowed failure recovery.
        start();
        </script></body></html>
        """
    }

    private var fallbackJavaScript: String {
        """
        (function(){
          if(window.__anyanimeInstalled)return; window.__anyanimeInstalled=true;
          var hidden=['.Adv','.ad-center','.ads','.advertisement','[class*="ads"]','[class*="banner"]','[id*="ads"]','iframe[src*="ads"]','.popup','.modal-backdrop','.header-ads-pc','.Adv.ad-center-header','header','footer','.footer','.header','.sidebar','.breadcrumb','.comments','.film-info','.heading-film','.list-episode-box','.server-list','.film-thumb','.film-desc','.film-buttons','.category-heading','.block-film','nav','.navbar','.menu'];
          var viewport=document.querySelector('meta[name="viewport"]');
          if(!viewport){viewport=document.createElement('meta');viewport.name='viewport';(document.head||document.documentElement).appendChild(viewport);}
          viewport.content='width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover';
          var reportedFrames={};
          var activeVideo=null;
          var reportedSources={};
          var playerSelectors='#media-player,.player-container,.watching_player,#player,.jwplayer,[class*="video-player"],[class*="player-wrap"]';
          var adSelectors='.ad,.ads,.advertisement,.video-ad,.ima-ad-container,.jw-ad,.jw-flag-ads,.vjs-ad-playing,[data-ad="true"]';
          function send(name,value){try{window.webkit.messageHandlers[name].postMessage(value);}catch(e){}}
          function adURL(s){return /(?:doubleclick|googlesyndication|popads|adservice|vast|\\/ads?[\\/.?]|[?&](?:ad|preroll)=)/i.test(s||'');}
          function playerAPI(v){
            try{
              if(typeof window.jwplayer!=='function')return null;
              var container=v&&v.closest('.jwplayer');
              var api=container?window.jwplayer(container.id):window.jwplayer();
              if(!api||typeof api.getPlaylistItem!=='function')return null;
              if(!api.__aaAdEvents&&api.on){
                api.__aaAdEvents=true;
                ['adPlay','adImpression','adStarted'].forEach(function(e){api.on(e,function(){api.__aaAdActive=true;});});
                ['adBreakEnd','adComplete','adSkipped','adError'].forEach(function(e){api.on(e,function(){api.__aaAdActive=false;});});
              }
              return api;
            }catch(e){return null;}
          }
          function contentSources(api){
            try{
              var item=api&&api.getPlaylistItem();if(!item)return [];
              return (item.sources||[]).map(function(x){return x.file||x.src;}).concat(item.file||[])
                .filter(function(x){return typeof x==='string'&&x&&!adURL(x);})
                .map(function(x){return new URL(x,location.href).href;});
            }catch(e){return [];}
          }
          function isAdvertisement(v){
            if(!v||v.closest(adSelectors)||adURL(mediaURL(v)))return true;
            var api=playerAPI(v);
            return !!(api&&api.__aaAdActive);
          }
          function contentURL(v){
            if(isAdvertisement(v))return '';
            var s=mediaURL(v),api=playerAPI(v),sources=contentSources(api);
            // A JW preroll can replace currentSrc on the SAME video element.
            // Only its actual playlist item is eligible for the native handoff.
            if(api){
              if(!sources.length)return '';
              if(sources.indexOf(s)>=0)return s;
              return sources.find(function(x){return /\\.m3u8(?:[?#]|$)/i.test(x);})||sources[0];
            }
            return /^https?:/i.test(s)&&!adURL(s)?s:'';
          }
          function reportSource(v){
            var s=contentURL(v);
            if(/^https?:/i.test(s)&&!reportedSources[s]){reportedSources[s]=true;send('videoFound',{url:s,referer:location.href});}
          }
          function tryPlay(v){
            if(!v||v.__aaUserPaused||!v.paused)return;
            var p=v.play();if(p&&p.catch)p.catch(function(){state();});
          }
          function important(el,key,value){if(el&&(el.style.getPropertyValue(key)!==value||el.style.getPropertyPriority(key)!=='important'))el.style.setProperty(key,value,'important');}
          function hideAccessNotices(){
            var candidates=document.querySelectorAll('p,span,small,a,.alert,.notice,.message,.warning,[class*="notice"],[class*="warning"],[class*="notify"]');
            candidates.forEach(function(el){
              var text=String(el.innerText||el.textContent||'').toLowerCase();
              var notice=text.indexOf('nếu bạn không thể truy cập animevietsub')>=0||text.indexOf('neu ban khong the truy cap animevietsub')>=0;
              if(notice&&text.length<500)important(el,'display','none');
            });
          }
          function challenge(){return /just a moment|attention required.*cloudflare|xác minh an toàn|xác minh bảo mật|verify you are human|checking your browser/i.test(document.title)||!!document.querySelector('#challenge-form,.cf-turnstile,iframe[src*="challenges.cloudflare.com"],#verification:not([hidden])');}
          function state(){
            var v=activeVideo;if(!v||isAdvertisement(v))return;
            reportSource(v);
            var api=playerAPI(v),sources=contentSources(api),current=mediaURL(v);
            if(api&&/^https?:/i.test(current)&&sources.indexOf(current)<0)return;
            send('mediaState',{time:isFinite(v.currentTime)?v.currentTime:0,duration:isFinite(v.duration)?v.duration:0,paused:v.paused,buffering:!v.paused&&v.readyState<3,ready:v.readyState>=2,ended:v.ended});
          }
          window.addEventListener('message',function(event){
            var c=event.data;if(!c||c.type!=='AnPinimeCommand')return;
            var v=activeVideo;
            if(v&&isAdvertisement(v))v=null;
            if(v){
              try{
                switch(c.name){
                  case 'play':v.__aaUserPaused=false;tryPlay(v);break;
                  case 'pause':v.__aaUserPaused=true;v.pause();break;
                  case 'seek':if(isFinite(v.duration))v.currentTime=Math.max(0,Math.min(Number(c.value)||0,v.duration));break;
                  case 'rate':v.playbackRate=Math.max(0.5,Math.min(Number(c.value)||1,2));break;
                  case 'volume':v.volume=Math.max(0,Math.min(Number(c.value)||0,1));break;
                  case 'fit':v.__anpinimeFill=c.value===1;important(v,'object-fit',v.__anpinimeFill?'cover':'contain');break;
                }
                state();
              }catch(e){}
            }
            document.querySelectorAll('iframe').forEach(function(f){try{f.contentWindow.postMessage(c,'*');}catch(e){}});
          });
          function hideChrome(){
            hidden.forEach(function(s){try{document.querySelectorAll(s).forEach(function(e){important(e,'display','none');});}catch(e){}});
            hideAccessNotices();
            important(document.documentElement,'margin','0'); important(document.documentElement,'padding','0');
            important(document.documentElement,'background','#000'); important(document.documentElement,'overflow','hidden');
            important(document.body,'margin','0'); important(document.body,'padding','0');
            important(document.body,'background','#000'); important(document.body,'overflow','hidden');
          }
          function isolate(el){
            if(!el)return false; hideChrome();
            var node=el;
            while(node&&node!==document.body){
              var parent=node.parentElement;
              if(!parent)break;
              Array.prototype.forEach.call(parent.children,function(sibling){if(sibling!==node)important(sibling,'display','none');});
              important(parent,'display','block'); important(parent,'visibility','visible'); important(parent,'opacity','1');
              important(parent,'position','static'); important(parent,'width','100%'); important(parent,'height','100%');
              important(parent,'margin','0'); important(parent,'padding','0'); important(parent,'transform','none');
              node=parent;
            }
            important(el,'display','block'); important(el,'visibility','visible'); important(el,'opacity','1');
            important(el,'position','fixed'); important(el,'inset','0'); important(el,'width','100vw');
            important(el,'height','100vh'); important(el,'max-width','none'); important(el,'max-height','none');
            important(el,'margin','0'); important(el,'padding','0'); important(el,'z-index','2147483647');
            important(el,'background','#000'); important(el,'transform','none'); important(el,'box-sizing','border-box'); important(el,'min-width','0'); important(el,'min-height','0');
            send('playerReady','ready'); return true;
          }
          function mediaURL(v){
            var s=v.currentSrc||v.getAttribute('src')||'';
            if(!s){var source=v.querySelector('source[src]');if(source)s=source.getAttribute('src')||'';}
            try{return s?new URL(s,location.href).href:'';}catch(e){return '';}
          }
          function watch(v){
            if(!v||isAdvertisement(v))return false;
            activeVideo=v;
            isolate(v); important(v,'object-fit',v.__anpinimeFill?'cover':'contain'); v.setAttribute('playsinline','');v.controls=false;
            if(!v.__aa){
              v.__aa=true;
              ['playing','loadedmetadata','loadeddata','canplay','pause','waiting','ended','durationchange'].forEach(function(name){v.addEventListener(name,function(){if(v===activeVideo)state();});});
              ['loadedmetadata','canplay'].forEach(function(name){v.addEventListener(name,function(){tryPlay(v);});});
              tryPlay(v);
            }
            state();
            return true;
          }
          function usefulFrame(frame){
            var src=frame.getAttribute('src')||'';
            if(!src||/^(?:about:blank|javascript:)/i.test(src)||adURL(src)||frame.closest(adSelectors))return false;
            var rect=frame.getBoundingClientRect();
            return rect.width>=240&&rect.height>=120;
          }
          function focus(){
            if(!window.document||!document.documentElement)return false;
            if(challenge())return false;
            hideChrome();
            var videos=Array.prototype.filter.call(document.querySelectorAll('video'),function(v){
              if(isAdvertisement(v))return false;
              for(var node=v;node&&node!==document.body;node=node.parentElement){
                var style=getComputedStyle(node);if(style.display==='none'||style.visibility==='hidden')return false;
              }
              return true;
            });
            var inPlayer=videos.filter(function(v){return !!v.closest(playerSelectors);});
            var video=inPlayer[0]||(videos.length===1?videos[0]:null);
            if(video)return watch(video);
            activeVideo=null;
            var player=document.querySelector(playerSelectors);
            var frames=Array.prototype.filter.call(document.querySelectorAll('iframe[src]'),usefulFrame);
            frames.sort(function(a,b){var ar=a.getBoundingClientRect(),br=b.getBoundingClientRect();return br.width*br.height-ar.width*ar.height;});
            var playerFrames=frames.filter(function(f){return !!f.closest(playerSelectors);});
            var frame=playerFrames[0]||(frames.length===1?frames[0]:null);
            if(frame){
              isolate(frame);
              if(window===window.top){
                try{var url=new URL(frame.getAttribute('src'),location.href).href;if(!reportedFrames[url]){reportedFrames[url]=true;send('iframeFound',url);}}catch(e){}
              }
              return true;
            }
            return player?isolate(player):false;
          }
          window.__anyanimeFocusPlayer=focus;
          function install(){
            if(!document.documentElement){setTimeout(install,20);return;}
            focus();
            new MutationObserver(function(){focus();}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src','class']});
            var tries=0,timer=setInterval(function(){focus();if(++tries>120)clearInterval(timer);},500);
            setInterval(state,500);
            setTimeout(function(){if(activeVideo||challenge())return;var b=document.querySelector('.jw-icon-playback,.play-btn,[class*="play-button"],button[aria-label*="Play"],button[title*="Play"]');if(b)b.click();focus();},1800);
          }
          if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
        })();
        """
    }
}
