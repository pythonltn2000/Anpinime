import SwiftUI
import WebKit

/// Ordinary browser pages stay hidden; only interactive challenges are shown.
@MainActor
final class WebsiteSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var needsInteraction = false
    let webView: WKWebView
    private var pending: CheckedContinuation<(String, URL), Error>?
    private var queue: [(UUID, URL, Bool, CheckedContinuation<(String, URL), Error>)] = []
    private var activeID: UUID?
    private var waitForEpisodes = false
    private var lastEpisodeCount = -1
    private var stableEpisodePolls = 0
    private var renderedSince: Date?
    private var timer: Timer?
    private var deadline = Date()
    private var inspecting = false
    private var lastWasChallenge = false
    private var targetURL: URL?
    private var generation = UUID()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 720), configuration: configuration)
        super.init()
        webView.customUserAgent = AnimeService.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func load(_ url: URL, waitForEpisodes: Bool = false) async throws -> (String, URL) {
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.append((id, url, waitForEpisodes, continuation))
                startNext()
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancelRequest(id) }
        })
    }

    private func cancelRequest(_ id: UUID) {
        if activeID == id { finish(.failure(CancellationError())) }
        else if let index = queue.firstIndex(where: { $0.0 == id }) {
            queue.remove(at: index).3.resume(throwing: CancellationError())
        }
    }

    private func startNext() {
        guard pending == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        activeID = request.0
        pending = request.3
        targetURL = request.1
        waitForEpisodes = request.2
        lastEpisodeCount = -1
        stableEpisodePolls = 0
        renderedSince = nil
        lastWasChallenge = false
        generation = UUID()
        deadline = Date().addingTimeInterval(45)
        webView.load(URLRequest(url: request.1, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40))
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectPage() }
        }
    }

    private func inspectPage() {
        guard pending != nil, !inspecting else { return }
        if Date() > deadline {
            if lastWasChallenge, let url = targetURL { finish(.failure(AnimeServiceError.verificationRequired(url))) }
            else { finish(.failure(URLError(.timedOut))) }
            return
        }
        guard !webView.isLoading else { return }
        inspecting = true
        let requestGeneration = generation
        webView.evaluateJavaScript(Self.pageInspection) { [weak self] result, _ in
            guard let self else { return }
            self.inspecting = false
            guard self.generation == requestGeneration, self.pending != nil, let page = result as? [String: Any],
                  let html = page["html"] as? String, let url = self.webView.url,
                  self.acceptsPageURL(url), !html.isEmpty else { return }
            self.lastWasChallenge = HTMLParser.containsVerification(html)
            if !self.lastWasChallenge {
                if self.waitForEpisodes {
                    if self.renderedSince == nil { self.renderedSince = Date() }
                    let identity = Anime(title: "", url: self.targetURL ?? url, imageURL: nil, episodeText: "", quality: "", score: "")
                    let count = HTMLParser.detail(from: html, anime: identity, baseURL: url.deletingLastPathComponent()).episodes.count
                    self.stableEpisodePolls = count == self.lastEpisodeCount ? self.stableEpisodePolls + 1 : 0
                    self.lastEpisodeCount = count
                    let elapsed = Date().timeIntervalSince(self.renderedSince ?? Date())
                    if elapsed < 8 && (count == 0 || self.stableEpisodePolls < 3) { return }
                }
                Task { @MainActor in
                    await self.copyCookies()
                    guard self.generation == requestGeneration, self.pending != nil else { return }
                    self.finish(.success((html, url)))
                }
            } else if (page["interactive"] as? Bool) == true, !self.needsInteraction {
                self.deadline = Date().addingTimeInterval(180)
                self.needsInteraction = true
            }
        }
    }

    func copyCookies() async {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
    }

    private func acceptsPageURL(_ url: URL) -> Bool {
        #if DEBUG
        if PlaybackSmokeTest.animeFixture, url.scheme == "http", url.host == "127.0.0.1", url.port == 8765 { return true }
        #endif
        return url.scheme == "https"
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<(String, URL), Error>) {
        timer?.invalidate()
        timer = nil
        webView.stopLoading()
        needsInteraction = false
        let continuation = pending
        pending = nil
        activeID = nil
        generation = UUID()
        inspecting = false
        continuation?.resume(with: result)
        startNext()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { inspectPage() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true else { decisionHandler(.allow); return }
        let host = navigationAction.request.url?.host?.lowercased() ?? ""
        let allowed = host == targetURL?.host || AnimeSiteConfiguration.isAutomaticHost(host)
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    static let pageInspection = """
    (() => {
      const visible = e => { const r=e.getBoundingClientRect(); const s=getComputedStyle(e); return r.width>10 && r.height>10 && s.display!=='none' && s.visibility!=='hidden'; };
      return {html:document.documentElement.outerHTML, interactive:Array.from(document.querySelectorAll('iframe[src*="challenges.cloudflare.com"],iframe[src*="recaptcha"],iframe[src*="hcaptcha"],.cf-turnstile,.g-recaptcha,.h-captcha,#challenge-stage input[type="checkbox"]')).some(visible)};
    })()
    """
}

struct VerificationGate: View {
    @ObservedObject var browser: WebsiteSession
    var body: some View {
        Group {
            if !browser.needsInteraction {
                VerificationWebView(browser: browser)
                    .frame(width: 390, height: 720)
                    .frame(width: 1, height: 1).clipped().opacity(0.001)
                    .allowsHitTesting(false).accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
            .sheet(isPresented: $browser.needsInteraction) {
                NavigationView {
                    VerificationWebView(browser: browser)
                        .navigationTitle("Xác minh kết nối")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Đóng") { browser.cancel() }
                            }
                        }
                }
                .interactiveDismissDisabled()
            }
    }
}

private struct VerificationWebView: UIViewRepresentable {
    let browser: WebsiteSession
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
