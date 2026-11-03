import UIKit
import Metal
import AVKit
import Libmpv

/// libmpv handles Matroska, embedded audio/subtitle tracks and two subtitle lanes.
/// All client API access is serialized on the main actor; no callback holds self.
@MainActor
final class MPVPlaybackController: UIViewController {
    private let playback: PlaybackState
    private let url: URL
    private let headers: [String: String]
    private var handle: OpaquePointer?
    private var timer: Timer?
    private let surface = MPVSurface()
    private var pictureInPicture: MPVPictureInPicture?
    private var preloading: Bool
    private let resizesEmbeddedSurface: Bool
    private var rendererSize = CGSize.zero
    private var resizeTask: Task<Void, Never>?
    private var reconfiguringGPU = false
    private var automaticPiPPrepared = false
    private var snapshotPending = false
    private var snapshotReady = false
    private var snapshotAttempts = 0
    private let snapshotReplyID: UInt64 = 0x504950
    #if DEBUG
    private(set) var automaticPiPRequests = 0
    private let diagnosticID = UUID().uuidString
    var nativeGeometry: [String: Any] {
        ["view": String(describing: view.frame), "bounds": String(describing: view.bounds),
         "surface": String(describing: surface.frame), "drawableWidth": surface.drawableSize.width,
         "drawableHeight": surface.drawableSize.height, "videoOutput": string("current-vo"),
         "rendererWidth": number("osd-width"), "rendererHeight": number("osd-height")]
    }
    var piPPrepared: Bool { pictureInPicture != nil }
    var piPPossible: Bool { pictureInPicture?.possible == true }
    #endif
    private var loaded = false
    private var userPaused = false
    private var backgroundPaused = false
    private var pendingImports: [(URL, String)] = []
    private var startedAt = Date()
    #if DEBUG
    private var pipSmokeStage = 0
    private var pipSmokeStageAt = Date()
    private var pipSmokePausedAt = 0.0
    #endif
    var onFailure: ((String) -> Void)?

