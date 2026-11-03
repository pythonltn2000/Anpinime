import SwiftUI
import UIKit

/// Recommendations use PineDrama's native feed, with one player for the committed page.
@MainActor
final class AIDramaShortsStore: ObservableObject {
    @Published private(set) var videos: [AIDramaShortVideo] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var session: AIDramaPlaybackSession?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    private let provider: AIDramaProviding
    private var request: Task<AIDramaShortFeedPage, Error>?
    private var generation = UUID()
    private var active = false
    private var sceneActive = false
    var selected: AIDramaShortVideo? { videos.first { $0.id == selectedID } }

    init(provider: AIDramaProviding) { self.provider = provider }

    func setActive(_ value: Bool, sceneActive: Bool) {
        active = value; self.sceneActive = sceneActive
        session?.setPresented(value, sceneActive: sceneActive)
        if !value { request?.cancel(); request = nil; generation = UUID(); loading = false }
    }

    func setSceneActive(_ value: Bool) { sceneActive = value; session?.setSceneActive(value) }

    func select(_ id: String) {
        guard let video = videos.first(where: { $0.id == id }) else { return }
        if selectedID != id || session == nil {
            session?.setPresented(false, sceneActive: false)
            selectedID = id
            // This is a single recommendation, not a claim that the series has one episode.
            let playlist = AIDramaPlaylist(series: video.series, episodes: [video.episode], reportedTotal: nil)
            session = AIDramaPlaybackSession(playlist: playlist, provider: provider, initialEpisodeID: video.episode.id)
        }
        session?.setPresented(active, sceneActive: sceneActive)
        if let index = videos.firstIndex(where: { $0.id == id }), index >= videos.count - 2, error == nil {
            Task { await loadMore() }
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
        } catch {
            guard generation == token, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }

    deinit { request?.cancel() }
}

@MainActor
struct AIDramaShortsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var feed: AIDramaShortsStore
    @State private var landscape = false
    let active: Bool
    let openAll: (AIDramaSeries, String, @escaping () -> Void) -> Void
    let fullscreenChanged: (Bool) -> Void

    init(provider: AIDramaProviding, active: Bool, openAll: @escaping (AIDramaSeries, String, @escaping () -> Void) -> Void, fullscreenChanged: @escaping (Bool) -> Void) {
        _feed = StateObject(wrappedValue: AIDramaShortsStore(provider: provider))
        self.active = active; self.openAll = openAll; self.fullscreenChanged = fullscreenChanged
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !feed.videos.isEmpty {
                AIDramaShortsPager(feed: feed, pagingEnabled: !landscape).ignoresSafeArea()
            }
            if let session = feed.session, let item = feed.selected {
                AIDramaShortsControls(session: session, item: item, landscape: $landscape) {
                    openAll(item.series, item.episode.id) {
                        // Stop preview ownership before the full playlist creates its player.
                        feed.setActive(false, sceneActive: false)
                    }
                }
                #if DEBUG
                if AIDramaDebugSupport.enabled {
                    AIDramaDebugStateView(session: session).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                #endif
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
        .background(VideoOrientationPresentation(landscape: landscape).frame(width: 0, height: 0))
        .task(id: active) {
            feed.setActive(active, sceneActive: scenePhase == .active)
            if active, feed.videos.isEmpty { await feed.loadMore() }
        }
        .onChange(of: scenePhase) { feed.setSceneActive($0 == .active) }
        .onChange(of: landscape) { fullscreenChanged($0) }
        .onChange(of: active) { value in if !value { landscape = false } }
        .onDisappear { feed.setActive(false, sceneActive: false); landscape = false }
        .accessibilityIdentifier("aidrama.shorts")
    }
}

@MainActor
private struct AIDramaShortsControls: View {
    @ObservedObject var session: AIDramaPlaybackSession
    let item: AIDramaShortVideo
    @Binding var landscape: Bool
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
                        Image(systemName: session.manuallyPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(session.manuallyPaused ? "Phát" : "Tạm dừng")
                    Button(action: openAll) {
                        Label("Phát tất cả" + (item.series.episodeCount.map { " · \($0) tập" } ?? ""), systemImage: "list.bullet.rectangle")
                            .font(.subheadline.bold()).padding(12).background(.white.opacity(0.16), in: Capsule())
                    }.accessibilityIdentifier("aidrama.shorts.all")
                    Spacer(minLength: 0)
                    Button { landscape.toggle() } label: {
                        Image(systemName: landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(landscape ? "Thoát toàn màn hình" : "Xem toàn màn hình")
                        .accessibilityIdentifier("aidrama.shorts.fullscreen")
                }
            }
            .padding(20).padding(.top, 30)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct AIDramaShortsPage: View {
    let item: AIDramaShortVideo
    @ObservedObject var feed: AIDramaShortsStore
    var body: some View {
        ZStack {
            Color.black
            if feed.selectedID == item.id, let session = feed.session {
                AIDramaShortsSurface(session: session)
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
        }
    }
}

@MainActor
private struct AIDramaShortsPager: UIViewControllerRepresentable {
    @ObservedObject var feed: AIDramaShortsStore
    let pagingEnabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(feed: feed) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
        pager.view.backgroundColor = .black
        pager.dataSource = context.coordinator; pager.delegate = context.coordinator
        context.coordinator.showSelection(in: pager)
        return pager
    }
    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        pager.dataSource = pagingEnabled ? context.coordinator : nil
        for scroll in pager.view.subviews.compactMap({ $0 as? UIScrollView }) { scroll.isScrollEnabled = pagingEnabled }
        if !context.coordinator.transitioning { context.coordinator.showSelection(in: pager) }
    }
    static func dismantleUIViewController(_ pager: UIPageViewController, coordinator: Coordinator) {
        pager.delegate = nil; pager.dataSource = nil
    }
    final class Page: UIHostingController<AIDramaShortsPage> {
        let videoID: String
        init(item: AIDramaShortVideo, feed: AIDramaShortsStore) {
            videoID = item.id; super.init(rootView: AIDramaShortsPage(item: item, feed: feed)); view.backgroundColor = .black
        }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:)") }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let feed: AIDramaShortsStore
        var transitioning = false
        init(feed: AIDramaShortsStore) { self.feed = feed }
        func showSelection(in pager: UIPageViewController) {
            guard let item = feed.selected, (pager.viewControllers?.first as? Page)?.videoID != item.id else { return }
            pager.setViewControllers([Page(item: item, feed: feed)], direction: .forward, animated: false)
        }
        func neighbor(_ page: UIViewController, offset: Int) -> UIViewController? {
            guard let page = page as? Page, let index = feed.videos.firstIndex(where: { $0.id == page.videoID }),
                  feed.videos.indices.contains(index + offset) else { return nil }
            return Page(item: feed.videos[index + offset], feed: feed)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? { neighbor(viewController, offset: -1) }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? { neighbor(viewController, offset: 1) }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            transitioning = true; feed.session?.beginPageTransition()
        }
        func pageViewController(_ pager: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            transitioning = false
            if completed, let page = pager.viewControllers?.first as? Page { feed.select(page.videoID) }
            else { feed.session?.finishPageTransition(episodeID: nil, completed: false) }
        }
    }
}
