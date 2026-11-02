import SwiftUI
import UIKit

/// A portrait player independent of the existing anime/movie source and landscape player.
@MainActor
struct AIDramaPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: AIDramaPlaybackSession
    @State private var playlistPresented = false

    init(playlist: AIDramaPlaylist, provider: AIDramaProviding, initialEpisodeID: String? = nil) {
        _session = StateObject(wrappedValue: AIDramaPlaybackSession(playlist: playlist, provider: provider,
                                                                  initialEpisodeID: initialEpisodeID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AIDramaVerticalPager(session: session).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                footer
            }
            if session.resolving { ProgressView().tint(.white).accessibilityLabel("Đang tải tập phim") }
            if let playback = session.playback { AIDramaLoadingState(playback: playback) }
            if let error = session.error {
                VStack(spacing: 14) {
                    Text(error).multilineTextAlignment(.center).foregroundColor(.white)
                    Button("Thử lại") { session.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("aidrama.retry")
                }
                .padding(24).background(Color.black.opacity(0.85)).cornerRadius(16).padding(32)
                .accessibilityIdentifier("aidrama.error")
            }
            #if DEBUG
            if AIDramaDebugSupport.enabled {
                AIDramaDebugStateView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            #endif
        }
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
        .sheet(isPresented: $playlistPresented) { playlistDrawer }
        .onAppear { session.setPresented(true, sceneActive: scenePhase == .active) }
        .onChange(of: scenePhase) { session.setSceneActive($0 == .active) }
        .onDisappear {
            session.setPresented(false, sceneActive: false)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                session.setPresented(false, sceneActive: false)
                dismiss()
            } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44).background(Color.black.opacity(0.4)).clipShape(Circle())
            }
            .accessibilityLabel("Đóng trình phát")
            .accessibilityIdentifier("aidrama.close")
            VStack(alignment: .leading, spacing: 5) {
                Text(session.playlist.series.title).font(.headline).lineLimit(2)
                    .accessibilityIdentifier("aidrama.series.title")
                if let episode = session.selectedEpisode, let index = session.selectedIndex {
                    Text("\(episode.displayTitle) · \(index + 1)/\(session.playlist.episodes.count)")
                        .font(.subheadline).foregroundColor(.white.opacity(0.85))
                        .accessibilityIdentifier("aidrama.episode.index")
                        #if DEBUG
                        .accessibilityValue(AIDramaDebugSupport.enabled ? episode.id : "")
                        #endif
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
        .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button { session.togglePause() } label: {
                    Image(systemName: session.manuallyPaused ? "play.fill" : "pause.fill")
                        .font(.title2).frame(width: 48, height: 48)
                }
                .accessibilityLabel(session.manuallyPaused ? "Phát" : "Tạm dừng")
                .accessibilityIdentifier("aidrama.playpause")
                Spacer()
                Button { playlistPresented = true } label: {
                    Label("Danh sách tập (\(session.playlist.episodes.count))", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold)).padding(.vertical, 12).padding(.horizontal, 14)
                        .background(Color.white.opacity(0.16)).cornerRadius(12)
                }
                .accessibilityIdentifier("aidrama.playlist.open")
            }
            if let playback = session.playback {
                AIDramaTimeline(playback: playback) { seconds in
                    guard session.playback === playback else { return }
                    session.seek(seconds)
                }
                .id(ObjectIdentifier(playback))
            } else {
                Color.white.opacity(0.25).frame(height: 3).padding(.vertical, 12)
            }
        }
        .foregroundColor(.white).padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 16)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    private var playlistDrawer: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 12) {
                        ForEach(session.playlist.episodes) { episode in
                            Button {
                                session.selectEpisode(episode.id)
                                playlistPresented = false
                            } label: {
                                VStack(spacing: 6) {
                                    Text("Tập \(episode.number)").font(.subheadline.weight(.semibold))
                                    if episode.isLocked { Image(systemName: "lock.fill").font(.caption) }
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .padding(.vertical, 8)
                                .foregroundColor(.white)
                                .background(session.selectedEpisodeID == episode.id ? Color.accentColor : Color.white.opacity(0.12))
                                .cornerRadius(10)
                            }
                            .id(episode.id)
                            .accessibilityLabel("Tập \(episode.number)" + (episode.isLocked ? ", đã khóa" : ""))
                            .accessibilityValue(session.selectedEpisodeID == episode.id ? "Đang chọn" : "")
                            .accessibilityIdentifier("aidrama.playlist.episode." + episode.id)
                        }
                    }
                    .padding(20)
                }
                .onAppear { if let id = session.selectedEpisodeID { proxy.scrollTo(id, anchor: .center) } }
            }
            .navigationTitle("Danh sách tập (\(session.playlist.episodes.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { playlistPresented = false }
                        .accessibilityIdentifier("aidrama.playlist.close")
                }
            }
        }
        .navigationViewStyle(.stack).preferredColorScheme(.dark)
    }
}

private struct AIDramaLoadingState: View {
    @ObservedObject var playback: PlaybackState
    var body: some View {
        Group {
            if playback.loading || playback.buffering {
                ProgressView().tint(.white).accessibilityLabel("Đang tải video")
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AIDramaTimeline: View {
    @ObservedObject var playback: PlaybackState
    let seek: (Double) -> Void
    @State private var scrubbing = false
    @State private var position = 0.0

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { scrubbing ? position : min(max(0, playback.currentTime), max(1, playback.duration)) },
                                  set: { position = $0 }),
                   in: 0...max(1, playback.duration), onEditingChanged: { editing in
                if editing { position = playback.currentTime }
                else { seek(position) }
                scrubbing = editing
            })
            .tint(.white).disabled(playback.duration <= 0)
            .accessibilityLabel("Vị trí phát")
            .accessibilityIdentifier("aidrama.seek")
            HStack {
                Text(time(scrubbing ? position : playback.currentTime))
                Spacer()
                Text(time(playback.duration))
            }
            .font(.caption.monospacedDigit()).foregroundColor(.white.opacity(0.8))
        }
    }

