import SwiftUI
import UIKit

@MainActor
struct AnimeSearchView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var resultsRequest: SearchRequest?
    @State private var loading = false
    @State private var message = "Nhập tên phim để tìm trong nguồn đang chọn"
    @State private var searchID = UUID()
    @State private var history: [String] = []
    @State private var selectedAnime: Anime?
    @State private var showingDetail = false
    private let historyStore = SearchHistory()

    private struct SearchRequest: Equatable {
        let query: String
        let source: ContentSource
        let verificationGeneration: Int
    }

    private var request: SearchRequest {
        SearchRequest(query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                      source: service.source, verificationGeneration: service.verificationGeneration)
    }

    var body: some View {
        ZStack {
            if request.query.isEmpty && !history.isEmpty {
                List {
                    Section(header: Text("Tìm kiếm gần đây · " + service.source.title)) {
                        ForEach(history, id: \.self) { value in
                            Button { query = value; remember(value, source: service.source) } label: {
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
            } else if !request.query.isEmpty && (loading || resultsRequest != request) {
                LoadingView(text: "Đang tìm kiếm…")
            } else if request.query.isEmpty || results.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Tìm \(service.contentName)", message: request.query.isEmpty ? "Nhập tên phim để tìm trong nguồn đang chọn" : ContentDisplayText.sourceLabels(message), actionTitle: nil, action: nil)
            } else {
                List(results) { anime in
                    Button { select(anime) } label: {
                        SearchResultRow(anime: anime)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel(resultAccessibilityLabel(anime))
                    .accessibilityHint("Mở thông tin phim")
                    .accessibilityIdentifier("search-result-" + anime.id)
                }
                .listStyle(.plain)
            }
        }
        .background {
            NavigationLink(isActive: $showingDetail) {
                if let selectedAnime { AnimeDetailView(anime: selectedAnime) }
            } label: { EmptyView() }
                .hidden()
        }
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, prompt: service.source.title)
        .onSubmit(of: .search) {
            remember(request.query, source: request.source)
            dismissKeyboard()
        }
        .task(id: request) { await search(request) }
    }

    private func remember(_ query: String, source: ContentSource) {
        historyStore.record(query, source: source)
        history = historyStore.queries(for: source)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resultAccessibilityLabel(_ anime: Anime) -> String {
        [anime.title, anime.subtitle,
         ContentDisplayText.sourceLabels(anime.catalogLabel.isEmpty ? anime.source.title : anime.catalogLabel),
         anime.episodeText, anime.quality, anime.score]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func select(_ anime: Anime) {
        // Capture the exact displayed object, before dismissing the search keyboard.
        guard let resultsRequest, resultsRequest == request else { return }
        selectedAnime = anime
        remember(resultsRequest.query, source: resultsRequest.source)
        dismissKeyboard()
        showingDetail = true
    }

    private func search(_ requested: SearchRequest) async {
        let id = UUID()
        searchID = id
        history = historyStore.queries(for: requested.source)
        results = []
        resultsRequest = nil
        loading = !requested.query.isEmpty
        defer { if searchID == id { loading = false } }
        guard !requested.query.isEmpty else {
            message = "Nhập tên phim để tìm trong nguồn đang chọn"
            return
        }
        do {
            try await Task.sleep(nanoseconds: 350_000_000)
            let found = try await service.search(requested.query, source: requested.source)
            try Task.checkCancellation()
            guard request == requested, searchID == id else { return }
            // Some catalogs repeat an entry. Keep its stable provider/URL identity once.
            var seen = Set<String>()
            results = found.filter { seen.insert($0.id).inserted }
            resultsRequest = requested
            message = results.isEmpty ? "Không tìm thấy kết quả cho \"\(requested.query)\"" : ""
        } catch {
            guard !Task.isCancelled, request == requested, searchID == id else { return }
            results = []
            resultsRequest = requested
            message = error.localizedDescription
            service.register(error)
        }
    }
}

private struct SearchResultRow: View {
    let anime: Anime

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: anime.imageURL)
                .frame(width: 68, height: 96)
                .clipped()
                .cornerRadius(8)
                // Clipping artwork alone does not constrain SwiftUI's hit-test region.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(anime.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !anime.subtitle.isEmpty {
                    Text(anime.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(ContentDisplayText.sourceLabels(anime.catalogLabel.isEmpty ? anime.source.title : anime.catalogLabel))
                    .font(.caption2).foregroundStyle(.secondary)
                Text([anime.episodeText, anime.quality].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption).foregroundStyle(.secondary)
                if !anime.score.isEmpty {
                    Label(anime.score, systemImage: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.09)))
        .contentShape(Rectangle())
    }
}
