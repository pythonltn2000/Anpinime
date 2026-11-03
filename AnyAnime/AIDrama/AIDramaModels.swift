import Foundation

/// PineDrama data stays independent of the existing movie/anime source IDs.
struct AIDramaSeries: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    var coverURL: URL? = nil
    var summary: String = ""
    var episodeCount: Int? = nil
    var viewCount: Int? = nil
    var genreText: String = ""
}

extension AIDramaSeries {
    private enum CodingKeys: String, CodingKey { case id, title, coverURL, summary, episodeCount, viewCount, genreText }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        coverURL = try values.decodeIfPresent(URL.self, forKey: .coverURL)
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        episodeCount = try values.decodeIfPresent(Int.self, forKey: .episodeCount)
        viewCount = try values.decodeIfPresent(Int.self, forKey: .viewCount)
        genreText = try values.decodeIfPresent(String.self, forKey: .genreText) ?? ""
    }
}

struct AIDramaEpisode: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let seriesID: String
    let number: Int
    var title: String = ""
    var coverURL: URL? = nil
    var isLocked: Bool = false

    var displayTitle: String { title.isEmpty ? "Tập \(number)" : title }
}

struct AIDramaCatalogPage: Sendable {
    let series: [AIDramaSeries]
    let nextCursor: String?
    let hasMore: Bool

    init(series: [AIDramaSeries], nextCursor: String?, hasMore: Bool? = nil) {
        self.series = series
        self.nextCursor = nextCursor
        self.hasMore = hasMore ?? (nextCursor != nil)
    }
}

enum AIDramaRanking: String, CaseIterable, Hashable, Sendable {
    case hot, latest
}

struct AIDramaCategorySelection: Hashable, Sendable {
    var backgroundID: String? = nil
    var characterID: String? = nil
    var storyID: String? = nil
    var recentDays: Int = 0
}

enum AIDramaCatalogQuery: Hashable, Sendable {
    case home
    case trending(AIDramaRanking)
    case categories(AIDramaCategorySelection)
    case newWorks
}

struct AIDramaFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let categoryID: String?
    let recentDays: Int?
}

struct AIDramaFilterGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Hashable, Sendable {
        case background, character, story, releaseTime
    }
    let kind: Kind
    let title: String
    let options: [AIDramaFilterOption]
    var id: Kind { kind }
}

struct AIDramaCatalogMetadata: Sendable {
    let filterGroups: [AIDramaFilterGroup]
}

/// Providers return this only after consuming and validating the full episode list.
struct AIDramaPlaylist: Sendable {
    let series: AIDramaSeries
    let episodes: [AIDramaEpisode]
    let reportedTotal: Int?
}

struct AIDramaStream: Sendable {
    let url: URL
    var headers: [String: String] = [:]
}

struct AIDramaShortVideo: Identifiable, Sendable {
    let series: AIDramaSeries
    let episode: AIDramaEpisode
    let isLandscape: Bool
    var id: String { episode.id }
}

struct AIDramaShortFeedPage: Sendable {
    let videos: [AIDramaShortVideo]
    let hasMore: Bool
}

protocol AIDramaProviding: Sendable {
    func shortFeed(loadedVideoIDs: [String]) async throws -> AIDramaShortFeedPage
    func discover(cursor: String?) async throws -> AIDramaCatalogPage
    func catalog(query: AIDramaCatalogQuery, cursor: String?, loadedSeriesIDs: [String]) async throws -> AIDramaCatalogPage
    func catalogMetadata() async throws -> AIDramaCatalogMetadata
    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist
    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream
}

extension AIDramaProviding {
    func shortFeed(loadedVideoIDs: [String]) async throws -> AIDramaShortFeedPage {
        throw AIDramaError.unavailable("Nguồn phim chưa trả luồng Phim ngắn.")
    }

    func catalog(query: AIDramaCatalogQuery, cursor: String?, loadedSeriesIDs: [String] = []) async throws -> AIDramaCatalogPage {
        guard query == .home else { throw AIDramaError.unavailable("Nguồn Phim AI chưa cung cấp mục này.") }
        return try await discover(cursor: cursor)
    }

    func catalogMetadata() async throws -> AIDramaCatalogMetadata {
        AIDramaCatalogMetadata(filterGroups: [])
    }
}

enum AIDramaError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case incompletePlaylist
    case lockedEpisode
    case missingEpisode

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidResponse: return "Phim AI chưa trả dữ liệu hợp lệ."
        case .incompletePlaylist: return "Chưa tải được đầy đủ danh sách tập. Hãy thử lại."
        case .lockedEpisode: return "Nguồn phim chưa cho phép phát tập này."
        case .missingEpisode: return "Tập đã chọn không còn trong danh sách của bộ phim."
        }
    }
}
