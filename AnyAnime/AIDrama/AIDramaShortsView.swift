import Combine
import SwiftUI
import UIKit

/// The committed video plus, at most, one silent prepared neighbor. The bounded
/// temporary media cache downloads the next five/ten clips without more decoders.
@MainActor
final class AIDramaShortsStore: ObservableObject {
    @Published private(set) var videos: [AIDramaShortVideo] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var session: AIDramaPlaybackSession?
    @Published private(set) var warmSession: AIDramaPlaybackSession?
    @Published private(set) var warmID: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    private let provider: AIDramaProviding
    private let mediaCache: AIDramaMediaCache
    private var request: Task<AIDramaShortFeedPage, Error>?
    private var warming: Task<Void, Never>?
    private var memoryWarning: AnyCancellable?
    private var generation = UUID()
    private var active = false
    private var sceneActive = false
    var selected: AIDramaShortVideo? { videos.first { $0.id == selectedID } }

    init(provider: AIDramaProviding) {
        let cache = AIDramaMediaCache(provider: provider)
        self.provider = cache; self.mediaCache = cache
        memoryWarning = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.discardWarmVideo()
                if let cache = self?.mediaCache { Task { await cache.stop(purge: true) } }
            }
    }

    func setActive(_ value: Bool, sceneActive: Bool) {
        active = value; self.sceneActive = sceneActive
        session?.setPresented(value, sceneActive: sceneActive)
        if !value {
            request?.cancel(); request = nil; generation = UUID(); loading = false
            discardWarmVideo()
            Task { await mediaCache.stop() }
        } else { scheduleWarmVideo(); prepareWindow() }
    }

    func setSceneActive(_ value: Bool) {
        sceneActive = value; session?.setSceneActive(value)
        if value { scheduleWarmVideo(); prepareWindow() }
        else { discardWarmVideo(); Task { await mediaCache.stop() } }
    }

    func select(_ id: String) {
        guard let video = videos.first(where: { $0.id == id }) else { return }
        if selectedID != id || session == nil {
            session?.setPresented(false, sceneActive: false)
            selectedID = id
            if warmID == id, let prepared = warmSession {
                warming?.cancel(); warming = nil
                warmSession = nil; warmID = nil
                session = prepared
                prepared.promotePreloadedVideo()
                if prepared.error != nil { prepared.retry() }
            } else {
                discardWarmVideo()
                session = makeSession(video, preloading: false)
            }
        }
        session?.setPresented(active, sceneActive: sceneActive)
        scheduleWarmVideo()
        prepareWindow()
        if let index = videos.firstIndex(where: { $0.id == id }), index >= videos.count - preloadCount - 1, error == nil {
            Task { await loadMore() }
        }
    }

    private var preloadCount: Int { UserDefaults.standard.integer(forKey: "AnPinime.AIDrama.preloadCount") == 10 ? 10 : 5 }
    private func prepareWindow() {
        guard active, sceneActive, let index = videos.firstIndex(where: { $0.id == selectedID }) else { return }
        guard session?.playback?.loading == false else { return }
        let next = Array(videos.dropFirst(index + 1).prefix(preloadCount).map(\.episode))
        let previous = Array(videos.prefix(index).suffix(3).map(\.episode))
        let current = selectedID
        Task { await mediaCache.prepare(next: next, previous: previous, current: current) }
        if next.count < preloadCount, hasMore, !loading, error == nil { Task { await loadMore() } }
    }

    private func makeSession(_ video: AIDramaShortVideo, preloading: Bool) -> AIDramaPlaybackSession {
        let playlist = AIDramaPlaylist(series: video.series, episodes: [video.episode], reportedTotal: nil)
        return AIDramaPlaybackSession(playlist: playlist, provider: provider,
                                     initialEpisodeID: video.episode.id, preloading: preloading)
    }

    private func discardWarmVideo() {
        warming?.cancel(); warming = nil
        warmSession?.setPresented(false, sceneActive: false)
        warmSession = nil; warmID = nil
    }

    private func scheduleWarmVideo() {
        guard active, sceneActive, warming == nil, warmSession == nil,
              let index = videos.firstIndex(where: { $0.id == selectedID }),
              videos.indices.contains(index + 1) else { return }
        let currentID = selectedID, next = videos[index + 1]
        warming = Task { [weak self] in
            // Let the visible video win the first network/decoder work.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, self.active, self.sceneActive,
                      self.selectedID == currentID else { return }
                if self.session?.error != nil { self.warming = nil; return }
                if self.session?.playback?.loading == false { break }
            }
            guard !Task.isCancelled, let self, self.active, self.sceneActive,
                  self.selectedID == currentID else { return }
            self.prepareWindow()
            self.warmID = next.id
            let prepared = self.makeSession(next, preloading: true)
            self.warmSession = prepared
            prepared.setPresented(true, sceneActive: true)
            // Do not retain an old signed URL indefinitely while the user watches.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, self.warmSession === prepared else { return }
            self.discardWarmVideo()
        }
    }

    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist { try await mediaCache.playlist(for: series) }

    func loadMore() async {
        guard active, !loading, hasMore else { return }
        loading = true; error = nil
        let token = UUID(); generation = token
        let ids = videos.map(\.id), provider = provider
        let task = Task { try await provider.shortFeed(loadedVideoIDs: ids) }
        request = task
        defer { if generation == token { loading = false; request = nil } }
        do {
            let page = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard generation == token, active else { return }
            var seen = Set(videos.map(\.id))
            let additions = page.videos.filter { seen.insert($0.id).inserted }
            videos.append(contentsOf: additions)
            hasMore = page.hasMore && !additions.isEmpty
            if selectedID == nil, let first = videos.first { select(first.id) }
            else { scheduleWarmVideo(); prepareWindow() }
        } catch {
            guard generation == token, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }
    deinit { request?.cancel(); warming?.cancel() }
}

