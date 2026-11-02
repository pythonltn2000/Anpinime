import SwiftUI
import UIKit
import MediaPlayer

@MainActor
final class PlaybackState: ObservableObject {
    @Published var loading = true
    @Published var buffering = false
    @Published var playing = false
    var userPaused = false
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published var verification = false
    @Published var endCount = 0
    @Published var rate = 1.0
    @Published var fill = false
    @Published var volume = 1.0
    @Published var audioTracks: [PlaybackChoice] = []
    @Published var subtitleTracks: [PlaybackChoice] = []
    @Published var audioTrack = ""
    @Published var subtitleTrack = "off"
    @Published var qualities: [PlaybackQuality] = [.automatic]
    @Published var quality = "auto"
    @Published var subtitleSize = 100.0
    @Published var subtitleBackground = false
    @Published var engine = "WebKit"
    @Published var mediaInfo = ""
    @Published var supportsAdvancedSubtitles = false
    @Published var secondarySubtitleTrack = "off"
    @Published var subtitleStyle = SubtitleStyle.load()
    var importSubtitle: ((URL, String) -> Void)?
    var chooseOption: ((String, String) -> Void)?
    var command: ((String, Double) -> Void)?

    func send(_ name: String, _ value: Double = 0) {
        if name == "pause" { userPaused = true }
        if name == "play" { userPaused = false }
        command?(name, value)
    }
    func reset() {
        loading = true; buffering = false; playing = false; userPaused = false
        currentTime = 0; duration = 0; error = nil; verification = false
        audioTracks = []; subtitleTracks = []; audioTrack = ""; subtitleTrack = "off"
        qualities = [.automatic]; quality = "auto"
        secondarySubtitleTrack = "off"; supportsAdvancedSubtitles = false; engine = "WebKit"; mediaInfo = ""
    }
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: AnimeService
    @StateObject private var playback = PlaybackState()
    let episode: Episode
    let title: String
    let artworkURL: URL?
    let episodes: [Episode]
    @State private var selectedEpisode: Episode?
    @State private var attempt = 0
    @State private var controlsVisible = true
    @State private var locked = false
    @State private var panel: String?
    @State private var panelSeason = ""
    @State private var scrubTime = 0.0
    @State private var scrubbing = false
    @State private var hideTask: Task<Void, Never>?
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness = UIScreen.main.brightness
    @AppStorage("AnPinime.autoNext") private var autoNext = true
    @AppStorage("AnPinime.rememberSpeed") private var rememberSpeed = true
    @AppStorage("AnPinime.playbackRate") private var savedRate = 1.0
    @AppStorage("AnPinime.skipSeconds") private var skipSeconds = 10

