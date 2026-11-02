import SwiftUI
import UniformTypeIdentifiers

struct PlayerSettingsPanel: View {
    @ObservedObject var playback: PlaybackState
    let initialTab: String
    let title: String
    let source: String
    let close: () -> Void
    let reload: () -> Void
    @State private var tab = "audio"
    @State private var importing = false
    @State private var importSlot = "subtitles"
    @State private var importError: String?
    @AppStorage("AnPinime.autoNext") private var autoNext = true
    @AppStorage("AnPinime.rememberSpeed") private var rememberSpeed = true
    @AppStorage("AnPinime.playbackRate") private var savedRate = 1.0
    @AppStorage("AnPinime.skipSeconds") private var skipSeconds = 10
    private let tabs = [("audio", "Âm thanh", "speaker.wave.2"), ("subtitles", "Phụ đề", "captions.bubble"),
                        ("display", "Hiển thị", "textformat.size"), ("speed", "Tốc độ", "speedometer"),
                        ("general", "Chung", "slider.horizontal.3"), ("info", "Thông tin", "info.circle")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cài đặt phát").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 40, height: 40) }.accessibilityLabel("Đóng cài đặt")
            }.padding(.horizontal, 18)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(tabs, id: \.0) { item in
                            Button { tab = item.0 } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: item.2).font(.system(size: 18))
                                    Text(item.1).font(.system(size: 12, weight: .semibold))
                                }.frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(tab == item.0 ? Color.anpinimeAccent.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundColor(tab == item.0 ? .anpinimeAccent : .white.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                    }.padding(7)
                }.frame(width: 88)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { content }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }.id(tab)
            }
        }
        .foregroundColor(.white).tint(.anpinimeAccent)
        .background(Color(white: 0.06).opacity(0.97), in: RoundedRectangle(cornerRadius: 22))
        .onAppear { tab = tabs.contains(where: { $0.0 == initialTab }) ? initialTab : "audio" }
        .onChange(of: playback.subtitleStyle) { style in style.save(); playback.send("subtitleStyle") }
        .fileImporter(isPresented: $importing, allowedContentTypes: ["srt", "ass", "ssa", "vtt"].compactMap { UTType(filenameExtension: $0) } + [.data]) { result in
            do {
                let original = try result.get()
                guard ["srt", "ass", "ssa", "vtt"].contains(original.pathExtension.lowercased()) else { throw SubtitleImportError.invalidFormat }
                let scoped = original.startAccessingSecurityScopedResource()
                defer { if scoped { original.stopAccessingSecurityScopedResource() } }
                let size = (try original.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { throw SubtitleImportError.tooLarge }
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Subtitles", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(UUID().uuidString + "-" + original.lastPathComponent)
                try FileManager.default.copyItem(at: original, to: destination)
                playback.importSubtitle?(destination, importSlot)
                importError = nil
            } catch { importError = error.localizedDescription }
        }
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case "audio":
            heading("Âm thanh")
            trackList(playback.audioTracks, kind: "audio", selected: playback.audioTrack)
            Text("Âm lượng").font(.subheadline)
            Slider(value: $playback.volume, in: 0...1).onChange(of: playback.volume) { playback.send("volume", $0) }
            SystemVolumeSlider().frame(height: 30)
        case "subtitles":
            subtitleLane("Phụ đề chính", kind: "subtitles", selected: playback.subtitleTrack)
            Divider()
            if playback.supportsAdvancedSubtitles {
                subtitleLane("Phụ đề phụ", kind: "secondarySubtitles", selected: playback.secondarySubtitleTrack)
            } else {
                Text("Phụ đề kép và file rời dùng cho luồng phát trực tiếp. Trình phát của trang chỉ hỗ trợ phụ đề chính.").font(.footnote).foregroundStyle(.secondary)
            }
            if let importError { Text(ContentDisplayText.sourceLabels(importError)).font(.footnote).foregroundColor(.orange) }
            Text("Phụ đề phụ hiển thị phía trên. Chữ đã ghép vào hình không thể tắt.").font(.caption).foregroundStyle(.secondary)
        case "display":
            heading("Hiển thị phụ đề")
            Picker("Phông chữ", selection: $playback.subtitleStyle.font) {
                ForEach(["Arial", "Helvetica", "Times New Roman", "Menlo"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
            labeledSlider("Cỡ chữ", value: $playback.subtitleStyle.size, range: 18...80, unit: "")
            labeledSlider("Khoảng cách tới mép", value: $playback.subtitleStyle.margin, range: 0...150, unit: "")
            Picker("Căn chỉnh", selection: $playback.subtitleStyle.alignment) {
                Text("Trái").tag("left"); Text("Giữa").tag("center"); Text("Phải").tag("right")
            }.pickerStyle(.segmented)
            ColorPicker("Màu chữ", selection: color(\SubtitleStyle.foreground), supportsOpacity: true)
            ColorPicker("Màu nền", selection: color(\SubtitleStyle.background), supportsOpacity: true)
            ColorPicker("Màu viền", selection: color(\SubtitleStyle.outline), supportsOpacity: true)
            if playback.supportsAdvancedSubtitles {
            labeledSlider("Độ trễ phụ đề chính", value: $playback.subtitleStyle.delay, range: -10...10, unit: "s", step: 0.1)
            labeledSlider("Độ trễ phụ đề phụ", value: $playback.subtitleStyle.secondaryDelay, range: -10...10, unit: "s", step: 0.1)
            }
            Text("Phụ đề ảnh (PGS/VobSub) giữ kiểu chữ của video.").font(.caption).foregroundStyle(.secondary)
            Button("Khôi phục hiển thị mặc định") { playback.subtitleStyle = SubtitleStyle() }
        case "speed":
            heading("Tốc độ phát · " + String(format: "%g×", playback.rate))
            Slider(value: $playback.rate, in: 0.25...3, step: 0.05).onChange(of: playback.rate) { savedRate = $0; playback.send("rate", $0) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))], spacing: 8) {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3], id: \.self) { rate in
                    Button(String(format: "%g×", rate)) { playback.rate = rate; savedRate = rate; playback.send("rate", rate) }
                        .buttonStyle(.bordered).tint(playback.rate == rate ? .anpinimeAccent : .gray)
                }
            }
            Toggle("Ghi nhớ tốc độ", isOn: $rememberSpeed)
        case "general":
            heading("Chung")
            Toggle("Lấp đầy màn hình", isOn: $playback.fill).onChange(of: playback.fill) { playback.send("fit", $0 ? 1 : 0) }
            Toggle("Tự phát tập tiếp theo", isOn: $autoNext)
            Picker("Bước tua", selection: $skipSeconds) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) giây").tag($0) } }.pickerStyle(.menu)
            Button(action: reload) { Label("Tải lại video", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
        default:
            heading(title)
            info("Nguồn", source)
            info("Trình phát", playback.engine)
            info("Định dạng", playback.mediaInfo.isEmpty ? "Đang đọc thông tin video…" : playback.mediaInfo)
            info("Âm thanh", "\(playback.audioTracks.count) track")
            info("Phụ đề", "\(playback.subtitleTracks.filter { $0.id != "off" }.count) track")
            info("Thời lượng", "\(Int(playback.duration / 60)) phút")
        }
    }
    private func subtitleLane(_ name: String, kind: String, selected: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(name)
            trackList(playback.subtitleTracks, kind: kind, selected: selected)
            Button { importSlot = kind; importing = true } label: { Label("Chọn file trên điện thoại", systemImage: "folder") }
                .disabled(!playback.supportsAdvancedSubtitles)
        }
    }
    private func trackList(_ tracks: [PlaybackChoice], kind: String, selected: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if tracks.isEmpty { Text(playback.loading ? "Đang đọc track…" : "Video không có track này.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(tracks) { track in
                Button { playback.chooseOption?(kind, track.id) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: selected == track.id ? "checkmark.circle.fill" : "circle").foregroundColor(selected == track.id ? .anpinimeAccent : .gray)
                        Text(ContentDisplayText.sourceLabels(track.title)).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 38).padding(.vertical, 3)
                }.buttonStyle(.plain)
            }
        }
    }
    private func heading(_ value: String) -> some View { Text(ContentDisplayText.sourceLabels(value)).font(.headline) }
    private func info(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(ContentDisplayText.sourceLabels(value)).font(.subheadline).textSelection(.enabled) }
    }
    private func labeledSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(name); Spacer(); Text(String(format: step < 1 ? "%.1f%@" : "%.0f%@", value.wrappedValue, unit)).monospacedDigit() }.font(.subheadline)
            Slider(value: value, in: range, step: step)
        }
    }
    private func color(_ key: WritableKeyPath<SubtitleStyle, String>) -> Binding<Color> {
        Binding(get: {
            let hex = playback.subtitleStyle[keyPath: key].replacingOccurrences(of: "#", with: "")
            let value = UInt64(hex, radix: 16) ?? 0xFFFFFFFF
            return Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: Double((value >> 24) & 255) / 255)
        }, set: { color in
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            playback.subtitleStyle[keyPath: key] = String(format: "#%02X%02X%02X%02X", Int(a * 255), Int(r * 255), Int(g * 255), Int(b * 255))
        })
    }
}

private enum SubtitleImportError: LocalizedError {
    case invalidFormat, tooLarge
    var errorDescription: String? { self == .invalidFormat ? "Chọn file SRT, ASS, SSA hoặc VTT." : "File phụ đề vượt quá 8 MB." }
}