@MainActor
struct AIDramaShortsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var feed: AIDramaShortsStore
    @State private var fullscreen = false
    @State private var episodePlaylist: AIDramaPlaylist?
    @State private var openingEpisodes = false
    @State private var episodeError: String?
    @State private var pendingEpisode: (AIDramaSeries, String)?
    @State private var episodeTask: Task<Void, Never>?
    let active: Bool
    let openAll: (AIDramaSeries, String, @escaping () -> Void) -> Void

    init(provider: AIDramaProviding, active: Bool, openAll: @escaping (AIDramaSeries, String, @escaping () -> Void) -> Void) {
        _feed = StateObject(wrappedValue: AIDramaShortsStore(provider: provider))
        self.active = active; self.openAll = openAll
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !feed.videos.isEmpty {
                AIDramaShortsPager(feed: feed, fullscreen: fullscreen, showFullscreen: { fullscreen = true }, openAll: playAll)
                    .ignoresSafeArea(edges: .top)
            }
            if feed.videos.isEmpty {
                VStack(spacing: 16) {
                    if feed.loading { ProgressView().tint(.white) }
                    else {
                        Text(feed.error ?? "Chưa có phim ngắn.").multilineTextAlignment(.center)
                        Button("Thử lại") { Task { await feed.loadMore() } }.buttonStyle(.bordered)
                    }
                }.padding(24)
            } else if let error = feed.error {
                VStack { Spacer(); Button("Tải tiếp · " + error) { Task { await feed.loadMore() } }.font(.caption).padding(12) }
            }
        }
        .foregroundColor(.white).preferredColorScheme(.dark)
        .overlay { if openingEpisodes { ProgressView().tint(.white).padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .sheet(isPresented: Binding(get: { episodePlaylist != nil }, set: { if !$0 { episodePlaylist = nil } }), onDismiss: {
            if let pending = pendingEpisode {
                pendingEpisode = nil
                openEpisode(pending.0, pending.1)
            }
        }) {
            if let playlist = episodePlaylist {
                AIDramaEpisodeSheet(playlist: playlist, selectedID: feed.selected?.episode.id,
                    select: { pendingEpisode = (playlist.series, $0) }, close: { episodePlaylist = nil })
            }
        }
        .alert("Chưa tải được danh sách tập", isPresented: Binding(get: { episodeError != nil }, set: { if !$0 { episodeError = nil } })) {
            Button("Đóng") { episodeError = nil }
        } message: { Text(episodeError ?? "") }
        .background(AIDramaShortsFullscreenPresenter(session: feed.session, presented: $fullscreen).frame(width: 0, height: 0))
        .task(id: active) {
            feed.setActive(active, sceneActive: scenePhase == .active)
            if active, feed.videos.isEmpty { await feed.loadMore() }
        }
        .onChange(of: scenePhase) { feed.setSceneActive($0 == .active) }
        .onChange(of: active) { if !$0 { fullscreen = false } }
        .onDisappear {
            if !fullscreen, episodePlaylist == nil { episodeTask?.cancel() }
            // A full-screen cover hides this view without leaving the feed.
            if !fullscreen { feed.setActive(false, sceneActive: false) }
        }
    }

    private func playAll(_ item: AIDramaShortVideo) {
        episodeTask?.cancel(); openingEpisodes = true
        episodeTask = Task { @MainActor in
            defer { openingEpisodes = false }
            do {
                let playlist = try await feed.playlist(for: item.series)
                try Task.checkCancellation()
                episodePlaylist = playlist
            } catch { if !Task.isCancelled { episodeError = error.localizedDescription } }
        }
    }

    private func openEpisode(_ series: AIDramaSeries, _ id: String) {
        openAll(series, id) {
            feed.session?.setPaused(false)
            feed.setActive(false, sceneActive: false)
        }
    }
}

