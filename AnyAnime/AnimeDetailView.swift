import SwiftUI

struct AnimeDetailView: View {
    @EnvironmentObject private var service: AnimeService
    let anime: Anime
    @State private var detail: AnimeDetail?
    @State private var loading = true
    @State private var message = ""
    @State private var selectedSeason = ""
    @State private var selectedEpisode: Episode?

    var body: some View {
        Group {
            if loading { LoadingView(text: "Đang tải thông tin anime…") }
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
        .fullScreenCover(item: $selectedEpisode) { episode in
            PlayerView(episode: episode)
                .environmentObject(service)
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: AnimeDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: detail.bannerURL ?? detail.posterURL)
                        .frame(maxWidth: .infinity).frame(height: 230).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 14) {
                        RemoteImage(url: detail.posterURL)
                            .frame(width: 105, height: 150).clipped().cornerRadius(8)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(detail.title).font(.title2.bold()).foregroundColor(.white)
                            if !detail.info.isEmpty {
                                Text(detail.info).font(.caption).foregroundColor(.white.opacity(0.8)).lineLimit(3)
                            }
                        }
                    }
                    .padding()
                }

                if let first = detail.episodes.first {
                    Button { selectedEpisode = first } label: {
                        Label("Xem phim", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red).padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nội dung").font(.headline)
                    Text(detail.summary).font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if !detail.episodes.isEmpty {
                    episodeSection(detail.episodes)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func episodeSection(_ episodes: [Episode]) -> some View {
        let seasons = Array(Set(episodes.map(\.season))).sorted()
        let active = selectedSeason.isEmpty ? (seasons.first ?? "Phần 1") : selectedSeason
        let visible = episodes.filter { $0.season == active }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Danh sách tập (\(episodes.count))").font(.headline)
                Spacer()
            }
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(seasons, id: \.self) { season in
                            Button(season) { selectedSeason = season }
                                .buttonStyle(.borderedProminent)
                                .tint(season == active ? .red : .gray)
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 9)], spacing: 9) {
                ForEach(visible) { episode in
                    Button(episode.title) { selectedEpisode = episode }
                        .font(.caption.weight(.semibold))
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

