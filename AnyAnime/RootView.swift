import SwiftUI

struct RootView: View {
    @EnvironmentObject private var service: AnimeService

    var body: some View {
        TabView {
            NavigationView { HomeView() }
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }

            NavigationView { AnimeSearchView() }
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }

            NavigationView { BrowseView() }
                .tabItem { Label("Thể loại", systemImage: "square.grid.2x2.fill") }

            NavigationView { AboutView() }
                .tabItem { Label("Giới thiệu", systemImage: "info.circle.fill") }
        }
        .tint(.red)
        .sheet(isPresented: $service.needsVerification) {
            VerificationView(url: service.verificationURL) { finalURL in
                Task {
                    await service.verificationCompleted(at: finalURL)
                    await service.loadHome(forceDomainRefresh: false)
                }
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var service: AnimeService

    var body: some View {
        Group {
            if service.homeSections.isEmpty && service.homeLoading {
                LoadingView(text: "Đang tải danh sách anime…")
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
                        ForEach(service.homeSections) { section in
                            AnimeRow(section: section)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable { await service.loadHome(forceDomainRefresh: true) }
            }
        }
        .navigationTitle("AnyAnime")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await service.loadHome(forceDomainRefresh: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(service.homeLoading)
            }
        }
        .task {
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
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
            service.register(error)
        }
    }
}

struct AnimeSearchView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var loading = false
    @State private var message = "Nhập từ khóa để tìm anime"

    var body: some View {
        Group {
            if loading { LoadingView(text: "Đang tìm kiếm…") }
            else if results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Tìm anime", message: message, actionTitle: nil, action: nil)
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
        .searchable(text: $query, prompt: "Tên anime")
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

struct AboutView: View {
    @EnvironmentObject private var service: AnimeService

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.red)
                Text("AnyAnime").font(.largeTitle.bold())
                Text("Phiên bản viết lại native cho iOS 15+")
                    .foregroundColor(.secondary)
                Divider()
                Text("Ứng dụng đọc dữ liệu công khai từ AnimeVietsub. Tên miền được xác định lại từ shortlink mỗi khi cần, nên không bị khóa vào một domain cố định.")
                    .multilineTextAlignment(.center)
                DomainStatusView()
                Link("Mở shortlink nguồn", destination: URL(string: "https://bit.ly/animevietsubtv")!)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Text("Nội dung và máy chủ phát thuộc website nguồn. Ứng dụng không tự động vượt CAPTCHA; khi website yêu cầu, bạn cần xác minh trong cửa sổ trình duyệt tích hợp.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .navigationTitle("Giới thiệu")
    }
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
                Text(service.baseURL.host ?? service.baseURL.absoluteString)
                    .font(.caption2).foregroundColor(.secondary)
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
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: placeholder
            case .empty: ZStack { placeholder; ProgressView() }
            @unknown default: placeholder
            }
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
    let text: String
    var body: some View {
        VStack(spacing: 12) { ProgressView(); Text(text).foregroundColor(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

