import SwiftUI

enum EpisodeLoadStatus: Equatable {
    case loading
    case available
    case unavailable(String)
    case verificationRequired
    case networkError(String)
}

struct AnimeDetailView: View {
    @EnvironmentObject private var service: AnimeService
    let anime: Anime
    @State private var detail: AnimeDetail?
    @State private var loading = true
    @State private var episodeStatus: EpisodeLoadStatus = .loading
    @State private var message = ""
    @State private var selectedSeason = ""
    @State private var selectedEpisode: Episode?
    @State private var showingServerSheet = false
    @State private var pendingEpisodeNumber: Int? = nil
    @State private var loadTask: Task<Void, Never>? = nil

    private func orderedSeasons(_ episodes: [Episode]) -> [String] {
        episodes.reduce(into: [String]()) { result, ep in
            if !result.contains(ep.season) { result.append(ep.season) }
        }
    }

    var body: some View {
        ZStack {
            if loading && detail == nil {
                LoadingView(text: "Đang tải thông tin phim…")
            } else if let currentDetail = detail {
                detailContent(currentDetail)
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", title: "Không tải được chi tiết", message: message, actionTitle: "Thử lại") {
                    startLoading(forceRefresh: true)
                }
            }
        }
        .navigationBarHidden(false)
        .navigationTitle(detail?.title ?? anime.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startLoading(forceRefresh: false) }
        .onDisappear { loadTask?.cancel() }
        .refreshable { await loadAsync(forceRefresh: true) }
        .onChange(of: service.verificationGeneration) { _ in startLoading(forceRefresh: true) }
        .sheet(isPresented: $showingServerSheet) {
            if let detail {
                ServerPickerSheet(
                    title: detail.title,
                    episodes: detail.episodes,
                    selectedSeason: $selectedSeason,
                    targetEpisodeNumber: pendingEpisodeNumber
                ) { chosenEpisode in
                    showingServerSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        selectedEpisode = chosenEpisode
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedEpisode) { episode in
            PlayerView(episode: episode, title: detail?.title ?? anime.title,
                       artworkURL: detail?.bannerURL ?? detail?.posterURL ?? anime.imageURL,
                       episodes: detail?.episodes ?? [episode])
                .environmentObject(service)
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: AnimeDetail) -> some View {
        let seasons = orderedSeasons(detail.episodes)
        let activeSeason = selectedSeason.isEmpty ? (seasons.first ?? "") : selectedSeason
        let activeEpisodes = detail.episodes.filter { $0.season == activeSeason }

        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: detail.bannerURL ?? detail.posterURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 235)
                        .clipped()
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.25), location: 0),
                            .init(color: .black.opacity(0.45), location: 0.45),
                            .init(color: .black.opacity(0.96), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    HStack(alignment: .bottom, spacing: 12) {
                        RemoteImage(url: detail.posterURL)
                            .frame(width: 96, height: 138)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(detail.title)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if !detail.info.isEmpty {
                                Text(ContentDisplayText.sourceLabels(detail.info))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.82))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if seasons.count > 1 {
                                HStack(spacing: 5) {
                                    Image(systemName: "server.rack")
                                    Text("\(seasons.count) máy chủ khả dụng")
                                }
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.anpinimeAccent.opacity(0.85), in: Capsule())
                                .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 235)
                .clipped()

                // Primary Action Button Area
                playbackActionButton(activeEpisodes: activeEpisodes, detail: detail, seasons: seasons)

