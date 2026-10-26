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
check(Phim4KFormat.free1.homeSectionsConfig.map(\.title) == ["Mới cập nhật", "Drama xứ Kim Chi", "Thiên đường Drama Tàu", "Phim Việt", "Phim hoạt hình", "Phim lẻ", "Phim bộ mới nhất"], "Nguồn phim 2 provides all 6 requested category rows plus Mới cập nhật")
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
let numericHTML = "<a class='btn-episode' href='/phim/series/xem-phim-99999.html'>12</a>"
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
