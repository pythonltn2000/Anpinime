import Foundation

/// PineDrama data stays independent of the existing movie/anime source IDs.
struct AIDramaSeries: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    var coverURL: URL? = nil
    var summary: String = ""
    var episodeCount: Int? = nil
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

protocol AIDramaProviding: Sendable {
    func discover(cursor: String?) async throws -> AIDramaCatalogPage
    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist
    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream
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
