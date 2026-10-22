import SwiftUI
import WebKit

// A browser-based replacement for a broken native HTML-scraping client.
// Cookies remain in the app's own persistent WKWebsiteDataStore (not Safari's).
@MainActor
final class AnimeBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var displayedURL = ""
    @Published private(set) var status = "Đang chuẩn bị..."
    @Published private(set) var isLoading = false
    @Published private(set) var siteVerified = false
    @Published private(set) var debugLines: [String] = []
    @Published private(set) var selectedSource = 0
    @Published private(set) var sourceURLs = [
        "https://bit.ly/animevietsubtv",
        "https://www.animevietsub.sale/",
        "https://animevietsub.fan/",
        "https://animevietsub.bio/"
    ]
    @Published var remoteConfigURL: String = UserDefaults.standard.string(forKey: "RemoteConfigURL") ?? ""

    let webView: WKWebView
    private var hasStarted = false
    private var generation = 0
    private var lastNavigationID = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func startOnce() {
        guard !hasStarted else { return }
        hasStarted = true
        let saved = UserDefaults.standard.string(forKey: "LastVerifiedSource")
        if let saved, let url = URL(string: saved), url.scheme == "https", !sourceURLs.contains(saved) {
            sourceURLs.insert(saved, at: 1)
        }
        loadSource(at: 0)
        Task { await fetchRemoteConfigIfAvailable() }
    }

    func loadSource(at index: Int) {
        guard sourceURLs.indices.contains(index) else {
            status = "Không có nguồn khả dụng. Thử chọn nguồn thủ công."
            return
        }
        let raw = sourceURLs[index]
        guard let url = URL(string: raw), url.scheme == "https" else {
            log("Bỏ qua URL không hợp lệ: \(raw)")
            return
        }
        generation += 1
        selectedSource = index
        siteVerified = false
        isLoading = true
        displayedURL = url.absoluteString
        status = "Đang tìm trang phim..."
        log("Mở nguồn \(index + 1): \(raw)")
        webView.stopLoading()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("vi-VN,vi;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    private func nextSource(reason: String) {
        log(reason)
        guard !siteVerified else { return }
        if sourceURLs.indices.contains(selectedSource + 1) {
            loadSource(at: selectedSource + 1)
        } else {
            status = "Chưa truy cập được nguồn phim. Mở mục Nhật ký để kiểm tra."
            isLoading = false
        }
    }

    func reload() {
        log("Tải lại trang")
        webView.reload()
    }

    func goHome() { loadSource(at: 0) }
    func tryNextSource() { nextSource(reason: "Người dùng yêu cầu thử nguồn khác") }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    func copyDiagnostics() -> String {
        "AnyAnime AutoRedirect\nURL: \(displayedURL)\nTrạng thái: \(status)\n" + debugLines.joined(separator: "\n")
    }

    func setRemoteConfig(_ value: String) {
        remoteConfigURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(remoteConfigURL, forKey: "RemoteConfigURL")
        Task { await fetchRemoteConfigIfAvailable() }
    }

    // An optional JSON file you control can replace the fallback list without a rebuild.
    // Format: {"sources":["https://bit.ly/animevietsubtv", "https://www.animevietsub.sale/"]}
    func fetchRemoteConfigIfAvailable() async {
        let text = remoteConfigURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https" else { return }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                log("Nguồn cấu hình trả về lỗi HTTP")
                return
            }
            guard data.count < 50_000 else { log("Từ chối cấu hình quá lớn"); return }
            let remote = try JSONDecoder().decode(RemoteSources.self, from: data)
            let validated = Array(remote.sources.filter {
                guard let url = URL(string: $0) else { return false }
                return url.scheme == "https" && url.host != nil
            }.prefix(12))
            guard !validated.isEmpty else { log("Cấu hình không có nguồn HTTPS hợp lệ"); return }
            sourceURLs = validated
            log("Đã cập nhật \(validated.count) nguồn từ cấu hình HTTPS")
        } catch {
            log("Lỗi cấu hình nguồn: \(error.localizedDescription)")
        }
    }

    private struct RemoteSources: Decodable { let sources: [String] }

    private func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLines.append("[\(time)] \(message)")
        if debugLines.count > 100 { debugLines.removeFirst(debugLines.count - 100) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        displayedURL = webView.url?.absoluteString ?? displayedURL
        lastNavigationID += 1
        log("Bắt đầu: \(displayedURL)")
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let newURL = webView.url?.absoluteString ?? "(chưa nhận URL)"
        displayedURL = newURL
        log("HTTP redirect → \(newURL)")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        displayedURL = webView.url?.absoluteString ?? displayedURL
        log("Đã nhận phản hồi: \(displayedURL)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        displayedURL = webView.url?.absoluteString ?? displayedURL
        log("Hoàn tất điều hướng: \(displayedURL)")
        // Allow JavaScript redirects and client-side HTML rendering to settle.
        let thisGeneration = generation
        let thisNavigation = lastNavigationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, thisGeneration == self.generation,
                  thisNavigation == self.lastNavigationID else { return }
            self.checkForAnimeContent(sourceGeneration: thisGeneration, navigationID: thisNavigation)
        }
    }

    private func checkForAnimeContent(sourceGeneration: Int, navigationID: Int) {
        let script = """
        (function(){
          var txt = document.body ? document.body.innerText : '';
          return {
            title: document.title || '',
            links: document.querySelectorAll('a[href]').length,
            cards: document.querySelectorAll('.ml-item,.film-item,.movie-item,.item,.list-film-item').length,
            likelyFilmLinks: document.querySelectorAll('a[href*="phim"],a[href*="anime"]').length,
            blocked: /just a moment|verify you are human|checking your browser|xác minh|access denied/i.test((document.title||'')+' '+txt.slice(0,300))
          };
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, sourceGeneration == self.generation,
                      navigationID == self.lastNavigationID else { return }
                guard let value = result as? [String: Any] else {
                    self.log("Chưa đọc được DOM: \(error?.localizedDescription ?? "trống")")
                    self.status = "Đang chờ website phản hồi..."
                    return
                }
                let links = value["links"] as? Int ?? 0
                let cards = value["cards"] as? Int ?? 0
                let films = value["likelyFilmLinks"] as? Int ?? 0
                let blocked = value["blocked"] as? Bool ?? false
                let title = value["title"] as? String ?? ""
                let host = self.webView.url?.host?.lowercased() ?? ""
                self.log("DOM: title=\(title), links=\(links), cards=\(cards), filmLinks=\(films), blocked=\(blocked)")
                let probableAnimeSite = host.contains("animevietsub")
                let looksLikeCatalog = links >= 15 && (cards >= 3 || films >= 8)
                if probableAnimeSite && looksLikeCatalog && !blocked {
                    self.siteVerified = true
                    self.status = "Đã tải website anime"
                    if let url = self.webView.url, let baseURL = URL(string: "\(url.scheme ?? "https")://\(host)/") {
                        UserDefaults.standard.set(baseURL.absoluteString, forKey: "LastVerifiedSource")
                    }
                } else if blocked {
                    // Do not skip an interactive CAPTCHA; the user may need to solve it.
                    self.status = "Trang đang yêu cầu xác minh. Bạn có thể hoàn tất trên màn hình."
                } else {
                    self.status = "Trang đã mở nhưng chưa nhận ra danh sách anime."
                    let capturedGeneration = self.generation
                    let capturedNavigation = self.lastNavigationID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                        guard let self, self.generation == capturedGeneration,
                              self.lastNavigationID == capturedNavigation,
                              !self.siteVerified else { return }
                        self.nextSource(reason: "Không nhận thấy danh sách anime sau 10 giây")
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        isLoading = false
        nextSource(reason: "Không kết nối được: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        isLoading = false
        log("Lỗi tải trang: \(error.localizedDescription)")
        status = "Lỗi tải trang. Có thể chọn nguồn khác."
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            log("HTTP \(response.statusCode): \(response.url?.absoluteString ?? "")")
            if response.statusCode >= 400 {
                status = "HTTP \(response.statusCode) — website từ chối phản hồi"
                let currentGeneration = generation
                let capturedNavigation = lastNavigationID
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, !self.siteVerified,
                          self.generation == currentGeneration,
                          self.lastNavigationID == capturedNavigation else { return }
                    self.nextSource(reason: "Thử nguồn khác do HTTP \(response.statusCode)")
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["https", "http", "about", "blob", "data"].contains(scheme) {
            if ["tel", "mailto"].contains(scheme) { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Internal movie/detail links often use target=_blank; keep those in the app.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.host?.contains("animevietsub") == true {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
