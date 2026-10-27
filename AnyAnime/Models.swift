import Foundation

enum ContentSource: String, CaseIterable, Identifiable {
    case anime, film4k, phim4k, kkphim
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anime: return "AnimeVietsub"
        case .film4k: return "Nguồn 1 · NguonC"
        case .phim4k: return "Nguồn 2 · Phim4K"
        case .kkphim: return "Nguồn 3 · KKPhim"
        }
    }
    var subtitle: String {
        switch self {
        case .anime: return "Anime"
        case .film4k: return "Nguồn 1 · NguonC"
        case .phim4k: return "Nguồn 2 · Phim4K"
        case .kkphim: return "Nguồn 3 · KKPhim"
        }
    }
    var isMovie: Bool { self != .anime }
}

enum EpisodePlayback: Hashable {
    case animePage
    case film4k(slug: String, season: Int?, episode: Int?, server: Int)
    case catalogEpisode(detailURL: URL, serverName: String, episodeKey: String)
    case phim4kCore(detailURL: URL, seasonID: String?, episodeID: String)
    case directStream(url: URL, webURL: URL?, isWeb: Bool, referer: URL?)
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
    var subtitle: String = ""
    let url: URL
    let imageURL: URL?
    var bannerURL: URL? = nil
    let episodeText: String
    let quality: String
    let score: String
    var summary: String = ""
    var info: String = ""
    var source: ContentSource = .anime
    var catalogLabel: String = ""

    var id: String { source.rawValue + ":" + url.absoluteString }
}

struct AnimeSection: Identifiable, Hashable {
    let title: String
    let items: [Anime]
    var categoryPath: String? = nil

    var id: String { title }
}

struct Episode: Identifiable, Hashable {
    let title: String
    let url: URL
    let number: Int?
    let season: String
    var qualityBadge: String = ""
    var source: ContentSource = .anime
    var playback: EpisodePlayback = .animePage

    var id: String { source.rawValue + ":" + url.absoluteString + "|" + season + "|" + title + "|" + qualityBadge }
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
    var group: String = ""
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
