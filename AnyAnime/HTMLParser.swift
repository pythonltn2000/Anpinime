import Foundation

enum HTMLParser {
    static func sections(from html: String, baseURL: URL) -> [AnimeSection] {
        let sectionPattern = #"(?is)<section\b[^>]*>(.*?)</section>"#
        var output: [AnimeSection] = []

        for match in matches(sectionPattern, in: html) {
            guard match.numberOfRanges > 1 else { continue }
            let block = substring(html, range: match.range(at: 1))
            let title = first(#"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>"#, in: block)
                .map(cleanText) ?? "Anime mới cập nhật"
            let items = animes(from: block, baseURL: baseURL)
            if !items.isEmpty { output.append(AnimeSection(title: title, items: items)) }
        }

        if output.isEmpty {
            let items = animes(from: html, baseURL: baseURL)
            if !items.isEmpty { output = [AnimeSection(title: "Anime mới cập nhật", items: items)] }
        }
        return uniqueSections(output)
    }

    static func animes(from html: String, baseURL: URL) -> [Anime] {
        let markerPattern = #"(?is)<(?:article|div|li)\b[^>]*class=[\"'][^\"']*(?:TPost|ml-item|film-item|movie-item)[^\"']*[\"'][^>]*>"#
        let source = html as NSString
        let markerRanges = matches(markerPattern, in: html).map { $0.range }
        var candidates: [String] = []

        if !markerRanges.isEmpty {
            for (index, marker) in markerRanges.enumerated() {
                let nextStart = index + 1 < markerRanges.count ? markerRanges[index + 1].location : source.length
                let length = min(max(0, nextStart - marker.location), 14_000)
                if length > 0 { candidates.append(source.substring(with: NSRange(location: marker.location, length: length))) }
            }
        } else {
            for match in matches(#"(?is)<a\b[^>]*href=[\"'][^\"']+[\"'][^>]*>.*?</a>"#, in: html) {
                candidates.append(substring(html, range: match.range))
            }
        }

        var result: [Anime] = []
        var seen = Set<String>()
        for block in candidates {
            guard let href = first(#"(?is)href\s*=\s*[\"']([^\"']+)[\"']"#, in: block),
                  let pageURL = absoluteURL(href, relativeTo: baseURL) else { continue }
            let lowerPath = pageURL.path.lowercased()
            guard lowerPath.contains("phim") || lowerPath.hasSuffix(".html") else { continue }

            let imageValue = imageSource(in: block)
            let titleValue = first(#"(?is)<h2[^>]*class=[\"'][^\"']*Title[^\"']*[\"'][^>]*>(.*?)</h2>"#, in: block)
                ?? first(#"(?is)<div[^>]*class=[\"'][^\"']*Title[^\"']*[\"'][^>]*>(.*?)</div>"#, in: block)
                ?? first(#"(?is)(?:alt|title)\s*=\s*[\"']([^\"']+)[\"']"#, in: block)
            guard let rawTitle = titleValue else { continue }
            let title = cleanText(rawTitle)
            guard title.count > 1, seen.insert(pageURL.absoluteString).inserted else { continue }

            let episode = first(#"(?is)<span[^>]*class=[\"'][^\"']*mli-eps[^\"']*[\"'][^>]*>(.*?)</span>"#, in: block).map(cleanText) ?? ""
            let quality = first(#"(?is)<span[^>]*class=[\"'][^\"']*mli-quality[^\"']*[\"'][^>]*>(.*?)</span>"#, in: block).map(cleanText) ?? ""
            let score = first(#"(?is)fa-star[^>]*></i>\s*([0-9.]+)"#, in: block).map(cleanText) ?? ""
            result.append(Anime(
                title: title,
                url: pageURL,
                imageURL: imageValue.flatMap { absoluteURL($0, relativeTo: baseURL) },
                episodeText: episode,
                quality: quality,
                score: score
            ))
        }
        return result
    }

    static func detail(from html: String, anime: Anime, baseURL: URL) -> AnimeDetail {
        let title = first(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html).map(cleanText) ?? anime.title
        let bannerValue = first(#"(?is)<meta\s+(?:property=[\"']og:image[\"']|itemprop=[\"']image[\"'])\s+content=[\"']([^\"']*banner[^\"']*)[\"']"#, in: html)
        let posterValue = first(#"(?is)<meta\s+(?:property=[\"']og:image[\"']|itemprop=[\"']image[\"'])\s+content=[\"']([^\"']+)[\"']"#, in: html)
        let description = first(#"(?is)<div[^>]*class=[\"'][^\"']*Description[^\"']*[\"'][^>]*>(.*?)</div>"#, in: html)
            .map(cleanText) ?? "Chưa có nội dung giới thiệu."
        let info = first(#"(?is)<div[^>]*class=[\"'][^\"']*(?:Info|film-info)[^\"']*[\"'][^>]*>(.*?)</div>"#, in: html)
            .map(cleanText) ?? ""

        var episodes: [Episode] = []
        var seen = Set<String>()
        for match in matches(#"(?is)<a\b([^>]*)>(.*?)</a>"#, in: html) {
            guard match.numberOfRanges > 2 else { continue }
            let attributes = substring(html, range: match.range(at: 1))
            let body = substring(html, range: match.range(at: 2))
            guard let href = first(#"(?is)href\s*=\s*[\"']([^\"']+)[\"']"#, in: attributes),
                  let url = absoluteURL(href, relativeTo: baseURL) else { continue }
            let lower = (attributes + " " + href).lowercased()
            guard lower.contains("btn-episode") || lower.contains("xem-phim") || lower.range(of: #"/(?:tap|ep)-?\d+"#, options: .regularExpression) != nil else { continue }

            let rawTitle = cleanText(body)
            let numberText = first(#"(?i)(?:tập|tap|ep)[^0-9]*([0-9]+)"#, in: rawTitle + " " + href)
            let number = numberText.flatMap(Int.init)
            let episodeTitle = rawTitle.isEmpty ? number.map { "Tập \($0)" } ?? "Xem phim" : rawTitle
            let season = first(#"(?is)data-(?:season|season-id)\s*=\s*[\"']([^\"']+)[\"']"#, in: attributes).map(cleanText) ?? "Phần 1"
            let key = url.absoluteString + episodeTitle
            if seen.insert(key).inserted {
                episodes.append(Episode(title: episodeTitle, url: url, number: number, season: season))
            }
        }

        episodes.sort {
            if let left = $0.number, let right = $1.number, left != right { return left < right }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return AnimeDetail(
            title: title,
            posterURL: posterValue.flatMap { absoluteURL($0, relativeTo: baseURL) } ?? anime.imageURL,
            bannerURL: bannerValue.flatMap { absoluteURL($0, relativeTo: baseURL) },
            summary: description,
            info: info,
            episodes: episodes
        )
    }

    static func containsVerification(_ html: String) -> Bool {
        let value = html.lowercased()
        // A normal page can contain Cloudflare scripts without asking for verification.
        let title = first(#"(?is)<title[^>]*>(.*?)</title>"#, in: value) ?? ""
        let challengeTitle = ["just a moment", "xác minh an toàn", "xác minh bảo mật", "attention required", "verify you are human", "checking your browser"].contains { title.contains($0) }
        let hasContent = value.range(of: #"class=["'][^"']*(?:tpost|ml-item|film-item|movie-item|btn-episode)[^"']*["']"#, options: .regularExpression) != nil
            || value.contains("filminfo.filmid")
        if hasContent && !challengeTitle { return false }
        return challengeTitle || value.contains("id=\"challenge-form\"") || value.contains("id='challenge-form'")
            || value.contains("cf-turnstile") || value.contains("g-recaptcha") || value.contains("h-captcha")
    }

    static func imageSource(in html: String) -> String? {
        guard let tag = first(#"(?is)(<img\b[^>]*>)"#, in: html) else { return nil }
        for attribute in ["data-original", "data-src", "data-lazy-src", "data-lazy", "src"] {
            if let value = first("(?is)(?:^|\\s)" + attribute + #"\s*=\s*["']([^"']+)["']"#, in: tag),
               !value.isEmpty, !value.lowercased().hasPrefix("data:"), !value.lowercased().contains("blank.gif") {
                return value
            }
        }
        if let srcset = first(#"(?is)(?:data-srcset|srcset)\s*=\s*["']([^"']+)["']"#, in: tag) {
            return srcset.split(separator: ",").last?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        }
        return nil
    }

    static func playerParameters(from html: String) -> (filmID: String, hash: String)? {
        guard let filmID = first(#"filmInfo\.filmID\s*=\s*parseInt\(['\"](\d+)['\"]\)"#, in: html) else { return nil }
        let hash = first(#"AnimeVsub\(['\"]([^'\"]+)['\"]"#, in: html)
            ?? first(#"class=[\"'][^\"']*active[^\"']*[\"'][^>]*data-hash=[\"']([^\"']+)[\"']"#, in: html)
            ?? first(#"data-hash=[\"']([^\"']+)[\"']"#, in: html)
        guard let hash, !hash.isEmpty else { return nil }
        return (filmID, hash)
    }

    private static func uniqueSections(_ sections: [AnimeSection]) -> [AnimeSection] {
        var names = Set<String>()
        var itemSets = Set<Set<String>>()
        return sections.filter { section in
            let title = section.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
            let key = title.contains("cap nhat") ? "latest-updates" : title
            return !section.items.isEmpty && names.insert(key).inserted && itemSets.insert(Set(section.items.map(\.id))).inserted
        }
    }

    private static func absoluteURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        guard !decoded.hasPrefix("javascript:"), !decoded.hasPrefix("data:") else { return nil }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#x27;": "'",
            "&#39;": "'", "&lt;": "<", "&gt;": ">"
        ]
        for (entity, replacement) in entities { text = text.replacingOccurrences(of: entity, with: replacement) }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let match = matches(pattern, in: text).first, match.numberOfRanges > 1 else { return nil }
        return substring(text, range: match.range(at: 1))
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func substring(_ text: String, range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        return (text as NSString).substring(with: range)
    }
}