@MainActor
private struct AIDramaShortsControls: View {
    @ObservedObject var session: AIDramaPlaybackSession
    let item: AIDramaShortVideo
    let fullscreen: () -> Void
    let openAll: () -> Void
    @State private var settingsPresented = false
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button { settingsPresented = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        .cinemaGlass(cornerRadius: 22, interactive: true)
                }.accessibilityLabel("Cài đặt phát").accessibilityIdentifier("aidrama.shorts.settings")
            }.padding(.horizontal, 20).padding(.top, 60)
            Spacer()
            if session.resolving { ProgressView().tint(.white) }
            if let error = session.error {
                Text(error).font(.subheadline).multilineTextAlignment(.center).padding(16)
                Button("Thử phát lại") { session.retry() }.buttonStyle(.bordered)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(item.series.title).font(.title3.bold()).lineLimit(2)
                    .accessibilityIdentifier("aidrama.shorts.title")
                Text("Tập \(item.episode.number)").font(.subheadline).foregroundColor(.white.opacity(0.8))
                HStack(spacing: 10) {
                    Button { session.togglePause() } label: {
                        Image(systemName: session.manuallyPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(session.manuallyPaused ? "Phát" : "Tạm dừng")
                    Button(action: openAll) {
                        Label("Tập \(item.episode.number)" + (item.series.episodeCount.map { "/\($0)" } ?? "") + " ⌃", systemImage: "list.bullet.rectangle")
                            .font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.8).padding(12).cinemaGlass(cornerRadius: 24, interactive: true)
                    }.accessibilityIdentifier("aidrama.shorts.all")
                    #if DEBUG
                    .accessibilityValue(AIDramaDebugSupport.enabled ? "\(item.series.id)|\(item.episode.id)|\(item.episode.number)|\(item.series.episodeCount ?? 0)" : "")
                    #endif
                    if let playback = session.playback { AIDramaSpeedControl(playback: playback) }
                    Spacer(minLength: 0)
                    if item.isLandscape {
                        Button(action: fullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.accessibilityLabel("Xem toàn màn hình").accessibilityIdentifier("aidrama.shorts.fullscreen")
                    }
                }
            }.padding(20).padding(.top, 30)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }.buttonStyle(.plain)
            .sheet(isPresented: $settingsPresented) {
                if let playback = session.playback {
                    PlayerSettingsPanel(playback: playback, initialTab: "audio", title: item.series.title,
                        source: "Phim AI", close: { settingsPresented = false },
                        reload: { settingsPresented = false; session.retry() })
                        .preferredColorScheme(.dark).modifier(AIDramaHalfSheet())
                }
            }
    }
}

