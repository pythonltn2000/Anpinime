import SwiftUI

struct AnimeDetailView: View {
    @EnvironmentObject private var service: AnimeService
    let anime: Anime
    @State private var detail: AnimeDetail?
    @State private var loading = true
    @State private var message = ""
    @State private var selectedSeason = ""
    @State private var selectedEpisode: Episode?
    @State private var showingServerSheet = false
    @State private var pendingEpisodeNumber: Int? = nil

    private func orderedSeasons(_ episodes: [Episode]) -> [String] {
        episodes.reduce(into: [String]()) { result, ep in
            if !result.contains(ep.season) { result.append(ep.season) }
        }
    }

    var body: some View {
        Group {
            if loading { LoadingView(text: "Đang tải thông tin phim…") }
            else if let detail { detailContent(detail) }
            else {
                EmptyStateView(icon: "exclamationmark.triangle", title: "Không tải được chi tiết", message: message, actionTitle: "Thử lại") {
                    Task { await load() }
                }
            }
        }
        .navigationTitle(detail?.title ?? anime.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: service.verificationGeneration) { _ in Task { await load() } }
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

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: detail.bannerURL ?? detail.posterURL)
                        .frame(maxWidth: .infinity).frame(height: 245).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 14) {
                        RemoteImage(url: detail.posterURL)
                            .frame(width: 105, height: 150).clipped().cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(detail.title).font(.title2.bold()).foregroundColor(.white)
                            if !detail.info.isEmpty {
                                Text(detail.info).font(.caption).foregroundColor(.white.opacity(0.82)).lineLimit(3)
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
                    }
                    .padding()
                }

                if let first = activeEpisodes.first ?? detail.episodes.first {
                    HStack(spacing: 10) {
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
                    }
                    .padding(.horizontal)
                } else {
                    Text("Nguồn này chưa có tập phát được.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nội dung").font(.headline)
                    Text(detail.summary).font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if !detail.episodes.isEmpty {
                    episodeSection(detail.episodes, seasons: seasons, active: activeSeason, visible: activeEpisodes)
                }
            }
            .padding(.bottom, 24)
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
                        Label("Tất cả server", systemImage: "list.bullet.rectangle")
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
                                    Text(season)
                                        .font(.caption.weight(.semibold))
                                    if !badge.isEmpty {
                                        Text(badge)
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

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await service.detail(for: anime)
            detail = value
            selectedSeason = value.episodes.first?.season ?? ""
            message = ""
        } catch {
            detail = nil
            message = error.localizedDescription
            service.register(error)
        }
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
                                            Badge(text: server.badge, color: server.badge.contains("4K") ? .purple : .blue)
                                        }
                                        if server.count > 1 {
                                            Text("\(server.count) tập")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Text(server.name)
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
