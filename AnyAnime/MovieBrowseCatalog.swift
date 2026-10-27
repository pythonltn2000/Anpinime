import Foundation

/// The website menus are provider-specific; a shared API schema is not a shared menu.
enum MovieBrowseCatalog {
    static let kkLists: [(String, String)] = [
        ("Phim Mới", "v1/api/danh-sach"),
        ("Phim Lẻ", "v1/api/danh-sach/phim-le"),
        ("Phim Bộ", "v1/api/danh-sach/phim-bo"),
        ("Hoạt Hình", "v1/api/danh-sach/hoat-hinh"),
        ("TV Shows", "v1/api/danh-sach/tv-shows"),
        ("Phim Vietsub", "v1/api/danh-sach/phim-vietsub"),
        ("Phim Thuyết Minh", "v1/api/danh-sach/phim-thuyet-minh"),
        ("Phim Lồng Tiếng", "v1/api/danh-sach/phim-long-tieng"),
        ("Phim Chiếu Rạp", "v1/api/danh-sach/phim-chieu-rap"),
        ("Phim Bộ Đang Chiếu", "site/danh-sach/phim-bo-dang-chieu"),
        ("Phim Bộ Đã Hoàn Thành", "site/danh-sach/phim-bo-hoan-thanh"),
        ("Subteam", "v1/api/danh-sach/subteam")
    ]
    static let kkWebsiteLists: Set<String> = ["site/danh-sach/phim-bo-dang-chieu", "site/danh-sach/phim-bo-hoan-thanh"]

    static func defaults(for source: ContentSource) -> [AnimeCategory] {
        if source == .kkphim {
            return kkLists.map { AnimeCategory(title: $0.0, path: $0.1, group: "Danh sách phim") }
                + kkGenres.map { AnimeCategory(title: $0.0, path: "v1/api/the-loai/" + $0.1, group: "Thể loại") }
                + kkCountries.map { AnimeCategory(title: $0.0, path: "v1/api/quoc-gia/" + $0.1, group: "Quốc gia") }
        }
        if source == .film4k {
            var categories = [AnimeCategory(title: "Phim mới cập nhật", path: "api/films/phim-moi-cap-nhat", group: "Danh sách phim")]
            categories += nguoncLists.map { AnimeCategory(title: $0.0, path: "api/films/danh-sach/" + $0.1, group: "Danh sách phim") }
            categories += nguoncGenres.map { AnimeCategory(title: $0.0, path: "api/films/the-loai/" + $0.1, group: "Thể loại") }
            categories += nguoncCountries.map { AnimeCategory(title: $0.0, path: "api/films/quoc-gia/" + $0.1, group: "Quốc gia") }
            categories += (2015...Calendar.current.component(.year, from: Date())).reversed().map {
                    AnimeCategory(title: String($0), path: "api/films/nam-phat-hanh/\($0)", group: "Năm phát hành")
                }
            categories += [("Vietsub", "vietsub"), ("Thuyết minh", "thuyet-minh"), ("Lồng tiếng", "long-tieng")].map {
                    AnimeCategory(title: $0.0, path: "api/films/ngon-ngu/" + $0.1, group: "Ngôn ngữ")
                }
            return categories
        }
        return []
    }