    init(url: URL, headers: [String: String], playback: PlaybackState, preloading: Bool = false, resizesEmbeddedSurface: Bool = false) {
        self.resizesEmbeddedSurface = resizesEmbeddedSurface
        self.preloading = preloading
        self.url = url; self.headers = headers; self.playback = playback; self.userPaused = playback.userPaused
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        surface.device = MTLCreateSystemDefaultDevice()
        surface.contentsScale = UIScreen.main.nativeScale
        surface.framebufferOnly = true
        view.layer.addSublayer(surface)
        guard let context = mpv_create() else { fail("Không khởi tạo được bộ giải mã video."); return }
        handle = context
        // Pass the retained CAMetalLayer pointer as mpv's native window handle.
        var window = Int64(Int(bitPattern: Unmanaged.passUnretained(surface).toOpaque()))
        mpv_set_option(context, "wid", MPV_FORMAT_INT64, &window)
        for (key, value) in ["vo": "gpu-next", "gpu-api": "vulkan", "gpu-context": "moltenvk",
                             "hwdec": "videotoolbox", "profile": "fast", "keep-open": "no",
                             "idle": "yes", "input-default-bindings": "no", "input-vo-keyboard": "no",
                             "osc": "no", "osd-level": "0", "cache": "yes", "cache-secs": "20",
                             "demuxer-max-bytes": "96MiB", "demuxer-max-back-bytes": "16MiB",
                             "network-timeout": "20", "alang": "vi,vie,en,eng", "slang": "vi,vie,en,eng",
                             "sub-auto": "no", "audio-display": "no", "pause": "no"] {
            mpv_set_option_string(context, key, value)
        }
        if preloading {
            for (key, value) in ["pause": "yes", "volume": "0", "cache-secs": "3", "demuxer-max-bytes": "12MiB", "demuxer-max-back-bytes": "0"] {
                mpv_set_option_string(context, key, value)
            }
        }
        if let agent = headers["User-Agent"] { mpv_set_option_string(context, "user-agent", agent) }
        if let referer = headers["Referer"] { mpv_set_option_string(context, "referrer", referer) }
        let extra = headers.filter { !["User-Agent", "Referer"].contains($0.key) }
            .sorted { $0.key < $1.key }.map { ($0.key + ": " + $0.value).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,") }.joined(separator: ",")
        if !extra.isEmpty { mpv_set_option_string(context, "http-header-fields", extra) }
        let status = mpv_initialize(context)
        guard status >= 0 else { fail("Không khởi tạo được mpv: " + String(cString: mpv_error_string(status))); return }
        #if DEBUG
        if PlaybackSmokeTest.source2Diagnostic || PlaybackSmokeTest.animeSmoke || PlaybackSmokeTest.mpvFixture { mpv_request_log_messages(context, "warn") }
        #endif
        mpv_observe_property(context, 1, "track-list", MPV_FORMAT_NONE)
        playback.pictureInPictureSupported = AVPictureInPictureController.isPictureInPictureSupported()
        playback.engine = "mpv"
        playback.supportsAdvancedSubtitles = true
        set("speed", String(playback.rate)); set("volume", preloading ? "0" : String(playback.volume * 100))
        applyStyle()
        command(["loadfile", url.absoluteString, "replace"])
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(prepareForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = view.bounds
        surface.drawableSize = CGSize(width: view.bounds.width * surface.contentsScale, height: view.bounds.height * surface.contentsScale)
        pictureInPicture?.layer.frame = view.bounds
        CATransaction.commit()
        resizeEmbeddedRendererIfNeeded()
    }

    private func resizeEmbeddedRendererIfNeeded() {
        let size = surface.drawableSize
        guard size.width > 1, size.height > 1, size != rendererSize else { return }
        let hadSize = rendererSize != .zero
        rendererSize = size
        guard resizesEmbeddedSurface, hadSize, loaded, !reconfiguringGPU else { return }
        resizeTask?.cancel()
        resizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self, self.handle != nil, self.rendererSize == size,
                  UIApplication.shared.applicationState == .active,
                  self.string("current-vo") == "gpu-next" else { return }
            // This MPVKit context reads layer size only during reconfig() and emits
            // no resize event. Let null output commit before restoring gpu-next, so
            // option caching cannot coalesce an equivalent driver list. Audio, file,
            // decoder ownership and playback position continue in the same player.
            self.reconfiguringGPU = true
            // Null output must not consume a silent/video-only clip at full speed.
            // This internal pause leaves the user's pause intent unchanged.
            self.set("pause", "yes")
            self.set("vo", "null")
            for _ in 0..<20 {
                guard self.handle != nil, !Task.isCancelled else { self.reconfiguringGPU = false; return }
                if self.string("current-vo") == "null" { break }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            if self.handle != nil, !Task.isCancelled {
                if UIApplication.shared.applicationState == .active, self.string("current-vo") != "libmpv" {
                    self.set("vo", "gpu-next")
                }
                self.set("pause", self.userPaused ? "yes" : "no")
            }
            self.reconfiguringGPU = false
        }
    }

    func shutdown() {
        resizeTask?.cancel(); resizeTask = nil
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        guard let context = handle else { return }
        handle = nil
        // Network demuxers can take time to close. Keep the render surface alive until teardown finishes.
        let retainedSurface = surface
        let destroy = {
            DispatchQueue.global(qos: .utility).async {
                mpv_terminate_destroy(context)
                withExtendedLifetime(retainedSurface) {}
            }
        }
        if let pictureInPicture { pictureInPicture.stop(restore: false, completion: destroy) }
        else { destroy() }
        pictureInPicture = nil
    }

    func finishPreloading() {
        preloading = false
        set("cache-secs", "20"); set("demuxer-max-bytes", "96MiB"); set("demuxer-max-back-bytes", "16MiB")
        set("volume", String(playback.volume * 100))
    }

    private var automaticPiPEnabled: Bool {
        !preloading && (UserDefaults.standard.object(forKey: "AnPinime.automaticPiP") as? Bool ?? true)
    }

    @objc private func prepareForBackground() { prepareAutomaticPictureInPicture() }

    /// Begin preparing frames at resign-active, but let the system's inline transition
    /// start PiP. An explicit fallback request follows only on actual background entry.
    func prepareAutomaticPictureInPicture() {
        guard automaticPiPEnabled, !userPaused else { return }
        preparePictureInPicture(start: false)
        automaticPiPPrepared = pictureInPicture != nil
    }

    private func armPictureInPicture() {
        guard loaded, !preloading, handle != nil else { return }
        if pictureInPicture != nil { requestPiPSnapshot(); return }
        snapshotReady = false; snapshotPending = false; snapshotAttempts = 0
        playback.pictureInPictureError = nil
        let pip = MPVPictureInPicture(playback: playback, command: { [weak self] name, value in
            guard let self else { return }
            if name == "pipOutput" {
                self.set("hwdec", "videotoolbox-copy"); self.set("vo", "libmpv")
                self.surface.isHidden = true
            } else { self.playback.send(name, value) }
        }, restoreVideo: { [weak self] in
            self?.set("vo", "gpu-next"); self?.set("hwdec", "videotoolbox")
            self?.surface.isHidden = false
        }, finished: { [weak self] in
            guard let self else { return }
            self.pictureInPicture = nil; self.automaticPiPPrepared = false
            if UIApplication.shared.applicationState == .background { self.background() }
        })
        pictureInPicture = pip
        pip.layer.frame = view.bounds
        view.layer.insertSublayer(pip.layer, below: surface)
        pip.onSystemStart = { [weak self] in self?.preparePictureInPicture(start: false) }
        #if DEBUG
        pip.onEvent = { [weak self] event in self?.recordAutomaticPiP(event) }
        #endif
        pip.arm(snapshot: nil, automatic: automaticPiPEnabled && !userPaused)
        requestPiPSnapshot()
    }

    private func requestPiPSnapshot() {
        guard !snapshotPending, !snapshotReady, snapshotAttempts < 3, let handle else { return }
        // Bootstrap from the decoder through mpv's software scaler. GPU screenshots
        // reinitialize the renderer, interrupt playback and crash Metal simulation's
        // shared-buffer readback. Never fall back to that path if the option is absent.
        guard mpv_set_property_string(handle, "screenshot-sw", "yes") >= 0 else { return }
        let screenshotCommand: [String] = ["screenshot-raw", "video"]
        let strings = screenshotCommand.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var arguments: [UnsafePointer<CChar>?] = strings.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        snapshotAttempts += 1
        snapshotPending = mpv_command_async(handle, snapshotReplyID, &arguments) >= 0
    }

    func preparePictureInPicture(start: Bool = true) {
        guard loaded, !userPaused, !preloading, let handle else { return }
        guard playback.pictureInPictureSupported || !start else { return }
        armPictureInPicture()
        let size = CGSize(width: max(1, number("video-params/w")), height: max(1, number("video-params/h")))
        pictureInPicture?.prepare(handle: handle, size: size, start: start)
    }

    @objc private func background() {
        if automaticPiPPrepared, !userPaused {
            #if DEBUG
            automaticPiPRequests += 1
            recordAutomaticPiP("automaticBackgroundRequest")
            #endif
            pictureInPicture?.requestStart()
        }
        guard !playback.pictureInPictureActive, !playback.pictureInPicturePending else { return }
        backgroundPaused = !userPaused
        set("pause", "yes")
    }
    @objc private func foreground() {
        if automaticPiPPrepared, let pip = pictureInPicture {
            automaticPiPPrepared = false
            pip.stop(restore: true) { [weak self] in self?.pictureInPicture = nil }
        }
        if backgroundPaused && !userPaused { set("pause", "no") }
        backgroundPaused = false
    }

    /// mpv's own decoded frame arms sample-buffer PiP before iOS suspends the app.
    /// The asynchronous reply is copied into one small buffer before the next event.
    /// Never block the main/render thread with mpv_command_ret while GPU output is live.
    private func decodedSnapshot(_ node: mpv_node) -> CVPixelBuffer? {
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list?.pointee,
              list.num > 0, list.num <= 32, let keys = list.keys, let values = list.values else { return nil }
        var fields: [String: mpv_node] = [:]
        for index in 0..<Int(list.num) { if let key = keys[index] { fields[String(cString: key)] = values[index] } }
        guard let w = fields["w"], w.format == MPV_FORMAT_INT64,
              let h = fields["h"], h.format == MPV_FORMAT_INT64,
              let row = fields["stride"], row.format == MPV_FORMAT_INT64,
              let format = fields["format"], format.format == MPV_FORMAT_STRING, let name = format.u.string,
              ["bgr0", "bgra"].contains(String(cString: name)),
              let data = fields["data"], data.format == MPV_FORMAT_BYTE_ARRAY, let bytes = data.u.ba?.pointee,
              let pointer = bytes.data else { return nil }
        let width = Int(w.u.int64), height = Int(h.u.int64), stride = Int(row.u.int64)
        guard width > 0, width <= 8192, height > 0, height <= 8192,
              stride >= width * 4, stride <= 131072, stride * height <= 64 * 1024 * 1024,
              bytes.size >= stride * height else { return nil }
        let color = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(dataInfo: nil, data: pointer, size: stride * height, releaseData: { _, _, _ in }),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: stride, space: color, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let scale = min(1, 640.0 / Double(max(width, height)))
        let outputWidth = max(4, Int(Double(width) * scale)), outputHeight = max(4, Int(Double(height) * scale))
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, []); defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let destination = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: outputWidth, height: outputHeight,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: color,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        destination.interpolationQuality = .medium
        destination.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        return buffer
    }

    func perform(_ name: String, value: Double) {
        switch name {
        case "pip": preparePictureInPicture()
        case "play": userPaused = false; set("pause", "no")
        case "pause": userPaused = true; set("pause", "yes"); pictureInPicture?.setAutomatic(false)
        case "seek": command(["seek", String(max(0, min(value, playback.duration))), "absolute+exact"])
        case "rate": set("speed", String(value))
        case "volume": set("volume", String(value * 100))
        case "aspect": set("video-aspect-override", String(value))
        case "fit": set("panscan", value == 1 ? "1" : "0")
        case "subtitleStyle", "subtitleSize", "subtitleBackground": applyStyle()
        default: break
        }
    }
    func choose(_ kind: String, id: String) {
        if kind == "quality", let option = playback.qualities.first(where: { $0.id == id }) {
            let time = playback.currentTime
            playback.quality = id; playback.loading = true; loaded = false; startedAt = Date()
            let bitrate = id == "auto" ? "max" : String(Int(option.bandwidth))
            command(["loadfile", url.absoluteString, "replace", "-1", "start=\(time),hls-bitrate=\(bitrate)"])
            return
        }
        let property = kind == "audio" ? "aid" : kind == "secondarySubtitles" ? "secondary-sid" : "sid"
        guard ["audio", "subtitles", "secondarySubtitles"].contains(kind) else { return }
        let tracks = kind == "audio" ? playback.audioTracks : playback.subtitleTracks
        guard id == "off" || tracks.contains(where: { $0.id == id }) else { return }
        // One subtitle track cannot occupy both lanes.
        if kind == "subtitles", id != "off", id == playback.secondarySubtitleTrack { set("secondary-sid", "no") }
        if kind == "secondarySubtitles", id != "off", id == playback.subtitleTrack { set("sid", "no") }
        set(property, id == "off" ? "no" : id)
        updateSelectedTracks()
    }
    func addSubtitle(_ url: URL, slot: String) {
        guard loaded else { pendingImports.append((url, slot)); return }
        // Select by external filename after the asynchronous track-list change.
        pendingImports.append((url, slot))
        command(["sub-add", url.path, "auto", url.deletingPathExtension().lastPathComponent])
    }
    private func poll() {
        guard let context = handle else { return }
        for _ in 0..<40 {
            guard let event = mpv_wait_event(context, 0), event.pointee.event_id != MPV_EVENT_NONE else { break }
            switch event.pointee.event_id {
            #if DEBUG
            case MPV_EVENT_LOG_MESSAGE:
                if PlaybackSmokeTest.source2Diagnostic || PlaybackSmokeTest.animeSmoke || PlaybackSmokeTest.mpvFixture, let log = event.pointee.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                    PlaybackSmokeTest.diagnostic("mpv-log", fields: ["component": String(cString: log.pointee.prefix),
                        "message": String(cString: log.pointee.text)])
                }
            #endif
            case MPV_EVENT_COMMAND_REPLY where event.pointee.reply_userdata == snapshotReplyID:
                snapshotPending = false
                if event.pointee.error >= 0, let result = event.pointee.data?.assumingMemoryBound(to: mpv_event_command.self),
                   let buffer = decodedSnapshot(result.pointee.result) {
                    snapshotReady = true
                    pictureInPicture?.arm(snapshot: buffer, automatic: automaticPiPEnabled && !userPaused)
                    #if DEBUG
                    recordAutomaticPiP("armedWithDecodedFrame")
                    #endif
                }
            case MPV_EVENT_FILE_LOADED:
                loaded = true
                let pending = pendingImports; pendingImports = []
                refreshTracks()
                for (url, slot) in pending { addSubtitle(url, slot: slot) }
                applyStyle(); set("pause", userPaused ? "yes" : "no")
            case MPV_EVENT_PROPERTY_CHANGE: if event.pointee.reply_userdata == 1 { refreshTracks() }
            case MPV_EVENT_END_FILE:
                if let data = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self) {
                    if data.pointee.reason == MPV_END_FILE_REASON_EOF { playback.playing = false; playback.endCount += 1 }
                    else if data.pointee.reason == MPV_END_FILE_REASON_ERROR {
                        fail("Không mở được luồng video: " + String(cString: mpv_error_string(data.pointee.error)))
                    }
                }
            default: break
            }
        }
        guard handle != nil else { return }
        playback.currentTime = number("time-pos")
        playback.duration = number("duration")
        playback.buffering = string("paused-for-cache") == "yes"
        playback.playing = loaded && string("pause") == "no" && !playback.buffering && string("idle-active") != "yes"
        if loaded && (playback.currentTime > 0 || number("video-params/w") > 0) { playback.loading = false; playback.error = nil }
        if !loaded && Date().timeIntervalSince(startedAt) > 40 { fail("Máy chủ chưa trả dữ liệu video. Hãy thử lại hoặc chọn máy chủ khác.") }
        if loaded, playback.currentTime > 0.5, automaticPiPEnabled, !userPaused,
           UIApplication.shared.applicationState == .active, playback.pictureInPictureSupported {
            armPictureInPicture()
        }
        pictureInPicture?.setAutomatic(automaticPiPEnabled && !userPaused)
        pictureInPicture?.invalidatePlaybackState()
        playback.mediaInfo = [string("file-format"), string("video-codec"), "\(Int(number("video-params/w"))) × \(Int(number("video-params/h")))", string("audio-codec")].filter { !$0.isEmpty }.joined(separator: " · ")
        #if DEBUG
        if PlaybackSmokeTest.source2Diagnostic || PlaybackSmokeTest.animeSmoke || PlaybackSmokeTest.mpvFixture {
            PlaybackSmokeTest.diagnostic("mpv-state", fields: ["loaded": loaded, "time": playback.currentTime,
                "videoWidth": number("video-params/w"), "videoHeight": number("video-params/h"),
                "playing": playback.playing, "buffering": playback.buffering,
                "pipStage": pipSmokeStage, "pipFrames": pictureInPicture?.frameCount ?? 0,
                "pipVisibleFrames": pictureInPicture?.visibleFrameCount ?? 0,
                "currentVideoOutput": string("current-vo")])
        }
        verifyPiPFixtureIfNeeded()
        PlaybackSmokeTest.record(time: playback.currentTime, backend: "mpv", size: view.bounds.size, playback: playback,
                                 videoSize: CGSize(width: number("video-params/w"), height: number("video-params/h")))
        #endif
    }
    #if DEBUG
    private func verifyPiPFixtureIfNeeded() {
        guard PlaybackSmokeTest.mpvFixture, loaded else { return }
        switch pipSmokeStage {
        case 0 where playback.currentTime > 2:
            pipSmokeStage = 1; preparePictureInPicture(start: false)
        case 1:
            guard let pip = pictureInPicture, pip.frameCount >= 8, pip.visibleFrameCount >= 6 else { return }
            playback.pipSmokeFrames = pip.frameCount
            playback.send("pause")
            pipSmokeStage = 2; pipSmokeStageAt = Date(); pipSmokePausedAt = playback.currentTime
        case 2 where Date().timeIntervalSince(pipSmokeStageAt) > 1:
            guard abs(playback.currentTime - pipSmokePausedAt) < 0.5 else { return }
            playback.send("seek", 6); playback.send("play")
            pipSmokeStage = 3
        case 3 where playback.currentTime > 6.8:
            guard let pip = pictureInPicture else { return }
            pipSmokeStage = 4
            pip.stop(restore: true) { [weak self] in
                guard let self else { return }
                self.pictureInPicture = nil; self.pipSmokeStageAt = Date(); self.pipSmokeStage = 5
            }
        case 5 where Date().timeIntervalSince(pipSmokeStageAt) > 0.7:
            guard playback.playing, number("video-params/w") > 0, string("vo") == "gpu-next" else { return }
            playback.pipSmokeSeekPauseRestored = true; pipSmokeStage = 6
        default: break
        }
    }
    #endif

    private func refreshTracks() {
        guard handle != nil else { return }
        var audio: [PlaybackChoice] = [], subtitles: [PlaybackChoice] = [.init(id: "off", title: "Tắt")]
        for index in 0..<min(200, Int(number("track-list/count"))) {
            let root = "track-list/\(index)/", type = string(root + "type"), id = string(root + "id")
            guard ["audio", "sub"].contains(type), !id.isEmpty else { continue }
            let title = [string(root + "title"), string(root + "lang"), string(root + "codec")].filter { !$0.isEmpty }.joined(separator: " · ")
            let item = PlaybackChoice(id: id, title: title.isEmpty ? (type == "audio" ? "Âm thanh " : "Phụ đề ") + id : title)
            if type == "audio" { audio.append(item) } else { subtitles.append(item) }
            if let pending = pendingImports.firstIndex(where: { $0.0.path == string(root + "external-filename") }) {
                let slot = pendingImports.remove(at: pending).1
                set(slot == "secondarySubtitles" ? "secondary-sid" : "sid", id)
            }
        }
        playback.audioTracks = audio; playback.subtitleTracks = subtitles
        updateSelectedTracks()
    }
    private func updateSelectedTracks() {
        playback.audioTrack = string("aid")
        playback.subtitleTrack = normalizedTrack(string("sid"))
        playback.secondarySubtitleTrack = normalizedTrack(string("secondary-sid"))
    }
    private func normalizedTrack(_ value: String) -> String { Int(value) == nil ? "off" : value }
    private func applyStyle() {
        let style = playback.subtitleStyle
        let values = ["sub-font": style.font, "sub-font-size": String(style.size), "sub-margin-y": String(style.margin),
                      "sub-align-x": style.alignment, "sub-color": style.foreground, "sub-back-color": style.background,
                      "sub-border-color": style.outline, "sub-border-size": "2", "sub-ass-override": "force",
                      "sub-delay": String(style.delay), "secondary-sub-delay": String(style.secondaryDelay),
                      "secondary-sub-pos": "10", "panscan": playback.fill ? "1" : "0"]
        for (name, value) in values { set(name, value) }
    }
    private func set(_ name: String, _ value: String) { if let handle { mpv_set_property_string(handle, name, value) } }
    private func string(_ name: String) -> String {
        guard let handle, let pointer = mpv_get_property_string(handle, name) else { return "" }
        defer { mpv_free(pointer) }
        return String(cString: pointer)
    }
    #if DEBUG
    private func recordAutomaticPiP(_ event: String) {
        guard AIDramaDebugSupport.enabled || PlaybackSmokeTest.mpvFixture else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("automatic-pip-events.json")
        var events = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        events.append(["event": event, "player": diagnosticID, "timestamp": Date().timeIntervalSince1970,
                       "applicationState": UIApplication.shared.applicationState.rawValue,
                       "possible": pictureInPicture?.possible == true, "active": playback.pictureInPictureActive,
                       "pending": playback.pictureInPicturePending, "paused": userPaused,
                       "automatic": automaticPiPEnabled, "time": playback.currentTime, "videoOutput": string("current-vo")])
        if let data = try? JSONSerialization.data(withJSONObject: Array(events.suffix(100)), options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif

    private func number(_ name: String) -> Double {
        guard let handle else { return 0 }
        var value = 0.0
        guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0, value.isFinite else { return 0 }
        return value
    }
    private func command(_ arguments: [String]) {
        guard let handle else { return }
        let pointers = arguments.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        var args: [UnsafePointer<CChar>?] = pointers.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        let result = mpv_command_async(handle, 0, &args)
        if result < 0 { fail(String(cString: mpv_error_string(result))) }
    }
    private func fail(_ message: String) {
        #if DEBUG
        if PlaybackSmokeTest.source2Diagnostic || PlaybackSmokeTest.animeSmoke || PlaybackSmokeTest.mpvFixture { PlaybackSmokeTest.diagnostic("failure", fields: ["message": message]) }
        #endif
        playback.loading = false; playback.buffering = false; playback.playing = false; playback.error = message
        timer?.invalidate(); timer = nil
        onFailure?(message)
    }
}

private final class MPVSurface: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if newValue.width > 1 && newValue.height > 1 { super.drawableSize = newValue } }
    }
}