    private func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@MainActor
private struct AIDramaEpisodePage: View {
    let episode: AIDramaEpisode
    @ObservedObject var session: AIDramaPlaybackSession

    var body: some View {
        ZStack {
            Color.black
            if session.selectedEpisodeID == episode.id, let controller = session.controller {
                AIDramaNativeSurface(player: controller, session: session).id(ObjectIdentifier(controller))
            } else if let cover = episode.coverURL ?? session.playlist.series.coverURL {
                AsyncImage(url: cover) { image in image.resizable().scaledToFit() }
                    placeholder: { Color.black }
            }
        }
        .clipped().accessibilityIdentifier("aidrama.page." + episode.id)
    }
}

/// Only the selected page may contain this surface. The session owns shutdown, including
/// when SwiftUI retains the old surface for the outgoing page transition.
@MainActor
private struct AIDramaNativeSurface: UIViewControllerRepresentable {
    let player: MPVPlaybackController
    let session: AIDramaPlaybackSession

    final class Container: UIViewController {
        var player: MPVPlaybackController?
        weak var session: AIDramaPlaybackSession?

        func mount(_ player: MPVPlaybackController, session: AIDramaPlaybackSession) {
            guard self.player !== player else { return }
            unmount()
            self.player = player
            self.session = session
            addChild(player)
            // MPV starts loading in viewDidLoad. Pause in the same main-actor turn before
            // granting playback to this visible, committed page.
            player.view.frame = view.bounds
            player.perform("pause", value: 0)
            player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(player.view)
            player.didMove(toParent: self)
            session.didAttach(player)
        }

        func unmount() {
            guard let player else { return }
            session?.didDetach(player)
            player.willMove(toParent: nil)
            player.view.removeFromSuperview()
            player.removeFromParent()
            self.player = nil
            session = nil
        }
    }

    func makeUIViewController(context: Context) -> Container {
        let container = Container()
        container.view.backgroundColor = .black
        container.mount(player, session: session)
        return container
    }
    func updateUIViewController(_ controller: Container, context: Context) { controller.mount(player, session: session) }
    static func dismantleUIViewController(_ controller: Container, coordinator: ()) { controller.unmount() }
}

@MainActor
private struct AIDramaVerticalPager: UIViewControllerRepresentable {
    @ObservedObject var session: AIDramaPlaybackSession

    final class Pager: UIPageViewController {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    }

    final class EpisodePageController: UIHostingController<AIDramaEpisodePage> {
        let episodeID: String
        init(episode: AIDramaEpisode, session: AIDramaPlaybackSession) {
            episodeID = episode.id
            super.init(rootView: AIDramaEpisodePage(episode: episode, session: session))
            view.backgroundColor = .black
        }
        @objc required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    final class WeakPage {
        weak var value: EpisodePageController?
        init(_ value: EpisodePageController) { self.value = value }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let session: AIDramaPlaybackSession
        // UIKit retains its visible/preloaded pages. Weak caching both bounds memory and
        // avoids making a second host for an episode UIKit still holds during a transition.
        private var pages: [String: WeakPage] = [:]

        init(session: AIDramaPlaybackSession) { self.session = session }

        func page(_ id: String) -> EpisodePageController? {
            if let cached = pages[id]?.value { return cached }
            guard let episode = session.playlist.episodes.first(where: { $0.id == id }) else { return nil }
            let page = EpisodePageController(episode: episode, session: session)
            pages[id] = WeakPage(page)
            return page
        }

        func id(_ controller: UIViewController?) -> String? { (controller as? EpisodePageController)?.episodeID }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(viewController, offset: -1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(viewController, offset: 1)
        }

        private func neighbor(_ controller: UIViewController, offset: Int) -> UIViewController? {
            guard let id = id(controller), let index = session.playlist.episodes.firstIndex(where: { $0.id == id }),
                  session.playlist.episodes.indices.contains(index + offset) else { return nil }
            return page(session.playlist.episodes[index + offset].id)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            session.beginPageTransition()
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            session.finishPageTransition(episodeID: id(pageViewController.viewControllers?.first), completed: completed)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIViewController(context: Context) -> Pager {
        let pager = Pager(transitionStyle: .scroll, navigationOrientation: .vertical)
        pager.view.backgroundColor = .black
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        if let id = session.selectedEpisodeID, let page = context.coordinator.page(id) {
            pager.setViewControllers([page], direction: .forward, animated: false)
        }
        return pager
    }

    func updateUIViewController(_ pager: Pager, context: Context) {
        guard !session.transitioning, let id = session.selectedEpisodeID,
              context.coordinator.id(pager.viewControllers?.first) != id,
              let page = context.coordinator.page(id) else { return }
        // Playlist jumps and EOF use the same committed selection, without resolving
        // intermediate pages or racing an interactive transition.
        pager.setViewControllers([page], direction: .forward, animated: false)
    }

    static func dismantleUIViewController(_ pager: Pager, coordinator: Coordinator) {
        pager.dataSource = nil
        pager.delegate = nil
        // Presentation cleanup belongs to the close action/onDisappear (with deinit
        // as a fallback). Publishing session changes while SwiftUI destroys this
        // graph re-enters GraphHost and triggers a Swift exclusivity abort.
    }
}
