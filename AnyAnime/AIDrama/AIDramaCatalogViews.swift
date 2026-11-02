import SwiftUI

enum AIDramaTheme {
    static let background = Color(red: 0.035, green: 0.025, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.065, blue: 0.14)
}

struct AIDramaArtwork: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            AIDramaTheme.surface
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "film.stack").font(.title).foregroundColor(.white.opacity(0.3)) }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(12)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct AIDramaSeriesButton: View {
    let series: AIDramaSeries
    let width: CGFloat
    var loading = false
    var statistics: String? = nil
    var identifierPrefix = "aidrama.series."
    let open: (AIDramaSeries) -> Void

    private var displayStatistics: String? {
        statistics ?? series.viewCount.map { "\($0.formatted()) lượt xem" }
    }

    var body: some View {
        Button { open(series) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    AIDramaArtwork(url: series.coverURL, width: width, height: width / 0.68)
                    if let count = series.episodeCount {
                        Text("\(count) tập").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(Color.black.opacity(0.72), in: Capsule())
                            .padding(7)
                    }
                    if loading {
                        Color.black.opacity(0.5).cornerRadius(12)
                        ProgressView().tint(.white).frame(width: width, height: width / 0.68)
                    }
                }
                Text(series.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(width: width, alignment: .leading)
                if let statistics = displayStatistics, !statistics.isEmpty {
                    Text(statistics).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityLabel(series.title + (displayStatistics.map { ", " + $0 } ?? "")
            + (series.episodeCount.map { ", \($0) tập" } ?? ""))
        .accessibilityHint("Mở phim")
        .accessibilityIdentifier(identifierPrefix + series.id)
    }
}

struct AIDramaCatalogGrid: View {
    let series: [AIDramaSeries]
    let availableWidth: CGFloat
    var loadingID: String? = nil
    let open: (AIDramaSeries) -> Void

    private var columnCount: Int { min(4, max(2, Int(availableWidth / 155))) }
    private var cardWidth: CGFloat { max(1, (availableWidth - CGFloat(columnCount - 1) * 12) / CGFloat(columnCount)) }
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(cardWidth), spacing: 12, alignment: .top), count: columnCount) }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(series) { item in
                AIDramaSeriesButton(series: item, width: cardWidth, loading: loadingID == item.id, open: open)
            }
        }
        .frame(width: max(1, availableWidth), alignment: .leading)
    }
}

@MainActor
struct AIDramaHeroCarousel: View {
    let series: [AIDramaSeries]
    let width: CGFloat
    var loadingID: String? = nil
    var canLoadMore = false
    var loadingMore = false
    var error: String? = nil
    var loadMore: (() async -> Void)? = nil
    let open: (AIDramaSeries) -> Void
    @State private var selectedSeriesID = ""

    var body: some View {
        VStack(spacing: 0) {
            pages
            if loadingMore {
                ProgressView("Đang tải thêm…").tint(.anpinimeAccent).padding(12)
            } else if let error {
                VStack(spacing: 10) {
                    Text(error).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    if canLoadMore, let loadMore {
                        Button("Thử lại") { Task { await loadMore() } }.buttonStyle(.bordered)
                    }
                }.padding(16)
            }
        }
        .onAppear { preserveSelection(); loadMoreIfNeeded() }
        .onChange(of: series.map(\.id)) { _ in preserveSelection(); loadMoreIfNeeded() }
        .onChange(of: selectedSeriesID) { _ in loadMoreIfNeeded() }
        .onChange(of: canLoadMore) { _ in loadMoreIfNeeded() }
    }

    private var pages: some View {
        TabView(selection: $selectedSeriesID) {
            ForEach(series) { item in
                Button { open(item) } label: {
                    ZStack(alignment: .bottomLeading) {
                        AIDramaArtwork(url: item.coverURL, width: width, height: 420)
                        LinearGradient(colors: [.clear, AIDramaTheme.background.opacity(0.3), AIDramaTheme.background],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("PHIM AI").font(.caption.weight(.heavy)).tracking(2).foregroundColor(.anpinimeAccent)
                            Text(item.title).font(.title2.bold()).lineLimit(3)
                            HStack(spacing: 12) {
                                if let count = item.episodeCount { Text("\(count) tập") }
                                if let views = item.viewCount { Label("\(views.formatted()) lượt xem", systemImage: "eye") }
                            }.font(.caption).foregroundColor(.white.opacity(0.8))
                            Label("Xem ngay", systemImage: "play.fill").font(.subheadline.weight(.bold))
                                .padding(.horizontal, 17).padding(.vertical, 11)
                                .background(Color.anpinimeAccent, in: Capsule())
                        }
                        .padding(22).padding(.bottom, 24)
                        if loadingID == item.id {
                            Color.black.opacity(0.45)
                            ProgressView("Đang tải danh sách tập…").tint(.white)
                                .frame(width: width, height: 420)
                        }
                    }
                    .frame(width: width, height: 420)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loadingID == item.id)
                        .accessibilityLabel(item.title + (item.viewCount.map { ", \($0.formatted()) lượt xem" } ?? "") + (item.episodeCount.map { ", \($0) tập" } ?? ""))
                .accessibilityHint("Mở phim nổi bật")
                .accessibilityIdentifier("aidrama.series." + item.id)
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: series.count > 1 ? .automatic : .never))
        .frame(height: 420)
    }