    static func nguoncMenu(_ html: String) -> [AnimeCategory] {
        let base = URL(string: "https://phim.nguonc.com")!
        var seen = Set<String>()
        return HTMLDocument.links(html).compactMap { link in
            guard let href = link.attributes["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.host == base.host, url.query == nil, url.fragment == nil else { return nil }
            let parts = url.path.split(separator: "/").map(String.init)
            let groups = ["danh-sach": "Danh sách phim", "the-loai": "Thể loại", "quoc-gia": "Quốc gia", "nam-phat-hanh": "Năm phát hành"]
            guard parts.count == 2, let group = groups[parts[0]], !link.text.isEmpty,
                  seen.insert(url.path).inserted else { return nil }
            return AnimeCategory(title: link.text, path: "api/films/" + parts.joined(separator: "/"), group: group)
        }
    }

    static func kkTaxonomy(_ json: MovieCatalog.Object, group: String, path: String) -> [AnimeCategory] {
        let data = json["data"] as? MovieCatalog.Object ?? json
        let rows = data["items"] as? [MovieCatalog.Object] ?? json["items"] as? [MovieCatalog.Object] ?? []
        return rows.compactMap { row in
            let slug = MovieCatalog.text(row["slug"]), name = MovieCatalog.text(row["name"])
            guard !slug.isEmpty, !name.isEmpty, !slug.contains("/") else { return nil }
            return AnimeCategory(title: name, path: path + slug, group: group)
        }
    }

    static func kkWebsiteItems(_ html: String) -> [Anime] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) else { return [] }
        let string = html as NSString
        let api = URL(string: "https://phimapi.com")!, site = URL(string: "https://kkphim.com")!
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let block = string.substring(with: match.range(at: 1))
            guard let link = HTMLDocument.links(block).first(where: { $0.marker.split(separator: " ").contains("info-title") }),
                  let href = link.attributes["href"], let url = URL(string: href, relativeTo: site)?.absoluteURL,
                  url.host == site.host, url.path.hasPrefix("/phim/"), !link.text.isEmpty,
                  seen.insert(url.lastPathComponent).inserted else { return nil }
            let status = capture(#"(?is)<div[^>]*class="info-status-sm"[^>]*>(.*?)</div>"#, block).map(HTMLDocument.text) ?? ""
            let origin = capture(#"(?is)<div[^>]*class="info-origin"[^>]*>(.*?)</div>"#, block).map(HTMLDocument.text) ?? ""
            return Anime(title: link.text, subtitle: origin, url: MovieCatalog.route("phim/" + url.lastPathComponent, base: api),
                         imageURL: HTMLParser.imageSource(in: block).flatMap { MovieCatalog.url($0, base: site) },
                         episodeText: status, quality: "", score: "", source: .kkphim)
        }
    }

