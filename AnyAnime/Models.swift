import Foundation

struct Anime: Identifiable, Hashable {
    let title: String
    let url: URL
    let imageURL: URL?
    let episodeText: String
    let quality: String
    let score: String

    var id: String { url.absoluteString }
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

    var id: String { url.absoluteString + title }
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
