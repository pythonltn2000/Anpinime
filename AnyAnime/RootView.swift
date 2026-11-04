import SwiftUI

/// Library selection is independent of the existing anime/movie provider IDs.
enum AppLibrary: String, CaseIterable, Identifiable {
    case anime, movie, aiDrama
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: return "Anime"
        case .movie: return "Phim"
        case .aiDrama: return "Phim AI"
        }
    }
    var logoName: String { self == .movie ? "MovieLogo" : "AppLogo" }
}

#if DEBUG
@MainActor
private enum AIDramaLibraryLaunchSupport {
    static var prepared = false
}
#endif

@MainActor
struct RootView: View {
    @EnvironmentObject private var service: AnimeService
    @StateObject private var aiDramaStore = AIDramaCatalogStore()
    @AppStorage("AnPinime.selectedLibrary") private var selectedLibraryRaw = AppLibrary.anime.rawValue
    @AppStorage("AnPinime.movieSource") private var selectedMovieSourceRaw = ContentSource.film4k.rawValue
    @State private var enteredLibrary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introVisible = true
    @State private var transition: (from: String, to: String)?
    @State private var transitionTask: Task<Void, Never>?
    @State private var selectedLibraryTab = 0

    init() {
        #if DEBUG
        if AIDramaDebugSupport.fixtureEnabled {
            AIDramaDebugSupport.clearFixtureProgress()
            let configuration = PineDramaProvider.Configuration(
                baseURL: URL(string: "http://127.0.0.1:8768")!, commonParameters: [:], allowLoopbackHTTP: true)
            _aiDramaStore = StateObject(wrappedValue: AIDramaCatalogStore(provider: PineDramaProvider(configuration: configuration)))
        }
        if AIDramaDebugSupport.enabled {
            if !AIDramaDebugSupport.fixtureEnabled {
                AIDramaDebugSupport.clearProgress(seriesID: "7676620083434656784")
            }
            if !AIDramaLibraryLaunchSupport.prepared {
                AIDramaLibraryLaunchSupport.prepared = true
                UserDefaults.standard.set(AppLibrary.aiDrama.rawValue, forKey: "AnPinime.selectedLibrary")
            }
            _enteredLibrary = State(initialValue: true)
            _introVisible = State(initialValue: false)
        }
        #endif
    }

    private var selectedLibrary: AppLibrary { AppLibrary(rawValue: selectedLibraryRaw) ?? .anime }
    private var selectedMovieSource: ContentSource {
        guard let source = ContentSource(rawValue: selectedMovieSourceRaw), source.isMovie else { return .film4k }
        return source
    }

    var body: some View {
        Group {
            if enteredLibrary {
                if selectedLibrary == .aiDrama {
                    AIDramaLibraryView(store: aiDramaStore, onChooseLibrary: { enteredLibrary = false })
                } else if (selectedLibrary == .anime && !service.source.isMovie)
                    || (selectedLibrary == .movie && service.source.isMovie) {
                    library
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                LibraryChoiceView { library in chooseLibrary(library) }
            }
        }
        .tint(.anpinimeAccent)
        .background {
            if enteredLibrary && selectedLibrary == .anime {
                VerificationGate(browser: service.website)
            }
        }
        .overlay {
            if introVisible { IntroVideoView { withAnimation(.easeOut(duration: 0.22)) { introVisible = false } }.ignoresSafeArea().transition(.opacity) }
            else if let transition { LibraryTransition(from: transition.from, to: transition.to, intro: false).transition(.opacity) }
        }
        .task {
            if enteredLibrary { activateSource(for: selectedLibrary) }
        }
        .onChange(of: service.source) { source in
            if source.isMovie { selectedMovieSourceRaw = source.rawValue }
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
            // A cancelled sleep returns before the task's normal cleanup. Never
            // leave its animated, touch-blocking overlay mounted on reappearance.
            transition = nil
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if AIDramaDebugSupport.enabled { AIDramaDebugOwnerView() }
        }
        #endif
    }

    private func activateSource(for library: AppLibrary) {
        switch library {
        case .anime: service.selectSource(.anime)
        case .movie: service.selectSource(selectedMovieSource)
        case .aiDrama: break
        }
    }

    private func chooseLibrary(_ library: AppLibrary) {
        guard transition == nil else { return }
        let old = selectedLibrary.logoName
        let new = library.logoName
        selectedLibraryTab = 0
        if old == new {
            selectedLibraryRaw = library.rawValue
            activateSource(for: library)
            enteredLibrary = true
            return
        }
        transition = (old, new)
        transitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 400_000_000)
            guard !Task.isCancelled else { return }
            selectedLibraryRaw = library.rawValue
            activateSource(for: library)
            enteredLibrary = true
            try? await Task.sleep(nanoseconds: reduceMotion ? 200_000_000 : 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { transition = nil }
        }
    }