@MainActor
private struct AIDramaShortsPage: View {
    let item: AIDramaShortVideo
    @ObservedObject var feed: AIDramaShortsStore
    let fullscreen: Bool
    let showFullscreen: () -> Void
    let openAll: (AIDramaShortVideo) -> Void
    var body: some View {
        ZStack {
            Color.black
            if feed.selectedID == item.id, let session = feed.session {
                if !fullscreen {
                    AIDramaVideoCanvas(session: session, cover: item.series.coverURL)
                    AIDramaShortsControls(session: session, item: item, fullscreen: showFullscreen) { openAll(item) }
                }
                #if DEBUG
                if AIDramaDebugSupport.enabled, !fullscreen {
                    AIDramaDebugStateView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                #endif
            } else if feed.warmID == item.id, let prepared = feed.warmSession {
                AIDramaVideoCanvas(session: prepared, cover: item.series.coverURL)
            } else {
                AIDramaFullCover(url: item.series.coverURL)
            }
        }.clipped()
    }
}

@MainActor
private struct AIDramaShortsSurface: View {
    @ObservedObject var session: AIDramaPlaybackSession
    var body: some View {
        if let controller = session.controller {
            AIDramaNativeSurface(player: controller, session: session).id(ObjectIdentifier(controller))
                .accessibilityIdentifier("aidrama.shorts.video")
        }
    }
}

/// A native full-screen controller owns orientation and containment independently
/// of SwiftUI's tab/page layout. It borrows the same player for this presentation.
@MainActor
struct AIDramaShortsFullscreenPresenter: UIViewControllerRepresentable {
    let session: AIDramaPlaybackSession?
    @Binding var presented: Bool
    func makeUIViewController(context: Context) -> Anchor { Anchor() }
    func updateUIViewController(_ anchor: Anchor, context: Context) {
        anchor.session = session; anchor.wanted = presented
        anchor.close = { presented = false }
        anchor.synchronize()
    }
    static func dismantleUIViewController(_ anchor: Anchor, coordinator: ()) { anchor.finish(animated: false) }

