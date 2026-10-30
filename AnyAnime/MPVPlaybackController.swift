import UIKit
import Metal
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
    private var loaded = false
    private var userPaused = false
    private var backgroundPaused = false
    private var pendingImports: [(URL, String)] = []
    private var startedAt = Date()
    var onFailure: ((String) -> Void)?

    init(url: URL, headers: [String: String], playback: PlaybackState) {
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
        if let agent = headers["User-Agent"] { mpv_set_option_string(context, "user-agent", agent) }
        if let referer = headers["Referer"] { mpv_set_option_string(context, "referrer", referer) }
        let extra = headers.filter { !["User-Agent", "Referer"].contains($0.key) }
            .sorted { $0.key < $1.key }.map { ($0.key + ": " + $0.value).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,") }.joined(separator: ",")
        if !extra.isEmpty { mpv_set_option_string(context, "http-header-fields", extra) }
        let status = mpv_initialize(context)
        guard status >= 0 else { fail("Không khởi tạo được mpv: " + String(cString: mpv_error_string(status))); return }
        #if DEBUG
        if PlaybackSmokeTest.source2Diagnostic { mpv_request_log_messages(context, "warn") }
        #endif
        mpv_observe_property(context, 1, "track-list", MPV_FORMAT_NONE)
        playback.engine = "mpv"
        playback.supportsAdvancedSubtitles = true
        set("speed", String(playback.rate)); set("volume", String(playback.volume * 100))
        applyStyle()
        command(["loadfile", url.absoluteString, "replace"])
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = view.bounds
        surface.drawableSize = CGSize(width: view.bounds.width * surface.contentsScale, height: view.bounds.height * surface.contentsScale)
        CATransaction.commit()
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        guard let context = handle else { return }
        handle = nil
        // Network demuxers can take time to close. Keep the render surface alive until teardown finishes.
        let retainedSurface = surface
        DispatchQueue.global(qos: .utility).async {
            mpv_terminate_destroy(context)
            withExtendedLifetime(retainedSurface) {}
        }
    }
    @objc private func background() {
        backgroundPaused = !userPaused
        set("pause", "yes")
    }
    @objc private func foreground() { if backgroundPaused && !userPaused { set("pause", "no") }; backgroundPaused = false }

    func perform(_ name: String, value: Double) {
        switch name {
        case "play": userPaused = false; set("pause", "no")
        case "pause": userPaused = true; set("pause", "yes")
        case "seek": command(["seek", String(max(0, min(value, playback.duration))), "absolute+exact"])
        case "rate": set("speed", String(value))
        case "volume": set("volume", String(value * 100))
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
                if PlaybackSmokeTest.source2Diagnostic, let log = event.pointee.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                    PlaybackSmokeTest.diagnostic("mpv-log", fields: ["component": String(cString: log.pointee.prefix),
                        "message": String(cString: log.pointee.text)])
                }
            #endif
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
        playback.mediaInfo = [string("file-format"), string("video-codec"), "\(Int(number("video-params/w"))) × \(Int(number("video-params/h")))", string("audio-codec")].filter { !$0.isEmpty }.joined(separator: " · ")
        #if DEBUG
        if PlaybackSmokeTest.source2Diagnostic {
            PlaybackSmokeTest.diagnostic("mpv-state", fields: ["loaded": loaded, "time": playback.currentTime,
                "videoWidth": number("video-params/w"), "videoHeight": number("video-params/h"),
                "playing": playback.playing, "buffering": playback.buffering])
        }
        PlaybackSmokeTest.record(time: playback.currentTime, backend: "mpv", size: view.bounds.size, playback: playback,
                                 videoSize: CGSize(width: number("video-params/w"), height: number("video-params/h")))
        #endif
    }
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
        if PlaybackSmokeTest.source2Diagnostic { PlaybackSmokeTest.diagnostic("failure", fields: ["message": message]) }
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
