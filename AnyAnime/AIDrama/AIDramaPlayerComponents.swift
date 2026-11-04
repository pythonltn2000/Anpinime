import SwiftUI

@MainActor
struct AIDramaVideoCanvas: View {
    @ObservedObject var session: AIDramaPlaybackSession
    let cover: URL?
    var body: some View {
        if let player = session.controller, let playback = session.playback {
            AIDramaLoadedCanvas(player: player, session: session, playback: playback, cover: cover)
        } else { AIDramaFullCover(url: cover) }
    }
}

private struct AIDramaFullCover: View {
    let url: URL?
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.black }
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false)
    }
}

@MainActor
private struct AIDramaLoadedCanvas: View {
    let player: MPVPlaybackController
    let session: AIDramaPlaybackSession
    @ObservedObject var playback: PlaybackState
    let cover: URL?
    var body: some View {
        ZStack {
            AIDramaNativeSurface(player: player, session: session).id(ObjectIdentifier(player))
            if playback.loading && !playback.playing { AIDramaFullCover(url: cover) }
        }
    }
}

@MainActor
struct AIDramaSpeedControl: View {
    @ObservedObject var playback: PlaybackState
    var body: some View {
        Menu {
            ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                Button(String(format: "%g×", rate)) {
                    playback.rate = rate
                    UserDefaults.standard.set(rate, forKey: "AnPinime.playbackRate")
                    playback.send("rate", rate)
                }
            }
        } label: {
            Text(String(format: "%.1f×", playback.rate)).font(.subheadline.bold())
                .frame(minWidth: 48, minHeight: 44).cinemaGlass(cornerRadius: 24, interactive: true)
        }.accessibilityLabel("Tốc độ phát").accessibilityIdentifier("aidrama.speed")
    }
}

@MainActor
struct AIDramaEpisodeSheet: View {
    let playlist: AIDramaPlaylist
    let selectedID: String?
    let select: (String) -> Void
    let close: () -> Void
    @State private var group = 0
    private var groups: Int { max(1, (playlist.episodes.count + 23) / 24) }
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(0..<groups, id: \.self) { index in
                            Button { group = index } label: {
                                Text("\(index * 24 + 1)–\(min((index + 1) * 24, playlist.episodes.count))")
                                    .font(.subheadline.bold()).foregroundColor(index == group ? .primary : .secondary)
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) { if index == group { Capsule().fill(Color.anpinimeAccent).frame(height: 3) } }
                            }.accessibilityIdentifier("aidrama.playlist.group.\(index)")
                        }
                    }.padding(.horizontal, 20)
                }.accessibilityIdentifier("aidrama.playlist.groups")
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(Array(playlist.episodes.dropFirst(group * 24).prefix(24))) { episode in
                            Button { select(episode.id); close() } label: {
                                VStack(spacing: 4) {
                                    Text("\(episode.number)").font(.subheadline.bold())
                                    if episode.isLocked { Image(systemName: "lock.fill").font(.caption2) }
                                }.frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundColor(selectedID == episode.id ? .anpinimeAccent : .primary)
                                    .background(selectedID == episode.id ? Color.anpinimeAccent.opacity(0.18) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Tập \(episode.number)" + (episode.isLocked ? ", đã khóa" : ""))
                                .accessibilityValue(selectedID == episode.id ? "Đang chọn" : "")
                                .accessibilityIdentifier("aidrama.playlist.episode." + episode.id)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 28)
                }.accessibilityIdentifier("aidrama.playlist.episodes")
                Spacer(minLength: 0)
            }
            .navigationTitle("Danh sách tập (\(playlist.episodes.count))").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: close) { Image(systemName: "xmark") }
                        .accessibilityLabel("Đóng danh sách tập").accessibilityIdentifier("aidrama.playlist.close")
                }
                ToolbarItem(placement: .principal) { Text(playlist.series.title).font(.headline).lineLimit(1) }
            }
        }.navigationViewStyle(.stack)
            .onAppear { group = (playlist.episodes.firstIndex { $0.id == selectedID } ?? 0) / 24 }
            .modifier(AIDramaHalfSheet())
    }
}

struct AIDramaHalfSheet: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(28) }
        else if #available(iOS 16, *) { content.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        else { content }
    }
}