    private static func capture(_ pattern: String, _ value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else { return nil }
        return (value as NSString).substring(with: match.range(at: 1))
    }
    private static let kkGenres: [(String, String)] = [
        ("Bí Ẩn", "bi-an"),
        ("Chiến Tranh", "chien-tranh"),
        ("Chính Kịch", "chinh-kich"),
        ("Cổ Trang", "co-trang"),
        ("Gia Đình", "gia-dinh"),
        ("Hài Hước", "hai-huoc"),
        ("Hành Động", "hanh-dong"),
        ("Hình Sự", "hinh-su"),
        ("Học Đường", "hoc-duong"),
        ("Khoa Học", "khoa-hoc"),
        ("Kinh Dị", "kinh-di"),
        ("Kinh Điển", "kinh-dien"),
        ("Lịch Sử", "lich-su"),
        ("Miền Tây", "mien-tay"),
        ("Phim 18+", "phim-18"),
        ("Phim Ngắn", "phim-ngan"),
        ("Phiêu Lưu", "phieu-luu"),
        ("Thần Thoại", "than-thoai"),
        ("Thể Thao", "the-thao"),
        ("Trẻ Em", "tre-em"),
        ("Tài Liệu", "tai-lieu"),
        ("Tâm Lý", "tam-ly"),
        ("Tình Cảm", "tinh-cam"),
        ("Viễn Tưởng", "vien-tuong"),
        ("Võ Thuật", "vo-thuat"),
        ("Âm Nhạc", "am-nhac"),
    ]
    private static let kkCountries: [(String, String)] = [
        ("Anh", "anh"),
        ("Ba Lan", "ba-lan"),
        ("Brazil", "brazil"),
        ("Bồ Đào Nha", "bo-dao-nha"),
        ("Canada", "canada"),
        ("Châu Phi", "chau-phi"),
        ("Hà Lan", "ha-lan"),
        ("Hàn Quốc", "han-quoc"),
        ("Hồng Kông", "hong-kong"),
        ("Indonesia", "indonesia"),
        ("Malaysia", "malaysia"),
        ("Mexico", "mexico"),
        ("Na Uy", "na-uy"),
        ("Nam Phi", "nam-phi"),
        ("Nga", "nga"),
        ("Nhật Bản", "nhat-ban"),
        ("Philippines", "philippines"),
        ("Pháp", "phap"),
        ("Quốc Gia Khác", "quoc-gia-khac"),
        ("Thái Lan", "thai-lan"),
        ("Thổ Nhĩ Kỳ", "tho-nhi-ky"),
        ("Thụy Sĩ", "thuy-si"),
        ("Thụy Điển", "thuy-dien"),
        ("Trung Quốc", "trung-quoc"),
        ("Tây Ban Nha", "tay-ban-nha"),
        ("UAE", "uae"),
        ("Ukraina", "ukraina"),
        ("Việt Nam", "viet-nam"),
        ("Âu Mỹ", "au-my"),
        ("Úc", "uc"),
        ("Ý", "y"),
        ("Đan Mạch", "dan-mach"),
        ("Đài Loan", "dai-loan"),
        ("Đức", "duc"),
        ("Ả Rập Xê Út", "a-rap-xe-ut"),
        ("Ấn Độ", "an-do"),
    ]
    private static let nguoncLists: [(String, String)] = [
        ("TV shows", "tv-shows"),
        ("Phim lẻ", "phim-le"),
        ("Phim bộ", "phim-bo"),
        ("Phim AI", "phim-ai"),
    ]
    private static let nguoncGenres: [(String, String)] = [
        ("Hành Động", "hanh-dong"),
        ("Phiêu Lưu", "phieu-luu"),
        ("Hoạt Hình", "hoat-hinh"),
        ("Hài", "phim-hai"),
        ("Hình Sự", "hinh-su"),
        ("Tài Liệu", "tai-lieu"),
        ("Chính Kịch", "chinh-kich"),
        ("Gia Đình", "gia-dinh"),
        ("Giả Tưởng", "gia-tuong"),
        ("Lịch Sử", "lich-su"),
        ("Kinh Dị", "kinh-di"),
        ("Nhạc", "phim-nhac"),
        ("Bí Ẩn", "bi-an"),
        ("Lãng Mạn", "lang-man"),
        ("Khoa Học Viễn Tưởng", "khoa-hoc-vien-tuong"),
        ("Gây Cấn", "gay-can"),
        ("Chiến Tranh", "chien-tranh"),
        ("Tâm Lý", "tam-ly"),
        ("Tình Cảm", "tinh-cam"),
        ("Cổ Trang", "co-trang"),
        ("Miền Tây", "mien-tay"),
        ("Phim 18+", "phim-18"),
    ]
    private static let nguoncCountries: [(String, String)] = [
        ("Nhật Bản", "nhat-ban"),
        ("Trung Quốc", "trung-quoc"),
        ("Mỹ", "my"),
        ("Hàn Quốc", "han-quoc"),
        ("Anh", "anh"),
        ("Hồng Kông", "hong-kong"),
        ("Pháp", "phap"),
        ("Ca-na-đa", "canada"),
        ("Thái Lan", "thai-lan"),
        ("Đức", "duc"),
        ("Ấn Độ", "an-do"),
        ("Tây Ban Nha", "tay-ban-nha"),
        ("Việt Nam", "viet-nam"),
        ("Italy", "italy"),
        ("Úc", "uc"),
        ("Đài Loan", "dai-loan"),
        ("Phi-líp-pin", "philippines"),
        ("Bỉ", "bi"),
        ("Nga", "nga"),
        ("Bra-xin", "brazil"),
    ]
}
