import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS: \(message)")
}

check(!HTMLParser.containsVerification("<title>AnimeVietsub</title><article class='TPost'><h2>Anime</h2></article><script src='/cdn-cgi/challenge-platform/test'></script>"), "Ordinary catalog with Cloudflare script is not a CAPTCHA")
check(!HTMLParser.containsVerification("<title>Xem phim</title><script>filmInfo.filmID = 20;</script><footer>verify you are human</footer>"), "Player content and footer text do not cause verification popup")
check(HTMLParser.containsVerification("<title>Just a moment...</title><form id='challenge-form'></form>"), "Managed challenge is recognized")
check(HTMLParser.containsVerification("<title>Xác Minh An Toàn - AnimeVietsub</title>"), "Vietnamese security page is recognized")
check(HTMLParser.containsVerification("<title>Kiểm tra</title><div class='cf-turnstile'></div>"), "Interactive verification is recognized")
let card = "<article class='TPost'><a href='/phim/example-a1/'><img src='/poster.jpg' alt='Test Anime'></a><h2 class='Title'>Test Anime</h2></article>"
let html = "<section><h2>Mới cập nhật</h2>\(card)</section><section><h2>Anime mới cập nhật</h2>\(card)</section>"
let sections = HTMLParser.sections(from: html, baseURL: URL(string: "https://animevietsub.example")!)
check(sections.count == 1, "Duplicate updated-anime row is removed")
check(sections.first?.items.first?.url.absoluteString == "https://animevietsub.example/phim/example-a1/", "Catalog links resolve on current domain")
print("All parser regressions passed")
check(HTMLParser.imageSource(in: "<img src='data:image/gif;base64,AAA' data-src='/real-poster.jpg'>") == "/real-poster.jpg", "Lazy poster URL takes priority over inline placeholder")
check(HTMLParser.imageSource(in: "<img src='/blank.gif' data-original='https://cdn.example/poster.webp'>") == "https://cdn.example/poster.webp", "Original artwork takes priority over placeholder src")

