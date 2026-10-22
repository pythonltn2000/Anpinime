import SwiftUI
import WebKit

struct VerificationView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let onVerified: (URL?) -> Void
    @StateObject private var browser = VerificationBrowser()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled").foregroundColor(.orange)
                    Text(browser.status).font(.caption).lineLimit(2)
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12))

                VerificationWebView(browser: browser)

                HStack {
                    Button { browser.reload() } label: { Label("Tải lại", systemImage: "arrow.clockwise") }
                    Spacer()
                    Button("Đã xác minh — thử lại") {
                        Task {
                            let finalURL = await browser.copyCookiesAndCurrentURL()
                            onVerified(finalURL)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
            .navigationTitle("Xác minh website")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .onAppear { browser.start(url) }
    }
}

private struct VerificationWebView: UIViewRepresentable {
    @ObservedObject var browser: VerificationBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

@MainActor
private final class VerificationBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var status = "Hoàn tất ô xác minh của AnimeVietsub bên dưới"
    let webView: WKWebView
    private var started = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.customUserAgent = AnimeService.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func start(_ url: URL) {
        guard !started else { return }
        started = true
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.setValue("vi-VN,vi;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    func reload() { webView.reload() }

    func copyCookiesAndCurrentURL() async -> URL? {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
        return webView.url
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        status = "Đang tải trang xác minh…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = "Hoàn tất CAPTCHA nếu có, sau đó bấm “Đã xác minh”"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status = "Lỗi tải: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status = "Lỗi kết nối: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "AnimeVietsub", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        topViewController()?.present(alert, animated: true)
    }

    private func topViewController() -> UIViewController? {
        var root = webView.window?.rootViewController
        while let presented = root?.presentedViewController { root = presented }
        return root
    }
}

