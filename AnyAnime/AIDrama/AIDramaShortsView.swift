import Combine
import SwiftUI
import UIKit

/// The committed video plus, at most, one silent prepared neighbor. Signed URLs
/// and decoded frames stay in memory and are discarded on leaving the feed.
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
    private var request: Task<AIDramaShortFeedPage, Error>?
    private var warming: Task<Void, Never>?
    private var memoryWarning: AnyCancellable?
    private var generation = UUID()
    private var active = false
    private var sceneActive = false
    var selected: AIDramaShortVideo? { videos.first { $0.id == selectedID } }

    init(provider: AIDramaProviding) {
        self.provider = provider
        memoryWarning = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in self?.discardWarmVideo() }
    }

    func setActive(_ value: Bool, sceneActive: Bool) {
        active = value; self.sceneActive = sceneActive
        session?.setPresented(value, sceneActive: sceneActive)
        if !value {
            request?.cancel(); request = nil; generation = UUID(); loading = false
            discardWarmVideo()
        } else { scheduleWarmVideo() }
    }

    func setSceneActive(_ value: Bool) {
        sceneActive = value; session?.setSceneActive(value)
        if value { scheduleWarmVideo() } else { discardWarmVideo() }
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
        if let index = videos.firstIndex(where: { $0.id == id }), index >= videos.count - 2, error == nil {
            Task { await loadMore() }
        }
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
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, self.active, self.sceneActive,
                      self.selectedID == currentID else { return }
                if self.session?.playback?.loading == false { break }
            }
            guard !Task.isCancelled, let self, self.active, self.sceneActive,
                  self.selectedID == currentID else { return }
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
            else { scheduleWarmVideo() }
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
        .fullScreenCover(isPresented: $fullscreen) {
            if let session = feed.session {
                AIDramaShortsFullscreen(session: session, close: { fullscreen = false })
            }
        }
        .task(id: active) {
            feed.setActive(active, sceneActive: scenePhase == .active)
            if active, feed.videos.isEmpty { await feed.loadMore() }
        }
        .onChange(of: scenePhase) { feed.setSceneActive($0 == .active) }
        .onChange(of: active) { if !$0 { fullscreen = false } }
        .onDisappear {
            // A full-screen cover hides this view without leaving the feed.
            if !fullscreen { feed.setActive(false, sceneActive: false) }
        }
    }

    private func playAll(_ item: AIDramaShortVideo) {
        openAll(item.series, item.episode.id) {
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
    var body: some View {
        VStack {
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
                HStack(spacing: 16) {
                    Button { session.togglePause() } label: {
                        Image(systemName: session.manuallyPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(session.manuallyPaused ? "Phát" : "Tạm dừng")
                    Button(action: openAll) {
                        Label("Phát tất cả" + (item.series.episodeCount.map { " · \($0) tập" } ?? ""), systemImage: "list.bullet.rectangle")
                            .font(.subheadline.bold()).padding(12).background(.white.opacity(0.16), in: Capsule())
                    }.accessibilityIdentifier("aidrama.shorts.all")
                    #if DEBUG
                    .accessibilityValue(AIDramaDebugSupport.enabled ? "\(item.series.id)|\(item.episode.id)|\(item.episode.number)|\(item.series.episodeCount ?? 0)" : "")
                    #endif
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
                    AIDramaShortsSurface(session: session)
                    AIDramaShortsControls(session: session, item: item, fullscreen: showFullscreen) { openAll(item) }
                }
                #if DEBUG
                if AIDramaDebugSupport.enabled, !fullscreen {
                    AIDramaDebugStateView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                #endif
            } else if feed.warmID == item.id, let prepared = feed.warmSession {
                AIDramaShortsSurface(session: prepared)
            } else {
                AsyncImage(url: item.series.coverURL) { image in image.resizable().scaledToFit() } placeholder: { Color.black }
                    .allowsHitTesting(false)
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

@MainActor
private struct AIDramaShortsFullscreen: View {
    @ObservedObject var session: AIDramaPlaybackSession
    let close: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AIDramaShortsSurface(session: session).ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: close) { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 48, height: 48).contentShape(Rectangle()) }
                        .accessibilityLabel("Thoát toàn màn hình").accessibilityIdentifier("aidrama.shorts.fullscreen")
                    Spacer()
                    Button { session.togglePause() } label: {
                        Image(systemName: session.manuallyPaused ? "play.fill" : "pause.fill").frame(width: 48, height: 48).contentShape(Rectangle())
                    }.accessibilityLabel(session.manuallyPaused ? "Phát" : "Tạm dừng")
                }.padding(.horizontal, 16).background(.black.opacity(0.25))
                Spacer()
            }
            #if DEBUG
            if AIDramaDebugSupport.enabled {
                AIDramaDebugStateView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            #endif
        }
        .foregroundColor(.white).buttonStyle(.plain).statusBarHidden(true)
        .background(LandscapePresentation().frame(width: 0, height: 0))
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