    private func preserveSelection() {
        if !series.contains(where: { $0.id == selectedSeriesID }) {
            selectedSeriesID = series.first?.id ?? ""
        }
    }

    private func loadMoreIfNeeded() {
        guard canLoadMore, error == nil, let loadMore,
              let index = series.firstIndex(where: { $0.id == selectedSeriesID }),
              index >= max(0, series.count - 2) else { return }
        Task { await loadMore() }
    }
}

struct AIDramaHorizontalRow: View {
    let title: String
    let series: [AIDramaSeries]
    var loadingID: String? = nil
    let identifierPrefix: String
    var more: (() -> Void)? = nil
    var canLoadMore = false
    var loadingMore = false
    var error: String? = nil
    var loadMore: (() async -> Void)? = nil
    let open: (AIDramaSeries) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                if let more {
                    Button(action: more) { Label("Xem thêm", systemImage: "chevron.right").font(.caption.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundColor(.anpinimeAccent)
                }
            }.padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(series) { item in
                        AIDramaSeriesButton(series: item, width: 132, loading: loadingID == item.id,
                                            identifierPrefix: identifierPrefix, open: open)
                    }
                    if loadingMore {
                        ProgressView().tint(.anpinimeAccent).frame(width: 64, height: 190)
                    } else if canLoadMore, let loadMore {
                        if error == nil {
                            Color.clear.frame(width: 32, height: 190).onAppear { Task { await loadMore() } }
                        } else {
                            Button("Thử lại") { Task { await loadMore() } }.frame(width: 90, height: 190)
                        }
                    }
                }.padding(.horizontal, 16)
            }
        }
    }
}

struct AIDramaRankedRow: View {
    let series: AIDramaSeries
    let rank: Int
    var loading = false
    let open: (AIDramaSeries) -> Void

    var body: some View {
        Button { open(series) } label: {
            HStack(alignment: .center, spacing: 13) {
                Text(String(rank)).font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundColor(rank <= 3 ? .anpinimeAccent : .white.opacity(0.4))
                    .frame(width: 36)
                AIDramaArtwork(url: series.coverURL, width: 80, height: 116)
                    .overlay { if loading { ProgressView().tint(.white) } }
                VStack(alignment: .leading, spacing: 9) {
                    Text(series.title).font(.headline).lineLimit(3)
                    if let count = series.episodeCount {
                        Text("\(count) tập").font(.caption).foregroundColor(.secondary)
                    }
                    if let views = series.viewCount {
                        Label("\(views.formatted()) lượt xem", systemImage: "eye").font(.caption).foregroundColor(.secondary)
                    }
                    if !series.genreText.isEmpty {
                        Text(series.genreText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    if !series.summary.isEmpty {
                        Text(series.summary).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.circle.fill").font(.title2).foregroundColor(.anpinimeAccent)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityLabel("Hạng \(rank), " + series.title + (series.episodeCount.map { ", \($0) tập" } ?? ""))
        .accessibilityHint("Mở phim")
        .accessibilityIdentifier("aidrama.series." + series.id)
    }
}

struct AIDramaCatalogMessage: View {
    var loading = false
    let message: String?
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            if loading { ProgressView("Đang tải Phim AI…").tint(.anpinimeAccent) }
            else {
                Image(systemName: "film.stack").font(.largeTitle).foregroundColor(.secondary)
                Text(message ?? "Chưa có phim để hiển thị").font(.subheadline)
                    .foregroundColor(.secondary).multilineTextAlignment(.center)
                if let retry {
                    Button("Thử lại", action: retry).buttonStyle(.borderedProminent).tint(.anpinimeAccent)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct AIDramaPagingFooter: View {
    let loading: Bool
    let canLoadMore: Bool
    let error: String?
    let loadMore: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            if loading { ProgressView("Đang tải thêm…").tint(.anpinimeAccent) }
            else if let error {
                Text(error).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                if canLoadMore { Button("Thử lại") { Task { await loadMore() } }.buttonStyle(.bordered) }
            } else if canLoadMore {
                Color.clear.frame(height: 32).onAppear { Task { await loadMore() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
