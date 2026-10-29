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

    static func detail(from html: String, anime: Anime, baseURL: URL, includeEpisodes: Bool = true) -> AnimeDetail {
        let title = first(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html).map(cleanText) ?? anime.title
        let bannerValue = first(#"(?is)<meta\s+(?:property=[\"']og:image[\"']|itemprop=[\"']image[\"'])\s+content=[\"']([^\"']*banner[^\"']*)[\"']"#, in: html)
        let posterValue = first(#"(?is)<meta\s+(?:property=[\"']og:image[\"']|itemprop=[\"']image[\"'])\s+content=[\"']([^\"']+)[\"']"#, in: html)
        let description = first(#"(?is)<div[^>]*class=[\"'][^\"']*Description[^\"']*[\"'][^>]*>(.*?)</div>"#, in: html)
            .map(cleanText) ?? "Chưa có nội dung giới thiệu."
        let info = first(#"(?is)<div[^>]*class=[\"'][^\"']*(?:Info|film-info)[^\"']*[\"'][^>]*>(.*?)</div>"#, in: html)
            .map(cleanText) ?? ""

        if !includeEpisodes {
            return AnimeDetail(title: title, posterURL: posterValue.flatMap { absoluteURL($0, relativeTo: baseURL) } ?? anime.imageURL,
                               bannerURL: bannerValue.flatMap { absoluteURL($0, relativeTo: baseURL) },
                               summary: description, info: info, episodes: [])
        }
        let identityURL = canonicalAnimeURL(from: html, fallback: anime.url, baseURL: baseURL)
        var episodes: [Episode] = []
        var seen = Set<String>()
        var candidateCount = 0
        var rejectedCount = 0

        for link in HTMLDocument.links(html) {
            guard !link.excluded, let href = link.attributes["href"],
                  let url = episodeURL(href, animeURL: identityURL, baseURL: baseURL) else { continue }
            candidateCount += 1
            let rawTitle = link.text.isEmpty ? (link.attributes["title"] ?? link.attributes["data-episode"] ?? "") : link.text
            let episodeLabel = rawTitle.range(of: #"(?i)^(?:(?:tập|tap|ep(?:isode)?)[ .:_-]*)?[0-9]+(?:[.,][0-9]+)?(?:[ ._-]*(?:end|cuối|final|vietsub|thuyết minh|thuyet minh|raw|lồng tiếng|long tieng|full|hd|[a-zA-Z0-9 -]+))?$|^(?:ova|ona|sp|special|tập đặc biệt|tap dac biet|movie|full|trọn bộ|trailer)(?:[ .:_-]*[0-9]+)?$"#, options: .regularExpression) != nil
            let button = link.marker.split(whereSeparator: \.isWhitespace).contains("btn-episode")
            let episodeContainer = link.ancestors.contains {
                $0.marker.range(of: #"(?:list-episode|episode-list|episodes|server-list|list-server|episodios|halim-list-eps)"#, options: .regularExpression) != nil
            }
            let hash = !(link.attributes["data-hash"] ?? "").isEmpty && !(link.attributes["data-hash"]?.lowercased().contains("user") ?? false)

            // A watch URL in a login redirect or a comment permalink is not an episode.
            // The observed Next.js site uses /xem-phim/<show>/tap-N links in
            // its episode grid without legacy btn-episode class names.
            let modernRoute = url.path.hasPrefix("/xem-phim/") && url.pathComponents.count >= 4
            let identifiedEpisode = button || episodeContainer
            guard (episodeLabel || (identifiedEpisode && !rawTitle.isEmpty)), identifiedEpisode || hash || modernRoute else {
                rejectedCount += 1
                continue
            }

            let numberText = first(#"(?i)^(?:(?:tập|tap|ep(?:isode)?)[ .:_-]*)?([0-9]+)"#, in: rawTitle)
            let number = numberText.flatMap(Int.init)
            let names = ["data-server", "data-server-name", "data-season", "data-season-id"]
            let ownServer = names.compactMap { link.attributes[$0] }.first
            let parentServer = link.ancestors.reversed().compactMap { ancestor in
                names.compactMap { ancestor.attributes[$0] }.first
            }.first
            let season = ownServer ?? parentServer ?? "Vietsub"
            let key = url.absoluteString + "|" + season
            if seen.insert(key).inserted {
                episodes.append(Episode(title: rawTitle, url: url, number: number, season: season))
            }
        }

        // Decode the site's streamed episode array only when the DOM itself
        // demonstrates the same show slug and the /xem-phim/<slug>/tap-N route.
        let existingURLs = Set(episodes.map { $0.url.absoluteString })
        let modern = streamedEpisodes(from: html, animeURL: identityURL, baseURL: baseURL, known: existingURLs)
        episodes.append(contentsOf: modern)

        #if DEBUG
        print("[Anime] episode_candidates=\(candidateCount) accepted=\(episodes.count) rejected=\(rejectedCount)")
        #endif

        if episodes.contains(where: { $0.number != nil }) {
            episodes.removeAll { $0.number == nil && ["xem phim", "xem ngay", "watch now"].contains($0.title.lowercased()) }
        }
        episodes.sort {
            if let left = $0.number, let right = $1.number, left != right { return left < right }
            if ($0.number != nil) != ($1.number != nil) { return $0.number != nil }
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

    static func hasCompleteStreamedEpisodes(_ html: String, episodes: [Episode]) -> Bool {
        guard html.contains("animeSlugOrId"),
              let declared = first(#"(?i)\"numberOfEpisodes\"\s*:\s*([0-9]+)"#, in: html).flatMap(Int.init), declared > 0 else { return false }
        return Set(episodes.compactMap(\.number)).count >= declared
    }

    static func watchURL(from html: String, baseURL: URL, animeURL: URL? = nil) -> URL? {
        let identity = animeURL.map { canonicalAnimeURL(from: html, fallback: $0, baseURL: baseURL) }
        var episodeCandidates: [(Int, URL)] = []
        for link in HTMLDocument.links(html) where !link.excluded {
            guard let href = link.attributes["href"], !href.hasPrefix("#"), !href.hasPrefix("?") else { continue }
            let url: URL
            if let identity {
                guard let candidate = episodeURL(href, animeURL: identity, baseURL: baseURL) else { continue }
                url = candidate
            } else {
                guard let candidate = absoluteURL(href, relativeTo: baseURL), candidate.host == baseURL.host,
                      candidate.path.range(of: #"(?i)/(?:xem-phim|tap-[0-9]+|ep-[0-9]+)(?:-[0-9a-zA-Z_]+)?(?:\.html)?/?$"#, options: .regularExpression) != nil else { continue }
                url = candidate
            }
            let label = link.text.lowercased()
            if ["xem phim", "xem ngay", "watch now"].contains(label) || link.marker.contains("watch-now") || link.marker.contains("watch-btn") {
                return url
            }
            if link.marker.split(whereSeparator: \.isWhitespace).contains("btn-episode") || link.ancestors.contains(where: { $0.marker.contains("list-episode") || $0.marker.contains("list-server") }) {
                let number = first(#"(?i)^(?:(?:tập|tap|ep)[ .:_-]*)?([0-9]+)"#, in: link.text).flatMap(Int.init) ?? Int.max
                episodeCandidates.append((number, url))
            }
        }
        return episodeCandidates.min { $0.0 < $1.0 }?.1
    }

    /// Canonical aliases may rename a slug while retaining the source's stable
    /// anime ID. Never accept a canonical link pointing to another anime ID.
    private static func canonicalAnimeURL(from html: String, fallback: URL, baseURL: URL) -> URL {
        func slug(_ url: URL) -> String {
            let parts = url.pathComponents.filter { $0 != "/" }
            return (parts.count > 1 ? parts[1] : url.lastPathComponent).replacingOccurrences(of: #"(?i)\.html$"#, with: "", options: .regularExpression)
        }
        let original = slug(fallback)
        for match in matches(#"(?is)<link\b[^>]*>"#, in: html) {
            let attrs = HTMLDocument.attributes(substring(html, range: match.range))
            guard attrs["rel"]?.lowercased() == "canonical", let href = attrs["href"],
                  let url = absoluteURL(href, relativeTo: baseURL), url.host == baseURL.host, url.path.hasPrefix("/phim/") else { continue }
            let candidate = slug(url)
            if candidate == original { return url }
            let oldID = first(#"(?i)(?:^|-)a([0-9]+)$"#, in: original)
            let newID = first(#"(?i)(?:^|-)a([0-9]+)$"#, in: candidate)
            if let oldID, oldID == newID { return url }
        }
        return fallback
    }

    static func episodeURL(_ href: String, animeURL: URL, baseURL: URL) -> URL? {
        let cleanHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHref.isEmpty, !cleanHref.hasPrefix("#"), !cleanHref.hasPrefix("?"),
              !cleanHref.hasPrefix("javascript:"), !cleanHref.hasPrefix("data:") else { return nil }
        let hrefWithoutFragment = cleanHref.split(separator: "#").first.map(String.init) ?? cleanHref
        guard let candidate = absoluteURL(hrefWithoutFragment, relativeTo: baseURL),
              ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") else { return nil }
        let url = rebasedAnimeURL(candidate, baseURL: baseURL)
        guard url.host == baseURL.host else { return nil }

        let showComponents = animeURL.pathComponents.filter { $0 != "/" }
        let rawShowSlug: String
        if showComponents.count >= 2 && ["phim", "xem-phim"].contains(showComponents[0].lowercased()) {
            rawShowSlug = showComponents[1]
        } else if let last = showComponents.last { rawShowSlug = last }
        else { return nil }
        let showSlug = rawShowSlug.replacingOccurrences(of: #"(?i)\.html$"#, with: "", options: .regularExpression)
        guard !showSlug.isEmpty else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else { return nil }
        let normalizedPath = pathComponents.map {
            $0.replacingOccurrences(of: #"(?i)\.html$"#, with: "", options: .regularExpression)
        }
        let normalizedShow = showComponents.map {
            $0.replacingOccurrences(of: #"(?i)\.html$"#, with: "", options: .regularExpression)
        }

        let matchesShow: Bool
        if normalizedPath.count >= 3 && normalizedPath[0].lowercased() == "xem-phim" && normalizedPath[1] == showSlug {
            matchesShow = true
        } else if normalizedPath.count >= 2 && normalizedShow.count >= 2 && Array(normalizedShow.prefix(2)) == Array(normalizedPath.prefix(2)) {
            matchesShow = true
        } else if normalizedPath.contains(showSlug) {
            matchesShow = true
        } else if url.path.contains("/" + showSlug + "/") || url.path.contains("/" + showSlug + "-") || url.path.contains("/" + showSlug + ".html") {
            matchesShow = true
        } else {
            matchesShow = false
        }
        guard matchesShow else { return nil }

        let last = url.lastPathComponent.lowercased()
        let isEpisodePath = last.range(of: #"(?i)^(?:xem-phim(?:-[0-9a-zA-Z_]+)?|(?:tap|ep)-?[0-9]+(?:[.-][0-9a-zA-Z_]+)*|(?:ova|ona|sp|special|movie|full|trailer)(?:-[0-9a-zA-Z_]+)?)(?:\.html)?$"#, options: .regularExpression) != nil
            || url.path.lowercased().contains("/xem-phim")
            || last.contains("tap-") || last.contains("ep-")
        guard isEpisodePath else { return nil }
        return url
    }

    /// Read React's serialized episode list; links are generated only from rows
    /// for a slug whose link pattern is already present in the HTML DOM.
    private static func streamedEpisodes(from html: String, animeURL: URL, baseURL: URL, known: Set<String>) -> [Episode] {
        let paths = animeURL.pathComponents.filter { $0 != "/" }
        guard paths.count >= 2, ["phim", "xem-phim"].contains(paths[0].lowercased()) else { return [] }
        let slug = paths[1].replacingOccurrences(of: #"(?i)\.html$"#, with: "", options: .regularExpression)
        let prefix = "/xem-phim/" + slug + "/tap-"
        guard HTMLDocument.links(html).contains(where: { !$0.excluded && ($0.attributes["href"] ?? "").hasPrefix(prefix) }) else { return [] }
        let text = streamedPayload(from: html)
        guard let object = streamedObjects(text, key: "animeSlugOrId", maxObjectBytes: 8_000_000).first(where: {
            $0["animeSlugOrId"] as? String == slug && $0["episodes"] is [[String: Any]]
        }), let rows = object["episodes"] as? [[String: Any]] else { return [] }
        var seen = known
        return rows.compactMap { row in
            guard let number = row["number"] as? Int, number > 0, number <= 100_000,
                  let id = row["episodeId"] as? String, !id.isEmpty,
                  let url = URL(string: prefix + String(number), relativeTo: baseURL)?.absoluteURL,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return Episode(title: "Tập " + String(number), url: url, number: number, season: "Vietsub")
        }
    }

    private static func streamedPayload(from html: String) -> String {
        let pattern = #"self\.__next_f\.push\(\s*\[1\s*,\s*("(?:\\.|[^"\\])*")\s*\]\s*\)"#
        var chunks: [String] = []
        for match in matches(pattern, in: html) where match.numberOfRanges > 1 {
            let json = "[" + substring(html, range: match.range(at: 1)) + "]"
            if let data = json.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String], let chunk = values.first {
                chunks.append(chunk)
            }
        }
        return chunks.joined()
    }

    static func schedule(from html: String, baseURL: URL) -> [DayOfWeek: [AnimeScheduleItem]] {
        var result: [DayOfWeek: [AnimeScheduleItem]] = [:]
        for day in DayOfWeek.allCases { result[day] = [] }
        var seenIDs = Set<String>()

        let payload = streamedPayload(from: html)
        // Each item is a JSON object, including in the streamed React payload.
        // Missing optional values stay empty; unknown weekdays are not guessed.
        for row in streamedObjects(payload, key: "pubTimeFormat") {
            func field(_ key: String) -> String {
                if let value = row[key] as? String { return value }
                if let number = row[key] as? NSNumber { return number.stringValue }
                return ""
            }
            let id = field("id"), slug = field("slug"), title = field("title")
            let pubTime = field("pubTimeFormat"), airTime = field("airTime")
            let latest = field("latestEpisode"), status = field("status")
            guard !id.isEmpty, !slug.isEmpty, !title.isEmpty,
                  let day = parseDayOfWeek(from: pubTime), seenIDs.insert(id + "|" + pubTime).inserted else { continue }
            let animePath = slug.hasPrefix("/") ? slug : "/phim/" + slug
            guard let pageURL = absoluteURL(animePath, relativeTo: baseURL), pageURL.host == baseURL.host else { continue }
            let cover = field("coverUrl")
            let anime = Anime(title: title, url: pageURL, imageURL: cover.isEmpty ? nil : absoluteURL(cover, relativeTo: baseURL),
                              episodeText: latest, quality: "", score: "")
            result[day, default: []].append(AnimeScheduleItem(id: id, anime: anime, airTime: airTime, pubTimeFormat: pubTime,
                                                               expectedEpisode: latest, statusText: status, dayOfWeek: day))
        }

        // AnimeVietsub's legacy schedule groups cards below weekday headings.
        // Read actual /phim/ anchors only; the date heading is not an episode.
        if result.values.allSatisfy({ $0.isEmpty }) {
            let headingPattern = #"(?is)<h[1-6]\b[^>]*>(.*?)</h[1-6]\s*>"#
            let headings = matches(headingPattern, in: html).compactMap { match -> (NSTextCheckingResult, DayOfWeek)? in
                guard match.numberOfRanges > 1, let day = parseDayOfWeek(from: cleanText(substring(html, range: match.range(at: 1)))) else { return nil }
                return (match, day)
            }
            let source = html as NSString
            for (index, heading) in headings.enumerated() {
                let start = NSMaxRange(heading.0.range)
                let end = index + 1 < headings.count ? headings[index + 1].0.range.location : source.length
                guard end > start else { continue }
                let section = source.substring(with: NSRange(location: start, length: end - start))
                let cards = matches(#"(?is)<li\b[^>]*>.*?</li\s*>"#, in: section)
                for cardMatch in cards {
                    let card = substring(section, range: cardMatch.range)
                    guard let link = HTMLDocument.links(card).first(where: { link in
                        guard !link.excluded, let href = link.attributes["href"],
                              let url = absoluteURL(href, relativeTo: baseURL) else { return false }
                        return url.host == baseURL.host && url.path.hasPrefix("/phim/")
                    }), let href = link.attributes["href"], let url = absoluteURL(href, relativeTo: baseURL) else { continue }
                    let title = link.attributes["title"] ?? first(#"(?is)(?:alt|title)\s*=\s*["']([^"']+)["']"#, in: link.body) ?? link.text
                    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let text = cleanText(card)
                    let hour = first(#"(?i)([0-9]{1,2})\s*giờ\s*[0-9]{1,2}\s*phút"#, in: text)
                    let minute = first(#"(?i)[0-9]{1,2}\s*giờ\s*([0-9]{1,2})\s*phút"#, in: text)
                    let time: String
                    if let hour, let minute, let h = Int(hour), let m = Int(minute), h < 24, m < 60 {
                        time = String(format: "%02d:%02d", h, m)
                    } else { time = first(#"\b([0-9]{1,2}:[0-9]{2})\b"#, in: text) ?? "" }
                    let id = url.path + "|" + String(heading.1.rawValue) + "|" + time
                    guard seenIDs.insert(id).inserted else { continue }
                    let image = imageSource(in: card).flatMap { absoluteURL($0, relativeTo: baseURL) }
                    let anime = Anime(title: cleanText(title), url: url, imageURL: image, episodeText: "", quality: "", score: "")
                    result[heading.1, default: []].append(AnimeScheduleItem(id: id, anime: anime, airTime: time,
                        pubTimeFormat: cleanText(substring(html, range: heading.0.range(at: 1))), expectedEpisode: "", statusText: "", dayOfWeek: heading.1))
                }
            }
        }

        if result.values.allSatisfy({ $0.isEmpty }) {
            let cardPattern = #"(?is)<div[^>]*class=[\"'][^\"']*(?:group relative flex flex-col|schedule-item|item-schedule)[^\"']*[\"'][^>]*>(.*?)</div>\s*</div>"#
            for cardMatch in matches(cardPattern, in: html) {
                let card = substring(html, range: cardMatch.range)
                let time = first(#"(?is)(?:Thứ\s+[2-7]|Thứ\s+[a-zA-Z]+|Chủ\s+Nhật|CN)\s+[0-9]{1,2}:[0-9]{2}"#, in: card) ?? ""
                let status = first(#"(?is)<span[^>]*>(Đã chiếu|Sắp chiếu|Chưa chiếu)</span>"#, in: card) ?? ""
                let href = first(#"(?is)href=[\"']([^\"']+)[\"']"#, in: card) ?? ""
                let title = first(#"(?is)title=[\"']([^\"']+)[\"']"#, in: card).map(cleanText)
                    ?? first(#"(?is)<h[2-4][^>]*>(.*?)</h[2-4]>"#, in: card).map(cleanText) ?? ""
                let cover = imageSource(in: card)
                let ep = first(#"(?is)<span[^>]*>([Tt]ập\s*[0-9]+)</span>"#, in: card) ?? ""

                guard !title.isEmpty, let pageURL = absoluteURL(href, relativeTo: baseURL) else { continue }
                guard let day = parseDayOfWeek(from: time) else { continue }
                let itemID = pageURL.path + "|" + time
                guard seenIDs.insert(itemID).inserted else { continue }

                let anime = Anime(title: title, url: pageURL, imageURL: cover.flatMap { absoluteURL($0, relativeTo: baseURL) },
                                  episodeText: ep, quality: "", score: "")
                let item = AnimeScheduleItem(id: itemID, anime: anime, airTime: time, pubTimeFormat: time, expectedEpisode: ep, statusText: status, dayOfWeek: day)
                result[day, default: []].append(item)
            }
        }

        return result
    }

    /// Decode complete nested JSON objects in streamed data, honoring escaped
    /// quotes and braces inside strings rather than assuming flat key order.
    private static func streamedObjects(_ payload: String, key: String, maxObjectBytes: Int = 65_536) -> [[String: Any]] {
        let bytes = Array(payload.utf8)
        var starts: [Int] = [], objects: [[String: Any]] = []
        var quoted = false, escaped = false
        for (index, byte) in bytes.enumerated() {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 { starts.append(index) }
            else if byte == 125, let start = starts.popLast(), index - start < maxObjectBytes {
                let data = Data(bytes[start...index])
                guard data.range(of: Data(key.utf8)) != nil,
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      object[key] != nil else { continue }
                objects.append(object)
            }
        }
        return objects
    }

    private static func parseDayOfWeek(from text: String) -> DayOfWeek? {
        let t = text.lowercased()
        if t.contains("hai") || t.contains("thứ 2") || t.contains("t2") { return .monday }
        if t.contains("ba") || t.contains("thứ 3") || t.contains("t3") { return .tuesday }
        if t.contains("tư") || t.contains("tu") || t.contains("thứ 4") || t.contains("t4") { return .wednesday }
        if t.contains("năm") || t.contains("nam") || t.contains("thứ 5") || t.contains("t5") { return .thursday }
        if t.contains("sáu") || t.contains("sau") || t.contains("thứ 6") || t.contains("t6") { return .friday }
        if t.contains("bảy") || t.contains("bay") || t.contains("thứ 7") || t.contains("t7") { return .saturday }
        if t.contains("chủ nhật") || t.contains("chu nhat") || t.contains("cn") { return .sunday }
        return nil
    }

    static func mergedEpisodes(_ preview: [Episode], _ full: [Episode]) -> [Episode] {
        var seen = Set<String>()
        // Keep distinct special/server links even when their numeric labels match.
        let combined = (full + preview).filter {
            seen.insert($0.season + "|" + $0.url.absoluteString).inserted
        }
        let numbered = combined.contains { $0.number != nil }
        return combined.filter { !numbered || $0.number != nil || !["xem phim", "xem ngay", "watch now"].contains($0.title.lowercased()) }
            .sorted {
                if $0.season != $1.season { return $0.season.localizedStandardCompare($1.season) == .orderedAscending }
                if let lhs = $0.number, let rhs = $1.number, lhs != rhs { return lhs < rhs }
                if ($0.number != nil) != ($1.number != nil) { return $0.number != nil }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    static func rebasedAnimeURL(_ url: URL, baseURL: URL) -> URL {
        guard AnimeSiteConfiguration.allows(url, baseURL: baseURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        return components.url ?? url
    }

    static func isVerifiedAnimeDetail(_ html: String, url: URL) -> Bool {
        guard url.path.hasPrefix("/phim/"), !containsVerification(html),
              let title = first(#"(?is)<h1\b[^>]*>(.*?)</h1>"#, in: html), !cleanText(title).isEmpty else { return false }
        let lower = html.lowercased()
        return lower.contains("xem phim") || lower.contains("tập") || lower.contains("filminfo.filmid")
    }

    static func containsVerification(_ html: String) -> Bool {
        let value = html.lowercased()
        // A normal page can contain Cloudflare scripts without asking for verification.
        let title = first(#"(?is)<title[^>]*>(.*?)</title>"#, in: value) ?? ""
        let challengeTitle = ["just a moment", "xác minh an toàn", "xác minh bảo mật", "attention required", "verify you are human", "checking your browser"].contains { title.contains($0) }
        let hasContent = value.range(of: #"class=["'][^"']*(?:tpost|ml-item|film-item|movie-item|btn-episode)[^"']*["']"#, options: .regularExpression) != nil
            || value.contains("filminfo.filmid")
            || (value.range(of: #"(?is)<h1\b[^>]*>"#, options: .regularExpression) != nil && value.contains("og:image") && value.contains("xem phim"))
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