    final class Anchor: UIViewController {
        var session: AIDramaPlaybackSession?
        var wanted = false
        var close: (() -> Void)?
        var fullscreen: Fullscreen?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); synchronize() }
        func synchronize() {
            if !wanted { finish(animated: true); return }
            guard isViewLoaded, view.window != nil else { return }
            if fullscreen == nil, presentedViewController == nil, let session {
                let player = Fullscreen(session: session, close: { [weak self] in
                    guard let self else { return }
                    self.wanted = false
                    self.finish(animated: true)
                    self.close?()
                })
                player.modalPresentationStyle = .fullScreen
                fullscreen = player
                AnPinimeAppDelegate.orientationMask = .landscape
                present(player, animated: true)
            }
        }
        func finish(animated: Bool) {
            guard let fullscreen else { return }
            self.fullscreen = nil
            let scene = fullscreen.viewIfLoaded?.window?.windowScene ?? viewIfLoaded?.window?.windowScene
            fullscreen.dismiss(animated: animated) {
                fullscreen.unmount()
                PlayerOrientation.setLandscape(false, scene: scene)
            }
        }
    }

    final class Fullscreen: UIViewController {
        let session: AIDramaPlaybackSession
        let close: () -> Void
        private var player: MPVPlaybackController?
        private var observations = Set<AnyCancellable>()
        private var appeared = false
        private let exit = UIButton(type: .system)
        private let pause = UIButton(type: .system)
        #if DEBUG
        private var debugHost: UIHostingController<AIDramaDebugStateView>?
        #endif
        init(session: AIDramaPlaybackSession, close: @escaping () -> Void) {
            self.session = session; self.close = close
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:)") }
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
        override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
        override var prefersStatusBarHidden: Bool { true }
        override var prefersHomeIndicatorAutoHidden: Bool { true }
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black; view.accessibilityViewIsModal = true
            configure(exit, symbol: "arrow.down.right.and.arrow.up.left", label: "Thoát toàn màn hình", action: #selector(exitPressed))
            exit.accessibilityIdentifier = "aidrama.shorts.fullscreen"
            configure(pause, symbol: "pause.fill", label: "Tạm dừng", action: #selector(pausePressed))
            session.$manuallyPaused.receive(on: RunLoop.main).sink { [weak self] value in
                self?.pause.setImage(UIImage(systemName: value ? "play.fill" : "pause.fill"), for: .normal)
                self?.pause.accessibilityLabel = value ? "Phát" : "Tạm dừng"
            }.store(in: &observations)
            session.$controller.receive(on: RunLoop.main).sink { [weak self] _ in self?.mountIfVisible() }.store(in: &observations)
            #if DEBUG
            if AIDramaDebugSupport.enabled {
                let host = UIHostingController(rootView: AIDramaDebugStateView(session: session))
                debugHost = host; addChild(host); host.view.backgroundColor = .clear
                view.addSubview(host.view); host.didMove(toParent: self)
            }
            #endif
        }
        private func configure(_ button: UIButton, symbol: String, label: String, action: Selector) {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .white; button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            button.layer.cornerRadius = 24; button.accessibilityLabel = label
            button.addTarget(self, action: action, for: .touchUpInside); view.addSubview(button)
        }
        @objc private func exitPressed() { close() }
        @objc private func pausePressed() { session.togglePause() }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared = true
            PlayerOrientation.setLandscape(true, scene: view.window?.windowScene)
            mountIfVisible()
        }
        private func mountIfVisible() {
            guard appeared, viewIfLoaded?.window != nil, let current = session.controller, player !== current else { return }
            unmount()
            if let previous = current.parent as? AIDramaNativeSurface.Container { previous.unmount() }
            else if current.parent != nil {
                current.willMove(toParent: nil); current.view.removeFromSuperview(); current.removeFromParent()
            }
            player = current; addChild(current)
            current.view.frame = view.bounds; current.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            current.view.isAccessibilityElement = true; current.view.accessibilityIdentifier = "aidrama.shorts.video"
            view.insertSubview(current.view, at: 0); current.didMove(toParent: self)
            session.didAttach(current)
            view.setNeedsLayout()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            player?.view.transform = .identity; player?.view.frame = view.bounds
            player?.view.setNeedsLayout(); player?.view.layoutIfNeeded()
            exit.frame = CGRect(x: view.safeAreaInsets.left + 12, y: 8, width: 48, height: 48)
            pause.frame = CGRect(x: view.bounds.width - view.safeAreaInsets.right - 60, y: 8, width: 48, height: 48)
            #if DEBUG
            debugHost?.view.frame = CGRect(x: view.safeAreaInsets.left, y: max(0, view.bounds.height - 120), width: 48, height: 120)
            #endif
        }
        func unmount() {
            guard let player else { return }
            if player.parent === self {
                session.didDetach(player); player.willMove(toParent: nil)
                player.view.removeFromSuperview(); player.removeFromParent()
            }
            self.player = nil
        }
    }
}