let filmBase = URL(string: "https://films.example")!
let filmHome = try MovieCatalog.object(Data(#"{"list":[{"slug":"test-series","title":{"en":"Test Series","vi":"Phim thử"},"poster":{"vi":"/poster.jpg"},"mediaType":"tv","epCount":3},{"slug":"test-series","title":"duplicate"}],"genres":["Hành động"]}"#.utf8))
let filmSections = MovieCatalog.filmSections(filmHome, base: filmBase)
check(filmSections.count == 1 && filmSections[0].items.count == 1, "Movie catalog uses JSON and removes duplicate provider IDs")
let film = filmSections[0].items[0]
check(film.title == "Phim thử" && film.source == .film4k, "Vietnamese title and source identity are preserved")
check(film.imageURL?.absoluteString == "https://films.example/poster.jpg", "Movie artwork resolves within its own provider")
let filmDetailJSON = try MovieCatalog.object(Data(#"{"movie":{"slug":"test-series","title":{"vi":"Phim thử"},"mediaType":"tv"},"episodes":[{"season":2,"episode":1,"sources":[{"url":"/two.m3u8"}]},{"season":1,"episode":2,"sources":[{"url":"/one.m3u8"}]}]}"#.utf8))
let filmDetail = try MovieCatalog.filmDetail(filmDetailJSON, anime: film, base: filmBase)
check(filmDetail.episodes.map(\.season) == ["Phần 1", "Phần 2"], "TV seasons are sorted independently of episode numbers")
check(filmDetail.episodes[0].url.query?.contains("s01e02") == true, "Fallback player opens the selected season and episode")
check(MovieCatalog.filmStreams(filmDetailJSON, season: 2, episode: 1).first?["url"] as? String == "/two.m3u8", "Stream selection never substitutes a different season")
check(MovieCatalog.filmStreams(filmDetailJSON, season: 3, episode: 1).isEmpty, "Missing episodes do not silently play another episode")
let movieJSON = try MovieCatalog.object(Data(#"{"movie":{"slug":"movie","title":"Feature Film","mediaType":"movie"},"episodes":[],"playable":true}"#.utf8))
let movieDetail = try MovieCatalog.filmDetail(movieJSON, anime: film, base: filmBase)
check(movieDetail.episodes.count == 1, "Feature films expose a playable entry even when detail omits expiring streams")
let legacyBase = URL(string: "https://legacy.example")!
let legacyJSON = try MovieCatalog.object(Data(#"{"data":{"APP_DOMAIN_CDN_IMAGE":"https://img.example","items":[{"slug":"sample","name":"Legacy film","poster_url":"uploads/poster.jpg","thumb_url":"uploads/thumb.jpg","year":2026,"quality":"4K","lang":"Vietsub"}]}}"#.utf8))
let legacy = MovieCatalog.legacyItems(legacyJSON, base: legacyBase, format: .free1)[0]
check(legacy.source == .phim4k && legacy.imageURL?.absoluteString == "https://img.example/uploads/poster.jpg", "Phim4K retains separate provider and image CDN even without trailing slash")
check(legacy.bannerURL?.absoluteString == "https://img.example/uploads/thumb.jpg", "Phim4K populates horizontal bannerURL for Featured Hero Carousel")
check(Phim4KFormat.free1.homeSectionsConfig.map(\.title) == ["Mới cập nhật", "Drama xứ Hàn", "Drama tàu", "Phim Việt", "Hoạt hình", "Phim lẻ mới nhất", "Phim Bộ mới nhất"], "Nguồn phim 2 provides all 6 requested category rows plus Mới cập nhật")
check(Phim4KFormat.free1.defaultCategories.count > 20, "Nguồn phim 2 provides full genre and country browsing list")
let legacyDetail = try MovieCatalog.object(Data(#"{"movie":{"name":"Legacy film"},"episodes":[{"server_name":"Vietsub","server_data":[{"name":"01","link_m3u8":"https://media.example/a.m3u8","link_embed":"https://embed.example/a"}]}]}"#.utf8))
let free1Detail = try MovieCatalog.legacyDetail(legacyDetail, anime: legacy)
check(free1Detail.episodes.first?.source == .phim4k, "Free1 detail maps episodes to the Phim4K resolver")
let free2 = try MovieCatalog.object(Data(#"{"movie":{"name":"Legacy film","episodes":[{"server_name":"Server A","items":[{"name":"01","embed":"https://embed.example/b"}]}]}}"#.utf8))
let free2Detail = try MovieCatalog.legacyDetail(free2, anime: legacy)
check(free2Detail.episodes.count == 1, "Free2 nested episodes and embed links are supported")
let runtimeDetail = try MovieCatalog.object(Data(#"{"movie":{"name":"Runtime movie"},"episodes":[{"server_name":"Vietsub","server_data":[{"name":"01","link":"https://stream.example/api/content/stream/hls?movie=test&server=Vietsub&slug=01"}]},{"server_name":"Lồng tiếng","server_data":[{"name":"01","link":"https://stream.example/api/content/stream/hls?movie=test&server=Dub&slug=01"}]}]}"#.utf8))
let runtimeEpisodes = try MovieCatalog.legacyDetail(runtimeDetail, anime: legacy).episodes
check(runtimeEpisodes.count == 2 && runtimeEpisodes[0].season != runtimeEpisodes[1].season, "Runtime API link fields preserve separate subtitled/dubbed servers")
check(MovieCatalog.legacyStream(["link":"https://stream.example/api/content/stream/hls?movie=test"], base: legacyBase)?.web == false, "Extensionless HLS resolver links use native playback rather than a website")
check(MovieCatalog.url("javascript:alert(1)", base: filmBase) == nil, "Provider metadata cannot become executable URL schemes")
var otherSource = film
otherSource.source = .phim4k
check(film.id != otherSource.id, "The same path in different sources has a different catalog identity")
check(MovieCatalog.rating(8.300000000000001) == "8.3", "Movie ratings do not expose floating-point precision artifacts")

let pngEnvelope = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==")!
let media = Data([0, 0, 0, 24]) + Data("ftypisom".utf8)
check(FilmMediaTransform.unwrap(pngEnvelope + media) == media, "Complete PNG envelope is removed without altering video bytes")
check(FilmMediaTransform.unwrap(media) == media, "Unwrapped media passes through unchanged")
check(FilmMediaTransform.unwrap(pngEnvelope) == pngEnvelope, "An ordinary PNG without appended media is not treated as video")
check(FilmMediaTransform.unwrap(Data(pngEnvelope.prefix(25))) == Data(pngEnvelope.prefix(25)), "Truncated PNG chunks never cause an out-of-bounds read")
let playlist = "#EXTM3U\n#EXT-X-MAP:URI=\"init.png\"\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"/a.m3u8\"\nsegment.png\n"
let rewritten = FilmMediaTransform.playlist(playlist, base: URL(string: "https://films.example/hls/master.m3u8")!) { url in
    URL(string: "http://127.0.0.1:1234/" + url.lastPathComponent)!
}
check(rewritten.contains("URI=\"http://127.0.0.1:1234/init.png\"") && rewritten.contains("\nhttp://127.0.0.1:1234/segment.png"), "HLS init, track and segment URLs are routed through the local adapter")
check(FilmMediaTransform.byteRange("bytes=0-1", count: 100) == 0..<2, "AVPlayer's initial two-byte probe is supported")
check(FilmMediaTransform.byteRange("bytes=-10", count: 100) == 90..<100, "Suffix byte ranges use normalized media size")
check(FilmMediaTransform.byteRange("bytes=100-", count: 100) == nil, "Unsatisfiable byte ranges are rejected")
let qualityManifest = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,CODECS=\"avc1,mp4a\"\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4200000,RESOLUTION=1920x1080\nb.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nc.m3u8"
let qualities = FilmMediaTransform.qualities(qualityManifest)
check(qualities.map(\.title) == ["Tự động", "1080p", "720p"], "Quality choices come from actual HLS variants and deduplicate audio/codec variants")
check(qualities[1].bandwidth == 4200000, "A resolution limit preserves the available codec/audio alternatives")
check(FilmMediaTransform.qualities("#EXTM3U\n#EXTINF:8,\nsegment.ts").count == 1, "Media playlists do not fabricate unsupported resolutions")

let animeBase = URL(string: "https://animevietsub.example")!
let animeFixture = Anime(title: "Long series", url: animeBase.appendingPathComponent("phim/series-a1/"), imageURL: nil, episodeText: "", quality: "", score: "")
let previewHTML = "<a href='/phim/series-a1/xem-phim.html'>Xem phim</a>" + (1198...1200).map { "<a class='btn-episode' href='/phim/series-a1/tap-\($0).html'>\($0)</a>" }.joined()
let fullHTML = (1...1200).reversed().map { "<a class='btn-episode' href='/phim/series-a1/tap-\($0).html'>\($0)</a>" }.joined()
let previewEpisodes = HTMLParser.detail(from: previewHTML, anime: animeFixture, baseURL: animeBase).episodes
let allEpisodes = HTMLParser.detail(from: fullHTML, anime: animeFixture, baseURL: animeBase).episodes
let merged = HTMLParser.mergedEpisodes(previewEpisodes, allEpisodes)
check(merged.count == 1200 && merged.first?.number == 1 && merged.last?.number == 1200, "All 1200 anime episodes survive preview merge and sort numerically")
check(HTMLParser.watchURL(from: previewHTML, baseURL: animeBase)?.path == "/phim/series-a1/xem-phim.html", "Detail page resolves its full watch page")
check(HTMLParser.rebasedAnimeURL(URL(string: "https://animevietsub.old/phim/test/tap-2.html?q=1")!, baseURL: animeBase).absoluteString == "https://animevietsub.example/phim/test/tap-2.html?q=1", "Anime domain recovery preserves episode path and query")
let numericHTML = "<a class='btn-episode' href='/phim/series-a1/xem-phim-99999.html'>12</a>"
check(HTMLParser.detail(from: numericHTML, anime: animeFixture, baseURL: animeBase).episodes.first?.number == 12, "Numeric label is used instead of an opaque watch-page ID")
let sourceRows: MovieCatalog.Object = ["items": [["slug": "same-title", "name": "Same title", "language": "Vietsub"]]]
let nguoncItems = MovieCatalog.legacyItems(sourceRows, base: URL(string: "https://phim.nguonc.com")!, format: .free2, source: .film4k)
let kkItems = MovieCatalog.legacyItems(sourceRows, base: URL(string: "https://phimapi.com")!, format: .free1, source: .kkphim)
check(nguoncItems[0].source == .film4k && nguoncItems[0].url.path == "/api/film/same-title", "Source 1 routes to NguonC detail API")
check(kkItems[0].source == .kkphim && kkItems[0].url.path == "/phim/same-title", "Source 3 routes to KKPhim detail API")
check(Set([nguoncItems[0].id, kkItems[0].id]).count == 2, "Same movie slug remains isolated across providers")
let nguoncDetail: MovieCatalog.Object = ["movie": ["name": "Same title", "episodes": [["server_name": "Vietsub", "items": [["name": "1", "embed": "https://player.example/1"], ["name": "2", "m3u8": "https://cdn.example/2.m3u8"]]]]]]
let parsedNguonc = try MovieCatalog.legacyDetail(nguoncDetail, anime: nguoncItems[0])
check(parsedNguonc.episodes.count == 2 && parsedNguonc.episodes.allSatisfy { $0.source == .film4k }, "NguonC nested episode servers preserve source identity")
let parsedKK = try MovieCatalog.legacyDetail(nguoncDetail, anime: kkItems[0])
check(parsedKK.episodes.allSatisfy { $0.source == .kkphim }, "KKPhim episodes never use source 2 identity")

let coreBase = URL(string: "https://api.phim4k.example")!
let coreRow: MovieCatalog.Object = ["videos_id": "14973", "title": "Avatar (2009)", "is_tvseries": "0", "video_quality": "4K", "slug": "avatar"]
let coreMovie = Phim4KCatalog.items([coreRow], base: coreBase)[0]
check(coreMovie.source == .phim4k && coreMovie.url.query == "type=movie&id=14973", "Phim4K Core uses stable app IDs, not a KKPhim slug search")
let coreJSON: MovieCatalog.Object = ["videos_id": "14973", "title": "Avatar (2009)", "videos": [
    ["video_file_id": "a", "label": "2160P REMUX HDR MKV", "file_type": "mkv", "file_url": "https://cdn.phim4k.lol/original-a"],
    ["video_file_id": "b", "label": "1080P MKV", "file_type": "mkv", "file_url": "https://cdn.phim4k.lol/original-b"]
]]
let coreEpisodes = try Phim4KCatalog.detail(coreJSON, anime: coreMovie).episodes
check(coreEpisodes.count == 2, "All original Phim4K 4K and MKV servers are retained")
check(coreEpisodes[0].qualityBadge.contains("4K") && coreEpisodes[0].season.contains("REMUX"), "Original Phim4K server labels retain 4K/Remux distinctions")
check(Phim4KCatalog.stream(coreJSON, seasonID: nil, episodeID: "a", base: coreBase)?.url.absoluteString == "https://cdn.phim4k.lol/original-a", "VIP entries resolve the actual app link, never a relabelled Free1 fallback")
check(Phim4KCatalog.stream(coreJSON, seasonID: nil, episodeID: "missing", base: coreBase) == nil, "Missing VIP server does not fall back to another server")
let coreSeries: MovieCatalog.Object = ["season": [
    ["seasons_id": "10", "seasons_name": "Season 1 4K", "episodes": [["episodes_id": "101", "episodes_name": "01.mkv", "file_url": "https://media.example/one.mkv"]]],
    ["seasons_id": "20", "seasons_name": "Season 2 4K", "episodes": [["episodes_id": "201", "episodes_name": "01.mkv", "file_url": "https://media.example/two.mkv"]]]
]]
check(Phim4KCatalog.episodes(coreSeries, detailURL: coreMovie.url).count == 2, "Phim4K series keep every season and its original episode links")
check(Phim4KCatalog.stream(coreSeries, seasonID: "20", episodeID: "201", base: coreBase)?.url.lastPathComponent == "two.mkv", "Core playback matches season and episode IDs instead of positional indexes")
check(Phim4KCatalog.stream(coreSeries, seasonID: "10", episodeID: "201", base: coreBase) == nil, "Core resolver cannot cross seasons")
let coreCats = Phim4KCatalog.categories(["all_genre": [["genre_id": "45", "name": "Hot"]], "all_country": [["country_id": "1", "name": "Hoa Kỳ"]]])
check(coreCats.map(\.path).contains("core/genre/45") && coreCats.map(\.path).contains("core/country/1"), "Phim4K categories come from the app's own genre and country IDs")
let coreGenreRoute = try Phim4KCatalog.listRoute("core/genre/45", base: coreBase, page: 2)
check(coreGenreRoute.path == "/rest-api/v130/content_by_genre_id" && coreGenreRoute.query == "page=2&id=45", "Core category requests use the original app endpoint and pagination")
check(!MovieCatalog.isCatalogPath("api/films/the-loai/hanh-dong", format: .free1), "KKPhim rejects NguonC category routes")
check(!MovieCatalog.isCatalogPath("v1/api/the-loai/hanh-dong", format: .free2), "NguonC rejects KKPhim category routes")
check(!MovieCatalog.isCatalogPath("https://other.example/v1/api/danh-sach/phim-bo", format: .free1), "Absolute foreign catalog routes are rejected")
check(MovieCatalog.legacyStream(["link_m3u8": "https://cdn.example/movie.m3u8", "link_embed": "https://player.example/preroll"], base: coreBase)?.url.host == "cdn.example", "Explicit movie HLS is preferred over an advertising web embed")
check(MovieCatalog.legacyStream(["link": "https://player.example/embed/one"], base: coreBase)?.web == true, "Opaque player links are not mistaken for native media")
let suite = "AnPinime.tests." + UUID().uuidString
let historyDefaults = UserDefaults(suiteName: suite)!
let history = SearchHistory(defaults: historyDefaults)
history.record("  Avatar  ", source: .phim4k)
history.record("avatar", source: .phim4k)
history.record("Anime riêng", source: .anime)
check(history.queries(for: .phim4k) == ["avatar"], "Search history trims and deduplicates completed searches")
check(history.queries(for: .film4k).isEmpty && history.queries(for: .kkphim).isEmpty, "Search history never leaks across providers")
check(SearchHistory(defaults: historyDefaults).queries(for: .anime) == ["Anime riêng"], "Search history persists when the store is recreated")
for index in 0..<25 { history.record("Query \(index)", source: .phim4k) }
check(history.queries(for: .phim4k).count == 20 && history.queries(for: .phim4k).first == "Query 24", "Recent searches are bounded and sorted newest first")
history.remove("Query 24", source: .phim4k)
check(!history.queries(for: .phim4k).contains("Query 24"), "Individual search history entries can be deleted")
history.clear(source: .phim4k)
check(history.queries(for: .phim4k).isEmpty && history.queries(for: .anime).count == 1, "Clearing history only clears the selected provider")
historyDefaults.removePersistentDomain(forName: suite)
let reordered: MovieCatalog.Object = ["movie": ["name": "Reordered"], "episodes": [
    ["server_name": "Lồng tiếng", "server_data": [["name": "01", "slug": "tap-1", "link_m3u8": "https://media.example/dub.m3u8"]]],
    ["server_name": "Vietsub", "server_data": [["name": "02", "slug": "tap-2", "link_m3u8": "https://media.example/two.m3u8"], ["name": "01", "slug": "tap-1", "link_m3u8": "https://media.example/one.m3u8"]]]
]]
check(MovieCatalog.episodeRow(reordered, serverName: "Vietsub", key: "tap-1")?["link_m3u8"] as? String == "https://media.example/one.m3u8", "Refreshing reordered public servers and episodes retains the selected film link")
check(MovieCatalog.episodeRow(reordered, serverName: "Missing", key: "tap-1") == nil, "A missing server never plays another dub or subtitle version")

let commentFixture = try String(contentsOfFile: "Tests/Fixtures/anime-episodes-comments.html", encoding: .utf8)
let commentDetail = HTMLParser.detail(from: commentFixture, anime: animeFixture, baseURL: animeBase)
check(commentDetail.episodes.map(\.title) == ["1", "Tập 2", "OVA 1"], "Anime excludes login redirects, usernames, comment permalinks, quoted episodes and script strings")
check(commentDetail.episodes.allSatisfy { $0.season == "Vietsub" }, "Anime preserves server identity from the actual episode container")
check(HTMLParser.watchURL(from: commentFixture, baseURL: animeBase, animeURL: animeFixture.url)?.path == "/phim/series-a1/xem-phim.html", "Watch-page discovery skips login redirects and comment links")
let kkMenu = MovieBrowseCatalog.defaults(for: .kkphim)
check(kkMenu.filter { $0.group == "Danh sách phim" }.count == 12, "KKPhim exposes all twelve lists shown on its website")
check(kkMenu.filter { $0.group == "Thể loại" }.count == 26 && kkMenu.filter { $0.group == "Quốc gia" }.count == 36, "KKPhim retains its complete genre and country menus")
let ncMenu = MovieBrowseCatalog.defaults(for: .film4k)
check(ncMenu.filter { $0.group == "Thể loại" }.count == 22, "NguonC exposes all 22 website genres")
check(ncMenu.contains { $0.title == "Phim AI" && $0.path == "api/films/danh-sach/phim-ai" }, "NguonC uses its own AI movie list")
check(ncMenu.contains { $0.title == "Hài" && $0.path == "api/films/the-loai/phim-hai" } && !ncMenu.contains { $0.path.contains("hai-huoc") }, "NguonC genre slugs are not replaced by KKPhim slugs")
let kkOngoing = MovieBrowseCatalog.kkWebsiteItems(try String(contentsOfFile: "Tests/Fixtures/kkphim-ongoing.html", encoding: .utf8))
check(kkOngoing.count == 2 && kkOngoing.allSatisfy { $0.source == .kkphim && $0.url.host == "phimapi.com" }, "KKPhim website-only lists resolve to its own detail API")
check(kkOngoing[0].title == "Ván Cờ Của Cô Ấy" && kkOngoing[0].episodeText == "Tập 16", "Website list parsing keeps the actual movie title and episode status")
let wakanda = try MovieCatalog.object(Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/phim4k-wakanda.json")))
let wakandaEpisodes = Phim4KCatalog.episodes(wakanda, detailURL: coreBase.appendingPathComponent("rest-api/v130/single_details"))
check(wakandaEpisodes.count == 5, "Wakanda Forever retains all five original Phim4K Premium servers")
check(wakandaEpisodes.filter { $0.qualityBadge.contains("4K") }.count == 2, "Wakanda keeps both original 2160p variants distinct from the three 1080p variants")

// URL shape observed on the reported Bleach page; markup is a synthetic regression fixture.
let bleach = Anime(title: "Bleach: Sennen Kessen-hen - Kashin-tan", url: animeBase.appendingPathComponent("phim/bleach-sennen-kessen-hen-kashin-tan-a5985/"), imageURL: nil, episodeText: "", quality: "", score: "")
let bleachHTML = "<div class='list-episode'><a class='btn-episode' data-hash='ep1' href='/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/tap-01-114773.html'>01</a></div><div class='comment-list'><a href='/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/xem-phim.html'>Lostsky</a></div>"
let bleachEpisodes = HTMLParser.detail(from: bleachHTML, anime: bleach, baseURL: animeBase).episodes
check(bleachEpisodes.count == 1 && bleachEpisodes[0].url.lastPathComponent == "tap-01-114773.html" && bleachEpisodes[0].number == 1, "Bleach episode links keep both the display number and opaque episode ID")

let nguoncMenuHTML = "<nav><a href='/the-loai/phim-hai'>Hài</a><a href='/quoc-gia/my'>Mỹ</a><a href='/nam-phat-hanh/2026'>2026</a><a href='https://phimapi.com/the-loai/foreign'>Foreign</a></nav>"
let parsedNguoncMenu = MovieBrowseCatalog.nguoncMenu(nguoncMenuHTML)
check(parsedNguoncMenu.map(\.path) == ["api/films/the-loai/phim-hai", "api/films/quoc-gia/my", "api/films/nam-phat-hanh/2026"], "NguonC website menus convert to its own API routes and discard foreign links")

// Additional regressions for Task 1: AnimeVietsub episode parsing with .html in animeURL and complex titles
let animeWithHTML = Anime(title: "Bleach", url: animeBase.appendingPathComponent("phim/bleach-sennen-kessen-hen-kashin-tan-a5985.html"), imageURL: nil, episodeText: "", quality: "", score: "")
let parsedHTMLURL = HTMLParser.detail(from: bleachHTML, anime: animeWithHTML, baseURL: animeBase).episodes
check(parsedHTMLURL.count == 1 && parsedHTMLURL[0].number == 1, "Anime with .html in animeURL correctly resolves episodes")

let complexEpHTML = "<div class='list-episode'><a class='btn-episode' href='/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/tap-01.html'>Tập 1 - Vietsub Full HD</a><a class='btn-episode' href='/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/tap-02.html'>Tập 2 - Thuyết Minh</a></div>"
let complexEps = HTMLParser.detail(from: complexEpHTML, anime: animeWithHTML, baseURL: animeBase).episodes
check(complexEps.count == 2 && complexEps[0].number == 1 && complexEps[1].number == 2, "Complex episode titles like 'Tập 1 - Vietsub Full HD' are properly extracted")

// Additional regressions for Task 2: Native Schedule timetable parsing
let scheduleNextJSHTML = "<html><script>self.__next_f.push([1,\"{\\\"id\\\":\\\"1\\\",\\\"slug\\\":\\\"anime-thu-2\\\",\\\"title\\\":\\\"Anime Thứ 2\\\",\\\"coverUrl\\\":\\\"https://img.example/t2.jpg\\\",\\\"airTime\\\":\\\"23:00\\\",\\\"pubTimeFormat\\\":\\\"Thứ Hai 23:00\\\",\\\"latestEpisode\\\":\\\"12\\\",\\\"status\\\":\\\"Đã chiếu\\\"},{\\\"id\\\":\\\"2\\\",\\\"slug\\\":\\\"anime-chu-nhat\\\",\\\"title\\\":\\\"Anime Chủ Nhật\\\",\\\"coverUrl\\\":\\\"https://img.example/cn.jpg\\\",\\\"airTime\\\":\\\"18:00\\\",\\\"pubTimeFormat\\\":\\\"Chủ Nhật 18:00\\\",\\\"latestEpisode\\\":\\\"05\\\",\\\"status\\\":\\\"Sắp chiếu\\\"}\"])</script></html>"
let scheduleParsed = HTMLParser.schedule(from: scheduleNextJSHTML, baseURL: animeBase)
check(scheduleParsed[.monday]?.count == 1 && scheduleParsed[.monday]?[0].anime.title == "Anime Thứ 2", "Schedule parses Monday Next.js streaming hydration payload")
check(scheduleParsed[.sunday]?.count == 1 && scheduleParsed[.sunday]?[0].statusText == "Sắp chiếu", "Schedule parses Sunday Next.js streaming hydration payload")

// Next.js fixture derived from a publicly served episode list; only IDs/numbers are retained.
let nextShow = Anime(title: "Fixture", url: animeBase.appendingPathComponent("phim/luc-do-toi-da-chuyen-sinh-thanh-slime-s4-2342192"), imageURL: nil, episodeText: "", quality: "", score: "")
let nextHTML = try String(contentsOfFile: "Tests/Fixtures/anime-next-episodes.html", encoding: .utf8)
let nextEpisodes = HTMLParser.detail(from: nextHTML, anime: nextShow, baseURL: animeBase).episodes
check(nextEpisodes.count == 12 && nextEpisodes.first?.number == 1 && nextEpisodes.last?.number == 12, "Streamed episode metadata restores 12 real entries across different detail/watch routes")
check(HTMLParser.hasCompleteStreamedEpisodes(nextHTML + #"<script type="application/ld+json">{"numberOfEpisodes":12}</script>"#, episodes: nextEpisodes), "Complete streamed episode lists do not need a second watch request")
check(!HTMLParser.hasCompleteStreamedEpisodes(nextHTML + #"<script type="application/ld+json">{"numberOfEpisodes":13}</script>"#, episodes: nextEpisodes), "Partial lists still allow a watch page refresh")
check(nextEpisodes.allSatisfy { $0.url.path.hasPrefix("/xem-phim/luc-do-toi-da-chuyen-sinh-thanh-slime-s4-2342192/tap-") }, "Episode URLs belong to the requested show")
check(HTMLParser.detail(from: nextHTML, anime: nextShow, baseURL: animeBase, includeEpisodes: false).episodes.isEmpty, "Metadata parsing does not block on the episode list")
let foreign = nextHTML.replacingOccurrences(of: "luc-do-toi-da-chuyen-sinh-thanh-slime-s4-2342192", with: "different-show")
check(HTMLParser.detail(from: foreign, anime: nextShow, baseURL: animeBase).episodes.isEmpty, "Another show never supplies episodes")
let multiHTML = "<div class='list-episode' data-server='A'><a href='/phim/series-a1/tap-1.html'>1</a><a href='/phim/series-a1/special.html'>Special</a></div><div class='list-episode' data-server='B'><a href='/phim/series-a1/tap-1.html'>1</a></div>"
let multiple = HTMLParser.detail(from: multiHTML, anime: animeFixture, baseURL: animeBase).episodes
check(multiple.count == 3 && Set(multiple.map(\.season)) == ["A", "B"], "Distinct episode servers and special are preserved")
let unavailableCore: MovieCatalog.Object = ["videos": [["video_file_id": "resolver-only", "label": "VIP"]]]
check(Phim4KCatalog.episodes(unavailableCore, detailURL: coreMovie.url).count == 1, "Core server with an ID remains visible without a direct URL")
check(Phim4KCatalog.stream(unavailableCore, seasonID: nil, episodeID: "resolver-only", base: coreBase) == nil, "Missing VIP URL never silently changes server")
let unknownDayHTML = scheduleNextJSHTML.replacingOccurrences(of: "Thứ Hai 23:00", with: "Đã cập nhật")
let unknownDay = HTMLParser.schedule(from: unknownDayHTML, baseURL: animeBase)
check(unknownDay[.monday]?.isEmpty == true && unknownDay[.sunday]?.count == 1, "A schedule item with no weekday is not assigned Monday")
let hlsURL = URL(string: "https://media.example/manifest")!
check(Phim4KCatalog.mediaKind(status: 200, contentType: "application/vnd.apple.mpegurl", url: hlsURL) == .hls, "HLS can be identified without a filename extension")
check(Phim4KCatalog.mediaKind(status: 206, contentType: "video/x-matroska", url: hlsURL) == .mkv, "MKV uses response MIME")
check(Phim4KCatalog.mediaKind(status: 200, contentType: "application/dash+xml", url: hlsURL) == .dash, "DASH uses response MIME")
check(Phim4KCatalog.mediaKind(status: 403, contentType: "text/html", url: hlsURL) == .authenticationRequired, "HTTP 403 signals authentication required")
check(Phim4KCatalog.mediaKind(status: 200, contentType: "application/json", url: hlsURL) == .intermediate, "JSON is an intermediate response rather than video")
check(Phim4KCatalog.mediaKind(status: 200, contentType: "text/html", url: hlsURL, isWeb: true) == .embed, "Declared embed remains a web player")
print("Extended anime and source isolation regressions passed")

// Synthetic legacy layout based on the publicly indexed weekday/time structure.
let legacyScheduleHTML = try String(contentsOfFile: "Tests/Fixtures/anime-schedule-legacy.html", encoding: .utf8)
let legacySchedule = HTMLParser.schedule(from: legacyScheduleHTML, baseURL: animeBase)
check(legacySchedule[.wednesday]?.first?.airTime == "21:00", "Legacy schedule reads Vietnamese weekday and time")
check(legacySchedule[.thursday]?.count == 2 && legacySchedule[.thursday]?.first?.airTime == "18:30", "Legacy schedule preserves cards with and without a time")
check(legacySchedule[.thursday]?.last?.anime.url.path == "/phim/fixture-no-time-a3", "Legacy schedule links open the same anime")
let scheduleDefaults = UserDefaults(suiteName: "AnPinime.ScheduleTests")!
scheduleDefaults.removePersistentDomain(forName: "AnPinime.ScheduleTests")
let cachedAt = Date(timeIntervalSince1970: 1000)
AnimeScheduleStore.save(legacySchedule, at: cachedAt, defaults: scheduleDefaults)
let restored = AnimeScheduleStore.load(defaults: scheduleDefaults)
check(restored?.0 == cachedAt && restored?.1[.wednesday]?.first?.anime.title == "Anime Thứ Tư", "Schedule cache survives a store reload")
AnimeScheduleStore.save([:], at: Date(), defaults: scheduleDefaults)
check(AnimeScheduleStore.load(defaults: scheduleDefaults)?.0 == cachedAt, "Empty schedule never replaces the last good cache")
check(Phim4KCatalog.mediaKind(prefix: Data([0,0,0,24,0x66,0x74,0x79,0x70])) == .mp4, "MP4 signature works without a video filename extension")
check(Phim4KCatalog.mediaKind(prefix: Data("#EXTM3U\n".utf8)) == .hls, "Range prefix identifies an HLS playlist")

let verifiedAnimeURL = animeBase.appendingPathComponent("phim/series-a1")
check(HTMLParser.isVerifiedAnimeDetail("<h1>Anime</h1><a>Xem phim</a>", url: verifiedAnimeURL), "A real detail shape can validate its anime domain")
check(!HTMLParser.isVerifiedAnimeDetail("<title>Xác Minh An Toàn</title><h1>Anime</h1><a>Xem phim</a>", url: verifiedAnimeURL), "A verification page never validates an anime domain")
check(!HTMLParser.isVerifiedAnimeDetail("<h1>Anime</h1><a>Xem phim</a>", url: animeBase), "The home page is not accepted as proof of a detail page")

let nestedScheduleRow = #"{"id":"nested","slug":"fixture-nested-a1","title":"Anime {đặc biệt}","extra":{"production":"JP"},"pubTimeFormat":"Thứ Tư 21:00","airTime":"21:00"}"#
let encodedNested = try JSONSerialization.data(withJSONObject: [nestedScheduleRow])
let escapedNested = String(data: encodedNested, encoding: .utf8)!.dropFirst().dropLast()
let nestedPage = "<script>self.__next_f.push([1," + escapedNested + "])</script>"
let nestedItems = HTMLParser.schedule(from: nestedPage, baseURL: animeBase)
check(nestedItems[.wednesday]?.first?.anime.title == "Anime {đặc biệt}", "Schedule JSON preserves nested objects and braces inside strings")

let animeSettings = UserDefaults(suiteName: "AnPinime.AnimeSiteTests")!
animeSettings.removePersistentDomain(forName: "AnPinime.AnimeSiteTests")
check(AnimeSiteConfiguration.normalizedBase("https://animevitsub..news") == nil, "Invalid anime host with empty labels is rejected")
animeSettings.set("https://animevietsub.news", forKey: "AnPinime.phim4kURL")
check(AnimeSiteConfiguration.migrateMisplacedURL(defaults: animeSettings), "Misplaced anime URL is moved to the anime setting")
check(AnimeSiteConfiguration.selectedURL(defaults: animeSettings)?.host == "animevietsub.news" && animeSettings.string(forKey: "AnPinime.phim4kURL") == nil, "Anime URL cannot remain a Phim4K Free override")
animeSettings.set("https://free.example", forKey: "AnPinime.phim4kURL")
check(!AnimeSiteConfiguration.migrateMisplacedURL(defaults: animeSettings) && animeSettings.string(forKey: "AnPinime.phim4kURL") == "https://free.example", "A real Free override remains independent")
let latestWatchHTML = "<a class='watch-now' href='/phim/series-a1/tap-10-10010.html'>Xem phim</a>"
check(HTMLParser.watchURL(from: latestWatchHTML, baseURL: animeBase, animeURL: animeFixture.url)?.lastPathComponent == "tap-10-10010.html", "Watch discovery accepts the real latest-episode link")
let canonicalHTML = "<link rel='canonical' href='/phim/renamed-series-a1/'><div class='list-episode'><a href='/phim/renamed-series-a1/tap-1.html'>1</a></div>"
check(HTMLParser.detail(from: canonicalHTML, anime: animeFixture, baseURL: animeBase).episodes.count == 1, "Canonical alias with the same anime ID retains episodes")
let differentCanonical = canonicalHTML.replacingOccurrences(of: "renamed-series-a1", with: "another-series-a2")
check(HTMLParser.detail(from: differentCanonical, anime: animeFixture, baseURL: animeBase).episodes.isEmpty, "Canonical links cannot select another anime ID")
check(!HTMLParser.containsVerification("<title>Anime</title><meta property='og:image' content='poster.jpg'><h1>Anime</h1><a>Xem phim</a><section id='comments'><div class='cf-turnstile'></div></section>"), "A comment captcha does not hide a real anime detail page")

let reorderedPayload: [String: Any] = ["episodes": [["number": 1, "episodeId": "real-1"], ["number": 2, "episodeId": "real-2"]], "animeSlugOrId": "luc-do-toi-da-chuyen-sinh-thanh-slime-s4-2342192"]
let payloadText = String(data: try JSONSerialization.data(withJSONObject: reorderedPayload, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
let payloadLiteral = String(data: try JSONSerialization.data(withJSONObject: [payloadText]), encoding: .utf8)!.dropFirst().dropLast()
let reorderedHTML = "<div class='episode-list'><a href='/xem-phim/luc-do-toi-da-chuyen-sinh-thanh-slime-s4-2342192/tap-1'>Tập 1</a></div><script>self.__next_f.push([1," + payloadLiteral + "])</script>"
check(HTMLParser.detail(from: reorderedHTML, anime: nextShow, baseURL: animeBase).episodes.count == 2, "Streamed episodes decode JSON regardless of property order and whitespace")

// Source 2 keeps the suffixes required by FFmpeg's HLS extension checks.
for ext in ["ts", "m4s", "mp4", "aac", "vtt", "m3u8"] {
    check(Phim4KRelayNaming.suffix(for: URL(string: "https://media.example/opaque.\(ext)?token=hidden")!) == ext,
          "Source-2 relay preserves \(ext) without signed query values")
}
check(Phim4KRelayNaming.suffix(for: URL(string: "https://media.example/api/content/stream/hls?id=hidden")!) == "m3u8", "Extensionless source-2 HLS remains a playlist")
check(Phim4KRelayNaming.suffix(for: URL(string: "https://media.example/unsafe.html")!) == "bin", "Unknown media suffixes remain opaque")
