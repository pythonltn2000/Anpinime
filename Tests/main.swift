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
