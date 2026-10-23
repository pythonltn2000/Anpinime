import Foundation

enum ContentSource: String, CaseIterable, Identifiable {
    case anime, film4k, phim4k
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: return "AnimeVietsub"
        case .film4k: return "Nguồn phim 1"
        case .phim4k: return "Nguồn phim 2"
        }
    }
    var subtitle: String {
        switch self {
        case .anime: return "Anime"
        case .film4k: return "Nguồn phim 1"
        case .phim4k: return "Nguồn phim 2"
        }
    }
    var isMovie: Bool { self != .anime }
}

enum EpisodePlayback: Hashable {
    case animePage
    case film4k(slug: String, season: Int?, episode: Int?, server: Int)
    case phim4k(detailURL: URL, server: Int, index: Int)
}

struct ResolvedPlayback {
    let url: URL
    let headers: [String: String]
    let webURL: URL?
    let isWeb: Bool
}

struct PlaybackChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

struct PlaybackQuality: Identifiable, Hashable {
    let id: String
    let title: String
    let bandwidth: Double
    let width: Double
    let height: Double
    static let automatic = PlaybackQuality(id: "auto", title: "Tự động", bandwidth: 0, width: 0, height: 0)
}

struct Anime: Identifiable, Hashable {
    let title: String
    let url: URL
    let imageURL: URL?
    let episodeText: String
    let quality: String
    let score: String
    var source: ContentSource = .anime

    var id: String { source.rawValue + ":" + url.absoluteString }
}

struct AnimeSection: Identifiable, Hashable {
    let title: String
    let items: [Anime]

    var id: String { title }
}

struct Episode: Identifiable, Hashable {
    let title: String
    let url: URL
    let number: Int?
    let season: String
    var source: ContentSource = .anime
    var playback: EpisodePlayback = .animePage

    var id: String { source.rawValue + ":" + url.absoluteString + season + title }
}

struct AnimeDetail: Hashable {
    let title: String
    let posterURL: URL?
    let bannerURL: URL?
    let summary: String
    let info: String
    let episodes: [Episode]
}

struct AnimeCategory: Identifiable, Hashable {
    let title: String
    let path: String
    var id: String { path }
}

struct PlayerParameters: Equatable {
    let filmID: String
    let hash: String
}

enum AnimeServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case verificationRequired(URL)
    case http(Int)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Địa chỉ website không hợp lệ."
        case .invalidResponse: return "Website trả về phản hồi không hợp lệ."
        case .verificationRequired: return "Website yêu cầu xác minh trình duyệt."
        case .http(let status): return "Website trả về HTTP \(status)."
        case .emptyData: return "Không tìm thấy dữ liệu anime trong trang."
        }
    }
}