    private var library: some View {
        TabView(selection: $selectedLibraryTab) {
            NavigationView { HomeView(onChooseLibrary: { enteredLibrary = false }) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }
                .tag(0)

            NavigationView { AnimeSearchView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }
                .tag(1)

            NavigationView { BrowseView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Thể loại", systemImage: "square.grid.2x2.fill") }
                .tag(2)

            if !service.source.isMovie {
                NavigationView { AnimeScheduleView() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Lịch chiếu", systemImage: "calendar") }
                    .tag(3)
            }

            NavigationView { AppSettingsView(onChooseLibrary: { enteredLibrary = false }) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .id(service.source)
        .tint(.anpinimeAccent)
    }
}

struct LibraryChoiceView: View {
    let select: (AppLibrary) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.04, blue: 0.21), .black, Color(red: 0.03, green: 0.09, blue: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Image("AppLogo").resizable().scaledToFit().frame(width: 100, height: 100)
                        VStack(spacing: 9) {
                            Text("AnPinime").font(.system(size: 36, weight: .heavy, design: .rounded))
                            Text("Hôm nay bạn muốn xem gì?").font(.title3).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 14) {
                            choice(.anime, subtitle: "Khám phá thế giới hoạt hình", icon: "sparkles.tv", color: .anpinimeAccent)
                            choice(.movie, subtitle: "Phim lẻ, phim bộ • Chọn nguồn riêng", icon: "film.stack", color: .cyan)
                            choice(.aiDrama, subtitle: "Khám phá những câu chuyện AI", icon: "sparkles", color: .purple)
                        }.frame(maxWidth: 480)
                        Text("Một nơi dành cho những bộ phim bạn yêu thích.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
    }

    private func choice(_ library: AppLibrary, subtitle: String, icon: String, color: Color) -> some View {
        Button { select(library) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 28, weight: .medium)).foregroundStyle(color)
                    .frame(width: 48, height: 56)
                VStack(alignment: .leading, spacing: 7) {
                    Text(library.title).font(.title2.bold()).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .cinemaGlass(cornerRadius: 26, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.choice." + library.rawValue)
    }
}

struct HomeView: View {
    @EnvironmentObject private var service: AnimeService
    var onChooseLibrary: (() -> Void)? = nil

    private var featuredItems: [Anime] {
        guard let first = service.homeSections.first else { return [] }
        return Array(first.items.prefix(8))
    }

    var body: some View {
        ZStack {
            if service.homeSections.isEmpty && service.homeLoading {
                LoadingView(text: "Đang tải danh sách \(service.contentName)…")
            } else if service.homeSections.isEmpty {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "Chưa tải được dữ liệu",
                    message: service.status,
                    actionTitle: "Thử lại"
                ) { Task { await service.loadHome(forceDomainRefresh: true) } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if !featuredItems.isEmpty {
                            FeaturedCarouselView(items: featuredItems)
                        }
                        if service.source.isMovie {
                            NavigationLink(destination: AnimeGridView(title: "Tất cả phim", path: "")) {
                                HStack {
                                    Label("Khám phá kho phim & thể loại", systemImage: "square.grid.2x2")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .cinemaGlass(cornerRadius: 18)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                        if !service.status.isEmpty && !service.homeLoading {
                            Text(ContentDisplayText.sourceLabels(service.status)).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        ForEach(service.homeSections) { section in
                            AnimeRow(section: section)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable { await service.loadHome(forceDomainRefresh: true) }
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            HStack {
                HStack(spacing: 10) {
                    Button { onChooseLibrary?() } label: {
                        Image(service.source.isMovie ? "MovieLogo" : "AppLogo").resizable().scaledToFit().frame(width: 34, height: 34)
                    }.accessibilityLabel("Đổi thư viện")
                    if service.source.isMovie {
                        Menu {
                            ForEach([ContentSource.film4k, .phim4k, .kkphim]) { source in
                                Button { service.selectSource(source) } label: {
                                    Label(source.title, systemImage: source == service.source ? "checkmark.circle.fill" : "circle")
                                }
                                .accessibilityIdentifier("movie.source." + source.rawValue)
                            }
                        } label: {
                            HStack(spacing: 5) { Text(service.source.title).font(.caption.weight(.semibold)); Image(systemName: "chevron.down").font(.caption2) }
                                .padding(.horizontal, 10).padding(.vertical, 8).cinemaGlass(cornerRadius: 16, interactive: true)
                        }
                        .accessibilityIdentifier("movie.source.choose")
                        .accessibilityLabel("Nguồn phim")
                        .accessibilityValue(service.source.title)
                    }
                }
                Spacer()
                if !service.source.isMovie {
                    NavigationLink(destination: AnimeScheduleView()) { Image(systemName: "calendar").frame(width: 42, height: 42) }
                        .accessibilityLabel("Lịch chiếu anime")
                }
            }
            .padding(.horizontal, 16).padding(.top, 6)
        }
        .task(id: service.source) {
            if service.homeSections.isEmpty { await service.loadHome() }
        }
    }
}

struct FeaturedCarouselView: View {
    let items: [Anime]
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, anime in
                    NavigationLink(destination: AnimeDetailView(anime: anime)) {
                        FeaturedHeroCard(anime: anime, visible: selection == index).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 465)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Circle()
                            .fill(index == selection ? Color.white : Color.white.opacity(0.32))
                            .frame(width: index == selection ? 7 : 6, height: index == selection ? 7 : 6)
                            .animation(.easeInOut(duration: 0.2), value: selection)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .task(id: items.map(\.id).joined()) {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    selection = (selection + 1) % items.count
                }
            }
        }
    }
}

struct FeaturedHeroCard: View {
    @EnvironmentObject private var service: AnimeService
    @State private var detailedArtwork: URL?
    @State private var metadataRevision = -1
    let anime: Anime
    var visible = true

    private var yearTag: String {
        if let match = anime.info.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            return String(anime.info[match])
        }
        return anime.source.isMovie ? "2026" : "Mới"
    }

    private var subtitleText: String {
        let candidate = anime.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty && candidate.lowercased() != anime.title.lowercased() {
            return candidate
        }
        return anime.info
    }

    private var qualityBadgeText: String {
        let qual = anime.quality.trimmingCharacters(in: .whitespacesAndNewlines)
        let ep = anime.episodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQual: String = {
            let up = qual.uppercased()
            if up == "FHD" || up == "1080P" || up == "FULLHD" { return "Full HD" }
            return qual
        }()
        if !normalizedQual.isEmpty && !ep.isEmpty {
            if ep == "Phim lẻ" {
                return "\(normalizedQual) (PĐ)"
            }
            return "\(normalizedQual) • \(ep)"
        }
        if !normalizedQual.isEmpty {
            return "\(normalizedQual) (PĐ)"
        }
        if !ep.isEmpty {
            return ep
        }
        return "Full HD (PĐ)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: detailedArtwork ?? anime.bannerURL ?? anime.imageURL, keepSharperImage: true)
                .frame(maxWidth: .infinity)
                .frame(height: 465)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0.0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.62), location: 0.68),
                    .init(color: .black.opacity(0.92), location: 0.86),
                    .init(color: .black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                Text(anime.title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.85), radius: 10, y: 3)
                    .padding(.horizontal, 20)

                if !subtitleText.isEmpty {
                    Text(ContentDisplayText.sourceLabels(subtitleText))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.horizontal, 28)
                }

                HStack(spacing: 8) {
                    Text(yearTag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))

                    if !anime.score.isEmpty {
                        Text("IMDb \(anime.score)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: Capsule())
                    }

                    Text(ContentDisplayText.sourceLabels(qualityBadgeText))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.08, green: 0.52, blue: 0.96), in: Capsule())
                }
                .padding(.top, 2)

                Text("Xem chi tiết")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.white, in: Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                    .padding(.top, 4)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 465)
        .clipped()
        .task(id: "\(visible)|\(service.imageGeneration)") {
            guard visible, anime.source == .anime, metadataRevision != service.imageGeneration else { return }
            let revision = service.imageGeneration
            // Only the visible banner requests metadata; list posters and episode loading
            // keep their existing paths. Use only artwork actually supplied by the source.
            do {
                let metadata = try await service.detailMetadata(for: anime)
                try Task.checkCancellation()
                guard service.source == anime.source, service.imageGeneration == revision else { return }
                detailedArtwork = metadata.bannerURL ?? metadata.posterURL
                metadataRevision = revision
            } catch {
                if !Task.isCancelled { metadataRevision = revision }
            }
        }
    }
}

struct AnimeRow: View {
    let section: AnimeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ContentDisplayText.sourceLabels(section.title))
                    .font(.title3.bold())
                Spacer()
                if let path = section.categoryPath, !path.isEmpty {
                    NavigationLink(destination: AnimeGridView(title: section.title, path: path)) {
                        HStack(spacing: 4) {
                            Text("Xem thêm")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.anpinimeAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { anime in
                        NavigationLink(destination: AnimeDetailView(anime: anime)) {
                            AnimeCard(anime: anime)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct AnimeCard: View {
    let anime: Anime

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: anime.imageURL)
                    .frame(width: 132, height: 190)
                    .clipped()
                    .cornerRadius(9)
                if !anime.episodeText.isEmpty || !anime.quality.isEmpty {
                    HStack(spacing: 4) {
                        if !anime.episodeText.isEmpty { Badge(text: anime.episodeText, color: .red) }
                        if !anime.quality.isEmpty { Badge(text: anime.quality, color: .blue) }
                    }
                    .padding(6)
                }
            }
            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 132, alignment: .leading)
            if !anime.score.isEmpty {
                Label(anime.score, systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .frame(width: 132, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

struct BrowseView: View {
    @EnvironmentObject private var service: AnimeService

    var body: some View {
        ZStack {
            if service.categories.isEmpty && service.homeLoading {
                LoadingView(text: "Đang tải thể loại…")
            } else {
                List {
                    ForEach(categoryGroups, id: \.self) { group in
                        Section(header: Text(ContentDisplayText.sourceLabels(group.isEmpty ? service.source.title : group))) {
                            ForEach(service.categories.filter { $0.group == group }) { category in
                                NavigationLink(destination: AnimeGridView(title: category.title, path: category.path)) {
                                    Label(ContentDisplayText.sourceLabels(category.title), systemImage: icon(for: category.path))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Thể loại")
        .task(id: service.source) {
            if service.categories.isEmpty { await service.loadHome() }
        }
    }

    private var categoryGroups: [String] {
        var seen = Set<String>()
        return service.categories.map(\.group).filter { seen.insert($0).inserted }
    }

    private func icon(for path: String) -> String {
        if path.contains("dang-chieu") || path.contains("moi-cap-nhat") { return "play.circle.fill" }
        if path.contains("tron-bo") { return "checkmark.circle.fill" }
        if path.contains("han-quoc") || path.contains("trung-quoc") || path.contains("viet-nam") || path.contains("au-my") || path.contains("nhat-ban") || path.contains("thai-lan") {
            return "globe.asia.australia.fill"
        }
        if path.contains("hoat-hinh") { return "sparkles.tv.fill" }
        if path.contains("anime-le") || path.contains("phim-le") || path.contains("type=movie") { return "film.fill" }
        if path.contains("phim-bo") || path.contains("type=tv") { return "tv.fill" }
        if path.contains("hanh-dong") || path.contains("vo-thuat") { return "flame.fill" }
        if path.contains("tinh-cam") { return "heart.fill" }
        if path.contains("kinh-di") || path.contains("bi-an") { return "moon.stars.fill" }
        return "rectangle.stack.fill"
    }
}

struct AnimeGridView: View {
    @EnvironmentObject private var service: AnimeService
    let title: String
    let path: String
    @State private var items: [Anime] = []
    @State private var loading = true
    @State private var errorMessage = ""
    @State private var page = 1
    @State private var loadingMore = false
    @State private var hasMore = true

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 14)]

    var body: some View {
        ZStack {
            if loading { LoadingView(text: "Đang tải \(ContentDisplayText.sourceLabels(title))…") }
            else if items.isEmpty {
                EmptyStateView(icon: "film", title: "Không có dữ liệu", message: errorMessage, actionTitle: "Thử lại") {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                        ForEach(items) { anime in
                            NavigationLink(destination: AnimeDetailView(anime: anime)) {
                                AnimeCard(anime: anime)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    if service.source.isMovie && hasMore {
                        Button { Task { await loadMore() } } label: {
                            if loadingMore { ProgressView() } else { Text("Tải thêm phim") }
                        }.buttonStyle(.bordered).disabled(loadingMore).padding()
                    }
                    if !errorMessage.isEmpty { Text(ContentDisplayText.sourceLabels(errorMessage)).font(.footnote).foregroundStyle(.secondary).padding() }
                }
                .refreshable { await load() }
            }
        }
        .navigationBarHidden(false)
        .navigationTitle(ContentDisplayText.sourceLabels(title))
        .task { await load() }
        .onChange(of: service.verificationGeneration) { _ in Task { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await service.list(path: path)
            page = 1; hasMore = !items.isEmpty
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            service.register(error)
        }
    }

    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await service.list(path: path, page: page + 1)
            let known = Set(items.map(\.id))
            let unique = next.filter { !known.contains($0.id) }
            hasMore = !unique.isEmpty
            items += unique; page += 1; errorMessage = ""
        } catch { errorMessage = error.localizedDescription }
    }
}

struct RemoteImage: View {
    @EnvironmentObject private var service: AnimeService
    @StateObject private var loader = ArtworkLoader()
    let url: URL?
    var keepSharperImage = false

    var body: some View {
        Color.clear
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    ZStack { placeholder; if loader.loading { ProgressView() } }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .task(id: "\(url?.absoluteString ?? "")|\(service.baseURL)|\(service.imageGeneration)") {
                await loader.load(url, baseURL: service.baseURL, revision: service.imageGeneration, keepSharperImage: keepSharperImage)
            }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.18)
            Image(systemName: "photo").foregroundColor(.secondary)
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(ContentDisplayText.sourceLabels(text))
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(color.opacity(0.92))
            .foregroundColor(.white)
            .cornerRadius(4)
            .lineLimit(1)
    }
}

struct LoadingView: View {
    @EnvironmentObject private var service: AnimeService
    let text: String
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.02, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 12) {
                AnimatedListLoader(movie: service.source.isMovie).frame(width: 210, height: 210).blendMode(.screen)
                Text(text).font(.subheadline).foregroundColor(.white.opacity(0.65))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(ContentDisplayText.sourceLabels(message)).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