    private var current: Episode { selectedEpisode ?? episode }
    private var currentIndex: Int? { episodes.firstIndex(where: { $0.id == current.id }) }
    private var availableSeasons: [String] {
        episodes.reduce(into: [String]()) { if !$0.contains($1.season) { $0.append($1.season) } }
    }
    private var nextEpisode: Episode? {
        guard let i = currentIndex, i + 1 < episodes.count, episodes[i + 1].season == current.season else { return nil }
        return episodes[i + 1]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                PlayerControllerView(episode: current, service: service, playback: playback)
                    .id(current.id + "-\(attempt)")
                    .ignoresSafeArea()

                if playback.loading && !playback.verification {
                    loadingBackdrop(size: geometry.size)
                }

                if !playback.verification {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture {
                            guard !locked else { return }
                            withAnimation(.easeOut(duration: 0.2)) { controlsVisible.toggle() }
                            scheduleHide()
                        }
                    if controlsVisible && !locked && panel == nil {
                        controls(size: geometry.size)
                            .transition(.opacity)
                    }
                    if locked {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                controlButton("lock.fill", "Mở khóa điều khiển") { locked = false; controlsVisible = true; scheduleHide() }
                            }
                        }.padding(24)
                    }
                    if playback.buffering && !playback.loading && panel == nil {
                        ProgressView().tint(.white).scaleEffect(1.5).allowsHitTesting(false)
                    }
                    if let error = playback.error {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                            Text(ContentDisplayText.sourceLabels(error)).multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Button("Thử phát lại") { retry() }.buttonStyle(.borderedProminent).tint(.anpinimeAccent)
                                if availableSeasons.count > 1 {
                                    Button("Đổi Server") { openPanel("seasons") }.buttonStyle(.bordered).tint(.white)
                                }
                            }
                        }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                            .padding(30)
                    }
                    if let panel {
                        Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { closePanel() }
                        HStack {
                            if geometry.size.width > geometry.size.height { Spacer(minLength: 0) }
                            if ["settings", "audio", "subtitles", "display", "speed", "general", "info"].contains(panel) {
                                PlayerSettingsPanel(playback: playback, initialTab: panel, title: title, source: ContentDisplayText.sourceLabels(current.season),
                                                    close: closePanel, reload: { closePanel(); retry() })
                                    .frame(width: min(720, geometry.size.width - 24), height: min(geometry.size.height - 24, 620)).padding(12)
                            } else {
                                playerPanel(panel)
                                    .frame(width: min(360, geometry.size.width - 24))
                                    .frame(maxHeight: min(geometry.size.height - 16, 620))
                                    .cinemaGlass(cornerRadius: 28).padding(12)
                            }
                        }
                    }
                } else {
                    VStack { HStack { controlButton("xmark", "Đóng trình phát") { dismiss() }; Spacer() }; Spacer() }.padding()
                }
            }
            .foregroundColor(.white)
            .tint(.anpinimeAccent)
        }
        .background(LandscapePresentation().frame(width: 0, height: 0))
        .statusBar(hidden: !playback.verification)
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            playback.rate = rememberSpeed ? savedRate : 1
            playback.send("rate", playback.rate)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
                if ["episodes", "settings", "audio", "subtitles", "display", "speed", "general", "info", "quality"].contains(InterfacePreview.mode) { openPanel(InterfacePreview.mode) }
            }
            #endif
        }
        .onDisappear {
            hideTask?.cancel()
            playback.send("pause")
            UIApplication.shared.isIdleTimerDisabled = false
            UIScreen.main.brightness = originalBrightness
        }
        .onChange(of: playback.playing) { _ in scheduleHide() }
        .onChange(of: playback.loading) { loading in if !loading { scheduleHide() } }
        .onChange(of: playback.endCount) { _ in
            if autoNext, let next = nextEpisode { select(next) }
            else { controlsVisible = true }
        }
    }

    private func loadingBackdrop(size: CGSize) -> some View {
        ZStack {
            Group {
                if artworkURL != nil { RemoteImage(url: artworkURL) }
                else { Image("AppLogo").resizable().scaledToFill() }
            }
            .frame(width: size.width, height: size.height).clipped()
            .overlay(Color.black.opacity(0.44))
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.1), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 16) {
                Text("ANPINIME").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(6).foregroundColor(.white.opacity(0.65))
                PulsingMovieTitle(title: title, size: size.width > 600 ? 40 : 30)
                Text(current.title).font(.subheadline.weight(.medium)).foregroundColor(.white.opacity(0.7))
            }.padding(.horizontal, 36).opacity(playback.duration > 0 ? 0 : 1)
        }.ignoresSafeArea().allowsHitTesting(false)
    }

    private func controls(size: CGSize) -> some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.75), location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    controlButton("chevron.left", "Đóng trình phát") { dismiss() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline).lineLimit(1)
                        Text(ContentDisplayText.sourceLabels(current.source.isMovie ? "\(current.season) · \(current.title)" : current.title)).font(.caption).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    controlButton("gearshape", "Cài đặt phát") { openPanel("settings") }
                }
                Spacer(minLength: 0)
                if (!playback.loading || playback.duration > 0) && playback.error == nil {
                    HStack(spacing: size.width > 600 ? 65 : 36) {
                        skipButton(forward: false)
                        Button {
                            playback.send(playback.playing ? "pause" : "play")
                            scheduleHide()
                        } label: {
                            MorphIcon(name: playback.playing ? "pause" : "play", size: 32)
                                .frame(width: 32, height: 32).frame(width: 72, height: 72)
                                .cinemaGlass(cornerRadius: 36, interactive: true)
                        }.accessibilityLabel(playback.playing ? "Tạm dừng" : "Phát")
                        skipButton(forward: true)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if playback.duration > 0 {
                        Slider(value: Binding(get: { scrubbing ? scrubTime : playback.currentTime }, set: { scrubTime = $0 }),
                               in: 0...max(playback.duration, 1), onEditingChanged: { editing in
                            scrubbing = editing
                            if editing { hideTask?.cancel(); scrubTime = playback.currentTime }
                            else { playback.send("seek", scrubTime); scheduleHide() }
                        }).accessibilityLabel("Vị trí phát")
                        HStack {
                            Text(timestamp(scrubbing ? scrubTime : playback.currentTime))
                            Spacer()
                            Text(timestamp(playback.duration))
                        }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    }
                    HStack(spacing: 12) {
                        smallButton("Danh sách tập", "rectangle.stack") { openPanel("episodes") }
                        if availableSeasons.count > 1 {
                            smallButton("Đổi Server", "server.rack") { openPanel("seasons") }
                        }
                        if let next = nextEpisode {
                            if size.width > 500 { smallButton("Tập tiếp", "forward.end.fill") { select(next) } }
                            else { controlButton("forward.end.fill", "Tập tiếp") { select(next) } }
                        }
                        Spacer(minLength: 0)
                        if current.source.isMovie {
                            Button { openPanel("subtitles") } label: { MorphIcon(name: "captions").frame(width: 23, height: 23).frame(width: 44, height: 44) }
                                .accessibilityLabel("Phụ đề và caption")
                            Button { openPanel("quality") } label: { MorphIcon(name: "quality").frame(width: 23, height: 23).frame(width: 44, height: 44) }
                                .accessibilityLabel("Chất lượng video")
                        }
                        controlButton("lock.open", "Khóa điều khiển") { locked = true; controlsVisible = false }
                        controlButton(playback.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", "Đổi tỉ lệ hình") {
                            playback.fill.toggle(); playback.send("fit", playback.fill ? 1 : 0); scheduleHide()
                        }
                    }
                }
            }.padding(.horizontal, size.width > 600 ? 30 : 18).padding(.vertical, 16)
        }
    }

    private func controlButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        let names = ["chevron.left": "back", "gearshape": "settings", "xmark": "close", "lock.fill": "lock", "lock.open": "unlock",
                     "arrow.down.right.and.arrow.up.left": "shrink", "arrow.up.left.and.arrow.down.right": "expand", "forward.end.fill": "next"]
        return Button(action: action) {
            if let name = names[icon] { MorphIcon(name: name).frame(width: 22, height: 22).frame(width: 44, height: 44) }
            else { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
        }
            .cinemaGlass(cornerRadius: 22, interactive: true)
            .accessibilityLabel(label)
    }
    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .cinemaGlass(cornerRadius: 22, interactive: true)
        }
    }
    private func skipButton(forward: Bool) -> some View {
        Button {
            playback.send("seek", max(0, playback.currentTime + (forward ? Double(skipSeconds) : -Double(skipSeconds))))
            scheduleHide()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: forward ? "goforward" : "gobackward").font(.system(size: 28))
                Text("\(skipSeconds)s").font(.caption2.weight(.bold))
            }.frame(width: 52, height: 60)
        }.accessibilityLabel("\(forward ? "Tua tới" : "Tua lại") \(skipSeconds) giây")
    }

    private func playerPanel(_ kind: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(panelTitle(kind)).font(.title3.bold())
                    Text(kind == "episodes" ? "\(episodes.count) tập · \(current.title)" : "Theo cách bạn thích")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                controlButton("xmark", "Đóng bảng") { closePanel() }
            }
            if kind == "episodes" { episodePanel }
            else if ["audio", "subtitles", "quality", "seasons"].contains(kind) { optionPanel(kind) }
            else { settingsPanel }
        }.padding(20)
    }

    private var episodePanel: some View {
        let seasons = episodes.reduce(into: [String]()) { if !$0.contains($1.season) { $0.append($1.season) } }
        let season = panelSeason.isEmpty ? current.season : panelSeason
        return VStack(spacing: 14) {
            if seasons.count > 1 {
                Button { panel = "seasons" } label: {
                    HStack { Text(ContentDisplayText.sourceLabels(season)); Spacer(); MorphIcon(name: "down").frame(width: 18, height: 18) }.frame(minHeight: 44)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                        ForEach(episodes.filter { $0.season == season }) { item in
                            Button { select(item) } label: {
                                VStack(spacing: 6) {
                                    if item.id == current.id { Image(systemName: "waveform").font(.caption) }
                                    Text(item.title).font(.caption.weight(.semibold)).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(item.id == current.id ? Color.anpinimeAccent.opacity(0.3) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(item.id == current.id ? Color.anpinimeAccent : .clear))
                            }.id(item.id)
                        }
                    }
                }.onAppear { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsRow("audio", value: playback.audioTracks.first { $0.id == playback.audioTrack }?.title ?? "Theo video")
                settingsRow("subtitles", value: playback.subtitleTracks.first { $0.id == playback.subtitleTrack }?.title ?? "Tắt / không có")
                settingsRow("quality", value: playback.qualities.first { $0.id == playback.quality }?.title ?? "Tự động")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tốc độ phát").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button {
                                playback.rate = rate; savedRate = rate; playback.send("rate", rate)
                            } label: {
                                Text(String(format: "%g×", rate)).font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(playback.rate == rate ? Color.anpinimeAccent.opacity(0.3) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                Toggle("Lấp đầy màn hình", isOn: $playback.fill)
                    .onChange(of: playback.fill) { playback.send("fit", $0 ? 1 : 0) }
                Toggle("Tự phát tập tiếp theo", isOn: $autoNext)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Độ sáng", systemImage: "sun.max")
                    Slider(value: $brightness, in: 0.05...1).onChange(of: brightness) { UIScreen.main.brightness = CGFloat($0) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Âm lượng phim", systemImage: "speaker.wave.2")
                    SystemVolumeSlider().frame(height: 32)
                }
                Button { closePanel(); retry() } label: { Label("Tải lại luồng phát", systemImage: "arrow.clockwise") }
            }.font(.subheadline).padding(.bottom, 8)
        }
    }

    private func panelTitle(_ kind: String) -> String {
        ["episodes": "Danh sách tập", "seasons": "Chọn phần / máy chủ", "audio": "Âm thanh", "subtitles": "Phụ đề · Caption", "quality": "Chất lượng video"][kind] ?? "Cài đặt phát"
    }

    private func settingsRow(_ kind: String, value: String) -> some View {
        Button { panel = kind } label: {
            HStack(spacing: 12) {
                MorphIcon(name: kind == "subtitles" ? "captions" : kind).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(panelTitle(kind)).font(.subheadline.weight(.semibold))
                    Text(ContentDisplayText.sourceLabels(value)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func choices(_ kind: String) -> [PlaybackChoice] {
        switch kind {
        case "audio": return playback.audioTracks
        case "subtitles": return playback.subtitleTracks
        case "quality": return playback.qualities.map { .init(id: $0.id, title: $0.title) }
        default: return episodes.reduce(into: [PlaybackChoice]()) { result, episode in
            if !result.contains(where: { $0.id == episode.season }) { result.append(.init(id: episode.season, title: episode.season)) }
        }
        }
    }

    private func selectedChoice(_ kind: String) -> String {
        switch kind {
        case "audio": return playback.audioTrack
        case "subtitles": return playback.subtitleTrack
        case "quality": return playback.quality
        default: return panelSeason
        }
    }

    private func optionPanel(_ kind: String) -> some View {
        let options = choices(kind)
        return VStack(alignment: .leading, spacing: 12) {
            Button { panel = kind == "seasons" ? "episodes" : "settings" } label: {
                Label("Quay lại", systemImage: "chevron.left").frame(minHeight: 36)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(options) { option in
                            Button {
                                // Stable option identity, never a transient menu index.
                                if kind == "seasons" {
                                    panelSeason = option.id
                                    let seasonEpisodes = episodes.filter { $0.season == option.id }
                                    if seasonEpisodes.count == 1, let single = seasonEpisodes.first {
                                        select(single)
                                    } else if let matched = seasonEpisodes.first(where: { $0.number == current.number }) {
                                        select(matched)
                                    } else {
                                        panel = "episodes"
                                    }
                                } else {
                                    playback.chooseOption?(kind, option.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(ContentDisplayText.sourceLabels(option.title)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    if selectedChoice(kind) == option.id { MorphIcon(name: "check").frame(width: 20, height: 20) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedChoice(kind) == option.id ? Color.anpinimeAccent.opacity(0.28) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(option.id)
                        }
                        if options.isEmpty {
                            Text("Luồng hiện tại không cung cấp lựa chọn này cho trình phát native.")
                                .font(.footnote).foregroundStyle(.secondary).padding(.vertical)
                        }
                        if kind == "subtitles" {
                            Text("Chỉ tắt được phụ đề rời. Chữ đã ghép vào hình không thể tắt; với nguồn có nhiều bản Vietsub/lồng tiếng, hãy đổi máy chủ trong Danh sách tập.")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        if kind == "quality" {
                            Text("Chỉ hiện mức chất lượng nguồn thực sự cung cấp. Mức chọn là giới hạn tối đa; video có thể giảm chất lượng khi mạng yếu.")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        if kind == "subtitles", options.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Cỡ chữ \(Int(playback.subtitleSize))%").font(.subheadline)
                                Slider(value: $playback.subtitleSize, in: 70...180, step: 10)
                                    .onChange(of: playback.subtitleSize) { playback.send("subtitleSize", $0) }
                                Toggle("Nền tối cho phụ đề", isOn: $playback.subtitleBackground)
                                    .onChange(of: playback.subtitleBackground) { playback.send("subtitleBackground", $0 ? 1 : 0) }
                            }.padding(.vertical, 12)
                        }
                    }
                }.onAppear { proxy.scrollTo(selectedChoice(kind), anchor: .center) }
            }
        }
    }

    private func openPanel(_ name: String) {
        hideTask?.cancel(); panelSeason = current.season
        withAnimation(.easeOut(duration: 0.2)) { panel = name }
    }
    private func closePanel() { withAnimation { panel = nil }; scheduleHide() }
    private func select(_ item: Episode) {
        playback.send("pause"); playback.reset()
        selectedEpisode = item; panel = nil; controlsVisible = true
    }
    private func retry() { playback.send("pause"); playback.reset(); attempt += 1; controlsVisible = true }
    private func scheduleHide() {
        hideTask?.cancel()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") { return }
        #endif
        guard playback.playing, !playback.loading, panel == nil, !scrubbing else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { controlsVisible = false }
        }
    }
    private func timestamp(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let seconds = Int(value)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PulsingMovieTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var illuminated = false
    let title: String
    let size: CGFloat

    var body: some View {
        ZStack {
            titleText
                .foregroundColor(.anpinimeAccent)
                .blur(radius: illuminated ? 14 : 5)
                .opacity(reduceMotion ? 0.35 : (illuminated ? 0.52 : 0.16))
                .scaleEffect(illuminated ? 1.025 : 0.985)
            titleText
                .foregroundStyle(LinearGradient(
                    colors: [.white, .white.opacity(0.92), .anpinimeAccent.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .black.opacity(0.72), radius: 18, y: 8)
                .shadow(color: .anpinimeAccent.opacity(illuminated ? 0.42 : 0.08), radius: illuminated ? 16 : 4)
                .opacity(reduceMotion ? 1 : (illuminated ? 1 : 0.68))
                .scaleEffect(reduceMotion ? 1 : (illuminated ? 1.012 : 0.992))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.45).repeatForever(autoreverses: true), value: illuminated)
        .onAppear { illuminated = true }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: size, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
    }
}

/// System volume works for both AVPlayer and iOS WebKit media.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = UIColor(Color.anpinimeAccent)
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) { }
}
