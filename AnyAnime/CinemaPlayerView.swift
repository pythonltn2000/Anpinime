import SwiftUI
import UIKit

@MainActor
final class PlaybackState: ObservableObject {
    @Published var loading = true
    @Published var buffering = false
    @Published var playing = false
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published var verification = false
    @Published var endCount = 0
    @Published var rate = 1.0
    @Published var fill = false
    @Published var volume = 1.0
    var command: ((String, Double) -> Void)?

    func send(_ name: String, _ value: Double = 0) { command?(name, value) }
    func reset() {
        loading = true; buffering = false; playing = false
        currentTime = 0; duration = 0; error = nil; verification = false
    }
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: AnimeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var pulse = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var originalBrightness = UIScreen.main.brightness
    @AppStorage("AnPinime.autoNext") private var autoNext = true
    @AppStorage("AnPinime.rememberSpeed") private var rememberSpeed = true
    @AppStorage("AnPinime.playbackRate") private var savedRate = 1.0
    @AppStorage("AnPinime.skipSeconds") private var skipSeconds = 10

    private var current: Episode { selectedEpisode ?? episode }
    private var currentIndex: Int? { episodes.firstIndex(where: { $0.id == current.id }) }
    private var nextEpisode: Episode? {
        guard let i = currentIndex, i + 1 < episodes.count, episodes[i + 1].season == current.season else { return nil }
        return episodes[i + 1]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                PlayerControllerView(episodeURL: current.url, baseURL: service.baseURL, playback: playback)
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
                            Text(error).multilineTextAlignment(.center)
                            Button("Thử phát lại") { retry() }.buttonStyle(.borderedProminent).tint(.anpinimeAccent)
                        }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                            .padding(30)
                    }
                    if let panel {
                        Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { closePanel() }
                        HStack {
                            if geometry.size.width > geometry.size.height { Spacer(minLength: 0) }
                            playerPanel(panel)
                                .frame(width: min(360, geometry.size.width - 24))
                                .frame(maxHeight: min(geometry.size.height - 16, 620))
                                .background(Color(red: 0.075, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.09)))
                                .padding(12)
                        }
                    }
                } else {
                    VStack { HStack { controlButton("xmark", "Đóng trình phát") { dismiss() }; Spacer() }; Spacer() }.padding()
                }
            }
            .foregroundColor(.white)
            .tint(.anpinimeAccent)
        }
        .statusBar(hidden: !playback.verification)
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            playback.rate = rememberSpeed ? savedRate : 1
            pulse = true
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
            AsyncImage(url: artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image("logo").resizable().scaledToFill()
            }
            .frame(width: size.width, height: size.height).clipped()
            .overlay(Color.black.opacity(0.44))
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.1), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Text("ANPINIME").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(6).foregroundColor(.white.opacity(0.65))
                Text(title).font(.system(size: size.width > 600 ? 40 : 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(3)
                    .shadow(color: .black.opacity(0.6), radius: 20)
                    .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.4))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                Text(current.title).font(.subheadline.weight(.medium)).foregroundColor(.white.opacity(0.7))
                HStack(spacing: 9) {
                    ProgressView().tint(.white.opacity(0.8))
                    Text("Đang chuẩn bị phim của bạn").font(.caption).foregroundColor(.white.opacity(0.65))
                }
            }.padding(.horizontal, 36)
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
                        Text(current.title).font(.caption).foregroundColor(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    controlButton("gearshape", "Cài đặt phát") { openPanel("settings") }
                }
                Spacer(minLength: 0)
                if !playback.loading && playback.error == nil {
                    HStack(spacing: size.width > 600 ? 65 : 36) {
                        skipButton(forward: false)
                        Button {
                            playback.send(playback.playing ? "pause" : "play")
                            scheduleHide()
                        } label: {
                            Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 32, weight: .semibold)).frame(width: 72, height: 72)
                                .background(.white.opacity(0.15), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.25)))
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
                        if let next = nextEpisode {
                            smallButton("Tập tiếp", "forward.end.fill") { select(next) }
                        }
                        Spacer(minLength: 0)
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
        Button(action: action) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
            .accessibilityLabel(label)
    }
    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: 44).background(.white.opacity(0.1), in: Capsule())
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
                    Text(kind == "episodes" ? "Danh sách tập" : "Cài đặt phát").font(.title3.bold())
                    Text(kind == "episodes" ? "\(episodes.count) tập · \(current.title)" : "Theo cách bạn thích")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                controlButton("xmark", "Đóng bảng") { closePanel() }
            }
            if kind == "episodes" { episodePanel } else { settingsPanel }
        }.padding(20)
    }

    private var episodePanel: some View {
        let seasons = episodes.reduce(into: [String]()) { if !$0.contains($1.season) { $0.append($1.season) } }
        let season = panelSeason.isEmpty ? current.season : panelSeason
        return VStack(spacing: 14) {
            if seasons.count > 1 {
                Picker("Phần", selection: $panelSeason) { ForEach(seasons, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
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
                    Slider(value: $playback.volume, in: 0...1).onChange(of: playback.volume) { playback.send("volume", $0) }
                }
                Button { closePanel(); retry() } label: { Label("Tải lại luồng phát", systemImage: "arrow.clockwise") }
            }.font(.subheadline).padding(.bottom, 8)
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