/// Native paging gives continuous finger-following movement, velocity-based settling
/// and cancelable swipes. Controls live INSIDE the scroll view so footer drags also page.
@MainActor
private struct AIDramaShortsPager: UIViewControllerRepresentable {
    @ObservedObject var feed: AIDramaShortsStore
    let fullscreen: Bool
    let showFullscreen: () -> Void
    let openAll: (AIDramaShortVideo) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> Pager {
        let pager = Pager()
        pager.scroll.delegate = context.coordinator
        context.coordinator.owner = pager
        context.coordinator.update(self)
        return pager
    }
    func updateUIViewController(_ pager: Pager, context: Context) { context.coordinator.update(self) }
    static func dismantleUIViewController(_ pager: Pager, coordinator: Coordinator) { pager.scroll.delegate = nil }

    final class Pager: UIViewController {
        let scroll = UIScrollView()
        var didLayout: (() -> Void)?
        override func loadView() {
            view = UIView(); view.backgroundColor = .black
            scroll.isPagingEnabled = true; scroll.showsVerticalScrollIndicator = false
            scroll.contentInsetAdjustmentBehavior = .never; scroll.alwaysBounceVertical = true
            scroll.scrollsToTop = false; scroll.delaysContentTouches = false
            scroll.frame = view.bounds; scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scroll)
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); didLayout?() }
    }
    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var owner: Pager?
        private var configuration: AIDramaShortsPager?
        private var pages: [Int: UIHostingController<AIDramaShortsPage>] = [:]
        private var lastSize = CGSize.zero
        func update(_ configuration: AIDramaShortsPager) {
            self.configuration = configuration
            guard let owner else { return }
            owner.loadViewIfNeeded()
            owner.didLayout = { [weak self] in self?.layout() }
            layout()
        }
        private func layout() {
            guard let owner, let config = configuration else { return }
            let scroll = owner.scroll, size = scroll.bounds.size
            guard size.height > 0, size.width > 0,
                  let index = config.feed.videos.firstIndex(where: { $0.id == config.feed.selectedID }) else { return }
            owner.view.accessibilityElementsHidden = config.fullscreen
            scroll.isScrollEnabled = !config.fullscreen
            scroll.contentSize = CGSize(width: size.width, height: size.height * CGFloat(config.feed.videos.count))
            let nearby = Set(max(0, index - 1)...min(config.feed.videos.count - 1, index + 1))
            for key in Array(pages.keys) where !nearby.contains(key) {
                guard let page = pages.removeValue(forKey: key) else { continue }
                page.willMove(toParent: nil); page.view.removeFromSuperview(); page.removeFromParent()
            }
            for number in nearby {
                let content = AIDramaShortsPage(item: config.feed.videos[number], feed: config.feed,
                    fullscreen: config.fullscreen, showFullscreen: config.showFullscreen, openAll: config.openAll)
                let page: UIHostingController<AIDramaShortsPage>
                if let existing = pages[number] { page = existing; page.rootView = content }
                else {
                    page = UIHostingController(rootView: content); pages[number] = page
                    owner.addChild(page); page.view.backgroundColor = .black
                    scroll.addSubview(page.view); page.didMove(toParent: owner)
                }
                page.view.frame = CGRect(x: 0, y: CGFloat(number) * size.height, width: size.width, height: size.height)
            }
            if !scroll.isDragging && !scroll.isDecelerating {
                let target = CGPoint(x: 0, y: CGFloat(index) * size.height)
                if scroll.contentOffset != target || lastSize != size { scroll.setContentOffset(target, animated: false) }
            }
            lastSize = size
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { configuration?.feed.session?.beginPageTransition() }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle(scrollView) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settle(scrollView) } }
        private func settle(_ scroll: UIScrollView) {
            guard let config = configuration, scroll.bounds.height > 0 else { return }
            let index = Int((scroll.contentOffset.y / scroll.bounds.height).rounded())
            if config.feed.videos.indices.contains(index), config.feed.videos[index].id != config.feed.selectedID {
                config.feed.select(config.feed.videos[index].id)
            } else { config.feed.session?.finishPageTransition(episodeID: nil, completed: false) }
            layout()
        }
    }
}
