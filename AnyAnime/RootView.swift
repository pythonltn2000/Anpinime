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
            if introVisible { LibraryTransition(from: "AppLogo", to: "MovieLogo", intro: true).transition(.opacity) }
            else if let transition { LibraryTransition(from: transition.from, to: transition.to, intro: false).transition(.opacity) }
        }
        .task {
            guard introVisible else { return }
            try? await Task.sleep(nanoseconds: reduceMotion ? 350_000_000 : 1_850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) { introVisible = false }
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
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }

            NavigationView { AnimeSearchView() }
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }

            NavigationView { BrowseView() }
                .tabItem { Label("Thể loại", systemImage: "square.grid.2x2.fill") }

            NavigationView { AppSettingsView() }
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
                        Image("AppLogo").resizable().scaledToFit().frame(width: 104, height: 104).cornerRadius(28)
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

    var body: some View {
        Group {
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
                    LazyVStack(alignment: .leading, spacing: 24) {
                        DomainStatusView()
                        if service.source.isMovie {
                            NavigationLink(destination: AnimeGridView(title: "Tất cả phim", path: "")) {
                                HStack { Label("Khám phá tất cả phim", systemImage: "square.grid.2x2"); Spacer(); Image(systemName: "chevron.right") }
                                    .padding().cinemaGlass(cornerRadius: 18)
                            }.buttonStyle(.plain).padding(.horizontal)
                        }
                        ForEach(service.homeSections) { section in
                            AnimeRow(section: section)
                        }
                    }
                    .padding(.vertical, 12)
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
                        Image(service.source.isMovie ? "MovieLogo" : "AppLogo").resizable().scaledToFit().frame(width: 32, height: 32).cornerRadius(9)
                    }.accessibilityLabel("Chọn Anime hoặc Phim")
                    if service.source.isMovie {
                        Menu {
                            ForEach([ContentSource.film4k, .phim4k]) { source in
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

struct AnimeRow: View {
    let section: AnimeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.bold())
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
        List(service.categories) { category in
            NavigationLink(destination: AnimeGridView(title: category.title, path: category.path)) {
                Label(category.title, systemImage: icon(for: category.path))
            }
        }
        .navigationTitle("Thể loại")
    }

    private func icon(for path: String) -> String {
        if path.contains("dang-chieu") { return "play.circle" }
        if path.contains("tron-bo") { return "checkmark.circle" }
        if path.contains("trung-quoc") { return "sparkles.tv" }
        if path.contains("anime-le") { return "film" }
        return "rectangle.stack"
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
        Group {
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

    var body: some View {
        Group {
            if loading { LoadingView(text: "Đang tìm kiếm…") }
            else if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Tìm \(service.contentName)", message: message, actionTitle: nil, action: nil)
            } else {
                List(results) { anime in
                    NavigationLink(destination: AnimeDetailView(anime: anime)) {
                        SearchResultRow(anime: anime)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, prompt: "Tên \(service.contentName)")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: service.verificationGeneration) { _ in
            if !query.isEmpty { Task { await search() } }
        }
    }

    private func search() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            results = try await service.search(clean)
            message = results.isEmpty ? "Không tìm thấy kết quả cho \"\(clean)\"" : ""
        } catch {
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
                    Image("AppLogo").resizable().scaledToFit().frame(width: 112, height: 112).cornerRadius(26)
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
                  footer: { Text("Để trống để dùng kết nối mặc định. Khi nguồn đổi địa chỉ, bạn có thể nhập địa chỉ API mới ở đây.") }
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

struct DomainStatusView: View {
    @EnvironmentObject private var service: AnimeService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.status).font(.caption.weight(.semibold))
                if !service.source.isMovie {
                    Text(service.baseURL.host ?? service.baseURL.absoluteString)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

struct RemoteImage: View {
    @EnvironmentObject private var service: AnimeService
    @StateObject private var loader = ArtworkLoader()
    let url: URL?

    var body: some View {
        Group {
            if let image = loader.image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { placeholder; if loader.loading { ProgressView() } } }
        }
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