                if !detail.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nội dung").font(.headline)
                        Text(ContentDisplayText.sourceLabels(detail.summary))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }

                // Episodes Section
                episodesSectionView(detail: detail, seasons: seasons, activeSeason: activeSeason, activeEpisodes: activeEpisodes)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func playbackActionButton(activeEpisodes: [Episode], detail: AnimeDetail, seasons: [String]) -> some View {
        HStack(spacing: 10) {
            if let first = activeEpisodes.first ?? detail.episodes.first {
                Button {
                    if seasons.count > 1 {
                        pendingEpisodeNumber = first.number
                        showingServerSheet = true
                    } else {
                        selectedEpisode = first
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(seasons.count > 1 ? "Xem phim · Chọn Server" : "Xem phim")
                            .fontWeight(.bold)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                if seasons.count > 1 {
                    Button {
                        pendingEpisodeNumber = first.number
                        showingServerSheet = true
                    } label: {
                        Label("\(seasons.count) SV", systemImage: "server.rack")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.anpinimeAccent)
                }
            } else {
                switch episodeStatus {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Đang tải danh sách tập…")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                case .verificationRequired:
                    Button {
                        startLoading(forceRefresh: true)
                    } label: {
                        Label("Yêu cầu xác minh · Thử lại", systemImage: "shield.lefthalf.filled")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                case .networkError:
                    Button {
                        startLoading(forceRefresh: true)
                    } label: {
                        Label("Lỗi tải tập · Chạm để thử lại", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                case .unavailable(let text):
                    Text(ContentDisplayText.sourceLabels(text))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .available:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func episodesSectionView(detail: AnimeDetail, seasons: [String], activeSeason: String, activeEpisodes: [Episode]) -> some View {
        switch episodeStatus {
        case .available:
            if !detail.episodes.isEmpty {
                episodeSection(detail.episodes, seasons: seasons, active: activeSeason, visible: activeEpisodes)
            } else {
                Text("Nguồn này chưa có tập phát được.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

        case .loading:
            VStack(alignment: .leading, spacing: 10) {
                Text("Danh sách tập").font(.headline)
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.85)
                    Text("Đang đồng bộ danh sách tập từ máy chủ…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)

        case .verificationRequired:
            VStack(alignment: .leading, spacing: 8) {
                Text("Danh sách tập").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.title3)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cần xác thực bảo vệ website")
                            .font(.caption.weight(.bold))
                        Text("Vui lòng tải lại hoặc mở lại trang để hoàn tất xác minh.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Thử lại") {
                        startLoading(forceRefresh: true)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)

        case .networkError(let errText):
            VStack(alignment: .leading, spacing: 8) {
                Text("Danh sách tập").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title3)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Không thể tải danh sách tập")
                            .font(.caption.weight(.bold))
                        Text(ContentDisplayText.sourceLabels(errText))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Tải lại") {
                        startLoading(forceRefresh: true)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                .padding(12)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)

        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Text("Danh sách tập").font(.headline)
                Text(ContentDisplayText.sourceLabels(reason))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func episodeSection(_ episodes: [Episode], seasons: [String], active: String, visible: [Episode]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(seasons.count > 1 ? "Máy chủ & Danh sách tập" : "Danh sách tập (\(visible.count))")
                    .font(.headline)
                Spacer()
                if seasons.count > 1 {
                    Button {
                        pendingEpisodeNumber = visible.first?.number
                        showingServerSheet = true
                    } label: {
                        Label("Tất cả server (\(seasons.count))", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { season in
                            let badge = episodes.first(where: { $0.season == season })?.qualityBadge ?? ""
                            Button {
                                selectedSeason = season
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: season == active ? "checkmark.circle.fill" : "server.rack")
                                        .font(.caption2)
                                    Text(ContentDisplayText.sourceLabels(season))
                                        .font(.caption.weight(.semibold))
                                    if !badge.isEmpty {
                                        Text(ContentDisplayText.sourceLabels(badge))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.35), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(season == active ? Color.red : Color.secondary.opacity(0.18), in: Capsule())
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 9)], spacing: 9) {
                ForEach(visible) { episode in
                    Button {
                        selectedEpisode = episode
                    } label: {
                        Text(episode.title)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal)
    }

    private func startLoading(forceRefresh: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            await loadAsync(forceRefresh: forceRefresh)
        }
    }

    private func loadAsync(forceRefresh: Bool) async {
        message = ""
        do {
            if anime.source.isMovie {
                loading = detail == nil
                let full = try await service.detail(for: anime)
                try Task.checkCancellation()
                detail = full
                selectedSeason = full.episodes.first?.season ?? ""
                episodeStatus = full.episodes.isEmpty ? .unavailable("Nguồn này chưa có tập phát được.") : .available
                loading = false
                return
            }

            // Check existing cache first
            if !forceRefresh, let cached = service.cachedDetail(for: anime.id) {
                detail = cached
                selectedSeason = cached.episodes.first?.season ?? ""
                episodeStatus = cached.episodes.isEmpty ? .loading : .available
                loading = false
                if !cached.episodes.isEmpty { return }
            } else if detail == nil {
                // Instantly provide metadata view from anime model so screen is not blank
                detail = AnimeDetail(title: anime.title, posterURL: anime.imageURL, bannerURL: nil,
                                     summary: "", info: "", episodes: [])
                loading = false
            }

            episodeStatus = .loading
            let meta = try await service.detailMetadata(for: anime, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            detail = meta
            loading = false

            if !meta.episodes.isEmpty {
                selectedSeason = meta.episodes.first?.season ?? ""
                episodeStatus = .available
            }

            await Task.yield() // Let SwiftUI present metadata before parsing a large episode list.
            let fullEpisodes = try await service.loadEpisodes(for: anime, initialDetail: meta, forceRefresh: forceRefresh)
            try Task.checkCancellation()

            if !fullEpisodes.isEmpty {
                let complete = AnimeDetail(title: meta.title, posterURL: meta.posterURL, bannerURL: meta.bannerURL,
                                           summary: meta.summary, info: meta.info, episodes: fullEpisodes)
                detail = complete
                if selectedSeason.isEmpty || !fullEpisodes.contains(where: { $0.season == selectedSeason }) {
                    selectedSeason = fullEpisodes.first?.season ?? ""
                }
                episodeStatus = .available
            } else {
                episodeStatus = .unavailable("Chưa đọc được danh sách tập từ website. Hãy thử tải lại hoặc xác minh kết nối.")
            }
        } catch is CancellationError {
            // Screen dismissed
        } catch let err as AnimeServiceError {
            switch err {
            case .verificationRequired:
                episodeStatus = .verificationRequired
            default:
                if detail == nil || detail?.summary.isEmpty == true {
                    message = err.localizedDescription
                }
                episodeStatus = .networkError(err.localizedDescription)
            }
            service.register(err)
        } catch {
            if detail == nil || detail?.summary.isEmpty == true {
                message = error.localizedDescription
            }
            episodeStatus = .networkError(error.localizedDescription)
            service.register(error)
        }
        loading = false
    }
}

struct ServerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let episodes: [Episode]
    @Binding var selectedSeason: String
    let targetEpisodeNumber: Int?
    let onSelect: (Episode) -> Void

    private var servers: [(name: String, badge: String, count: Int, firstEpisode: Episode)] {
        var names: [String] = []
        for ep in episodes where !names.contains(ep.season) {
            names.append(ep.season)
        }
        return names.compactMap { name in
            let group = episodes.filter { $0.season == name }
            guard let first = group.first else { return nil }
            let matched = targetEpisodeNumber.flatMap { num in group.first(where: { $0.number == num }) } ?? first
            return (name: name, badge: first.qualityBadge, count: group.count, firstEpisode: matched)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("Chọn máy chủ (Server) phù hợp để bắt đầu phát với tốc độ và chất lượng tốt nhất:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ForEach(Array(servers.enumerated()), id: \.element.name) { idx, server in
                        let isSelected = server.name == selectedSeason
                        Button {
                            selectedSeason = server.name
                            onSelect(server.firstEpisode)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color.red.opacity(0.22) : Color.secondary.opacity(0.14))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: server.badge.contains("4K") ? "4k.tv.fill" : (server.name.contains("VIP") ? "bolt.fill" : "server.rack"))
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(isSelected ? .red : .anpinimeAccent)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text("Server \(idx + 1)")
                                            .font(.caption2.weight(.heavy))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.anpinimeAccent.opacity(0.22), in: Capsule())
                                            .foregroundColor(.anpinimeAccent)

                                        if !server.badge.isEmpty {
                                            Badge(text: ContentDisplayText.sourceLabels(server.badge), color: server.badge.contains("4K") ? .purple : .blue)
                                        }
                                        if server.count > 1 {
                                            Text("\(server.count) tập")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Text(ContentDisplayText.sourceLabels(server.name))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isSelected ? Color.red.opacity(0.10) : Color.secondary.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isSelected ? Color.red.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Chọn Server Phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
