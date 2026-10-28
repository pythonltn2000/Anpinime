import SwiftUI

struct RootView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var enteredLibrary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introVisible = true
    @State private var transition: (from: String, to: String)?
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        Group {
            if enteredLibrary {
                library
            } else {
                LibraryChoiceView { source in
                    chooseLibrary(source)
                }
            }
        }
        .tint(.anpinimeAccent)
        .background(VerificationGate(browser: service.website))
        .overlay {
            if introVisible { IntroVideoView { withAnimation(.easeOut(duration: 0.22)) { introVisible = false } }.ignoresSafeArea().transition(.opacity) }
            else if let transition { LibraryTransition(from: transition.from, to: transition.to, intro: false).transition(.opacity) }
        }
        .onDisappear { transitionTask?.cancel() }
    }

    private func chooseLibrary(_ source: ContentSource) {
        guard transition == nil else { return }
        let old = service.source.isMovie ? "MovieLogo" : "AppLogo"
        let new = source.isMovie ? "MovieLogo" : "AppLogo"
        if old == new { service.selectSource(source); enteredLibrary = true; return }
        transition = (old, new)
        transitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 400_000_000)
            guard !Task.isCancelled else { return }
            service.selectSource(source); enteredLibrary = true
            try? await Task.sleep(nanoseconds: reduceMotion ? 200_000_000 : 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { transition = nil }
        }
    }

    private var library: some View {
        TabView {
            NavigationView { HomeView(onChooseLibrary: { enteredLibrary = false }) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }

            NavigationView { AnimeSearchView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }

            NavigationView { BrowseView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Thể loại", systemImage: "square.grid.2x2.fill") }

            if !service.source.isMovie {
                NavigationView { AnimeScheduleView() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Lịch chiếu", systemImage: "calendar") }
            }

            NavigationView { AppSettingsView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
        }
        .id(service.source)
        .tint(.anpinimeAccent)
    }
}

struct LibraryChoiceView: View {
    let select: (ContentSource) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.04, blue: 0.21), .black, Color(red: 0.03, green: 0.09, blue: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 26) {
                        Image("AppLogo").resizable().scaledToFit().frame(width: 120, height: 120)
                        VStack(spacing: 9) {
                            Text("AnPinime").font(.system(size: 36, weight: .heavy, design: .rounded))
                            Text("Hôm nay bạn muốn xem gì?").font(.title3).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 16) {
                            choice("Anime", subtitle: "Khám phá thế giới hoạt hình", icon: "sparkles.tv", color: .anpinimeAccent, source: .anime)
                            choice("Phim", subtitle: "Phim lẻ, phim bộ • Chọn nguồn riêng", icon: "film.stack", color: .cyan, source: .film4k)
                        }.frame(maxWidth: 480)
                        Text("Một nơi dành cho những bộ phim bạn yêu thích.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
    }

    private func choice(_ title: String, subtitle: String, icon: String, color: Color, source: ContentSource) -> some View {
        Button { select(source) } label: {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundStyle(color)
                    .frame(width: 56, height: 60)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.title2.bold()).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.padding(20).cinemaGlass(cornerRadius: 28, interactive: true)
        }.buttonStyle(.plain)
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
                            Text(service.status).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        ForEach(service.homeSections) { section in
                            AnimeRow(section: section)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable { await service.loadHome(forceDomainRefresh: true) }
            }
        }
        .navigationTitle(service.source.isMovie ? "Phim" : "Anime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 10) {
                    Button { onChooseLibrary?() } label: {
                        Image(service.source.isMovie ? "MovieLogo" : "AppLogo").resizable().scaledToFit().frame(width: 34, height: 34)
                    }.accessibilityLabel("Chọn Anime hoặc Phim")
                    if service.source.isMovie {
                        Menu {
                            ForEach([ContentSource.film4k, .phim4k, .kkphim]) { source in
                                Button { service.selectSource(source) } label: {
                                    Label(source.title, systemImage: source == service.source ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        } label: {
                            HStack(spacing: 5) { Text(service.source.title).font(.caption.weight(.semibold)); Image(systemName: "chevron.down").font(.caption2) }
                                .padding(.horizontal, 10).padding(.vertical, 8).cinemaGlass(cornerRadius: 16, interactive: true)
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await service.loadHome(forceDomainRefresh: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(service.homeLoading)
            }
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
                        FeaturedHeroCard(anime: anime)
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
    let anime: Anime

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
            RemoteImage(url: anime.imageURL ?? anime.bannerURL)
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
                    Text(subtitleText)
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

                    Text(qualityBadgeText)
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
    }
}

struct AnimeRow: View {
    let section: AnimeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.title)
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
                        Section(header: Text(group.isEmpty ? service.source.title : group)) {
                            ForEach(service.categories.filter { $0.group == group }) { category in
                                NavigationLink(destination: AnimeGridView(title: category.title, path: category.path)) {
                                    Label(category.title, systemImage: icon(for: category.path))
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
            if loading { LoadingView(text: "Đang tải \(title)…") }
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
                    if !errorMessage.isEmpty { Text(errorMessage).font(.footnote).foregroundStyle(.secondary).padding() }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(title)
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

struct AnimeSearchView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var loading = false
    @State private var message = "Nhập tên phim để tìm trong nguồn đang chọn"
    @State private var searchID = UUID()
    @State private var history: [String] = []
    private let historyStore = SearchHistory()

    var body: some View {
        ZStack {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !history.isEmpty {
                List {
                    Section(header: Text("Tìm kiếm gần đây · " + service.source.title)) {
                        ForEach(history, id: \.self) { value in
                            Button { query = value; remember(value) } label: {
                                Label(value, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { historyStore.remove(history[index], source: service.source) }
                            history = historyStore.queries(for: service.source)
                        }
                        Button("Xóa lịch sử", role: .destructive) {
                            historyStore.clear(source: service.source)
                            history = []
                        }
                    }
                }
            } else if loading { LoadingView(text: "Đang tìm kiếm…") }
            else if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Tìm \(service.contentName)", message: message, actionTitle: nil, action: nil)
            } else {
                List(results) { anime in
                    NavigationLink(destination: AnimeDetailView(anime: anime)) {
                        SearchResultRow(anime: anime)
                    }
                    .simultaneousGesture(TapGesture().onEnded { remember(query) })
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, prompt: service.source.title)
        .onSubmit(of: .search) { remember(query) }
        .task(id: query) {
            searchID = UUID()
            history = historyStore.queries(for: service.source)
            results = []
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                loading = false
                message = "Nhập tên phim để tìm trong nguồn đang chọn"
                return
            }
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            await search()
        }
        .onChange(of: service.verificationGeneration) { _ in
            if !query.isEmpty { Task { await search() } }
        }
    }

    private func remember(_ query: String) {
        historyStore.record(query, source: service.source)
        history = historyStore.queries(for: service.source)
    }

    private func search() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let selected = service.source
        let id = UUID()
        searchID = id
        loading = true
        defer { if searchID == id { loading = false } }
        do {
            let found = try await service.search(clean, source: selected)
            try Task.checkCancellation()
            guard selected == service.source, searchID == id, query.trimmingCharacters(in: .whitespacesAndNewlines) == clean else { return }
            results = found
            message = results.isEmpty ? "Không tìm thấy kết quả cho \"\(clean)\"" : ""
        } catch {
            guard !Task.isCancelled, selected == service.source, searchID == id else { return }
            results = []
            message = error.localizedDescription
            service.register(error)
        }
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var service: AnimeService
    @AppStorage("AnPinime.autoNext") private var autoNext = true
    @AppStorage("AnPinime.rememberSpeed") private var rememberSpeed = true
    @AppStorage("AnPinime.skipSeconds") private var skipSeconds = 10
    @State private var phim4kURL = UserDefaults.standard.string(forKey: "AnPinime.phim4kURL") ?? ""
    @State private var phim4kFormat = Phim4KFormat(rawValue: UserDefaults.standard.string(forKey: "AnPinime.phim4kFormat") ?? "") ?? .free1
    @State private var sourceMessage = ""

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("AppLogo").resizable().scaledToFit().frame(width: 120, height: 120)
                    Text("AnPinime").font(.largeTitle.bold())
                    Text("Anime và điện ảnh. Một nơi dành cho bạn.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            Section("Trải nghiệm xem") {
                Toggle("Tự phát tập tiếp theo", isOn: $autoNext)
                Toggle("Ghi nhớ tốc độ phát", isOn: $rememberSpeed)
                Picker("Tua nhanh / tua lại", selection: $skipSeconds) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) giây").tag($0) }
                }
            }
            Section("Kết nối") {
                LabeledContentCompat(title: "Nguồn đang chọn", value: service.source.subtitle)
                if !service.source.isMovie { LabeledContentCompat(title: "Máy chủ", value: service.baseURL.host ?? "Đang kết nối") }
                Button("Làm mới danh sách và kết nối") { Task { await service.loadHome(forceDomainRefresh: true) } }
                    .disabled(service.homeLoading)
            }
            if service.source.isMovie {
                Section {
                    TextField("https://…", text: $phim4kURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                    Picker("Định dạng", selection: $phim4kFormat) {
                        ForEach(Phim4KFormat.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Lưu địa chỉ nguồn 2") {
                        let value = phim4kURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            guard let url = URL(string: value), url.scheme == "https", url.host != nil,
                                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                                sourceMessage = "Hãy nhập URL HTTPS hợp lệ, không chứa mật khẩu hoặc tham số."
                                return
                            }
                        }
                        UserDefaults.standard.set(value, forKey: "AnPinime.phim4kURL")
                        UserDefaults.standard.set(phim4kFormat.rawValue, forKey: "AnPinime.phim4kFormat")
                        sourceMessage = value.isEmpty ? "Đã dùng lại máy chủ mặc định." : "Đã lưu địa chỉ."
                        if service.source == .phim4k { Task { await service.loadHome(forceDomainRefresh: true) } }
                    }.disabled(service.homeLoading)
                    if !sourceMessage.isEmpty { Text(sourceMessage).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Nguồn phim 2") }
                  footer: { Text("Để trống để dùng đầy đủ kho Phim4K, Free1 và Free2. Địa chỉ thủ công chỉ dùng một kho Free1/Free2 tương thích.") }
            }
            Section("Giới thiệu") {
                LabeledContentCompat(title: "Ứng dụng", value: "AnPinime")
                LabeledContentCompat(title: "Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0")
                LabeledContentCompat(title: "Tác giả", value: "KingLTN")
                Text("Khám phá anime và phim, chọn nguồn yêu thích và tận hưởng từng khung hình.")
                    .font(.footnote).foregroundColor(.secondary)
                Link(destination: URL(string: "https://t.me/kingltnn")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color(red: 0.13, green: 0.67, blue: 0.91), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Telegram").font(.headline)
                            Text("@kingltnn").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .cinemaGlass(cornerRadius: 20, interactive: true)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Cài đặt")
    }
}

private struct LabeledContentCompat: View {
    let title: String
    let value: String
    var body: some View { HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) } }
}

private struct SearchResultRow: View {
    let anime: Anime

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: anime.imageURL)
                .frame(width: 64, height: 88)
                .clipped()
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 7) {
                Text(anime.title).font(.headline).lineLimit(2)
                Text(anime.catalogLabel.isEmpty ? anime.source.title : anime.catalogLabel)
                    .font(.caption2).foregroundStyle(.secondary)
                Text([anime.episodeText, anime.quality].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !anime.score.isEmpty {
                    Label(anime.score, systemImage: "star.fill").font(.caption).foregroundColor(.yellow)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RemoteImage: View {
    @EnvironmentObject private var service: AnimeService
    @StateObject private var loader = ArtworkLoader()
    let url: URL?

    var body: some View {
        Color.clear
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack { placeholder; if loader.loading { ProgressView() } }
                }
            }
            .clipped()
            .task(id: "\(url?.absoluteString ?? "")|\(service.baseURL)|\(service.imageGeneration)") {
                await loader.load(url, baseURL: service.baseURL, revision: service.imageGeneration)
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
        Text(text)
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
            Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
