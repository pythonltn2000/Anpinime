import SwiftUI
import WebKit

/// Keep the site's day selectors and release times intact instead of guessing a timetable.
struct AnimeScheduleView: View {
    @State private var base: URL?
    @State private var selection: Anime?
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()
    var body: some View {
        ZStack {
            if let base {
                ScheduleBrowser(base: base, loading: $loading, error: $error, selected: $selection).id(revision)
            }
            if loading { ProgressView("Đang tải lịch chiếu…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            if let error {
                VStack(spacing: 16) { Text(error).multilineTextAlignment(.center); Button("Thử lại") { reload() } }
                    .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            NavigationLink(destination: selection.map { AnimeDetailView(anime: $0) }, isActive: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) { EmptyView() }.hidden()
        }
        .navigationTitle("Lịch chiếu").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: reload) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Cập nhật lịch chiếu") } }
        .task { if base == nil { base = await DomainResolver.shared.resolve() } }
    }
    private func reload() { error = nil; loading = true; revision = UUID() }
}

private struct ScheduleBrowser: UIViewRepresentable {
    let base: URL
    @Binding var loading: Bool
    @Binding var error: String?
    @Binding var selected: Anime?
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(WKUserScript(source: Self.style, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = AnimeService.userAgent
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false; webView.backgroundColor = .black
        var request = URLRequest(url: base.appendingPathComponent("lich-chieu-phim.html"), cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
        request.setValue(base.absoluteString, forHTTPHeaderField: "Referer")
        webView.load(request)
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScheduleBrowser
        init(parent: ScheduleBrowser) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            if let url = webView.url { Task { _ = await DomainResolver.shared.acceptResolvedURL(url) } }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { parent.loading = false; parent.error = "Không tải được lịch chiếu. " + error.localizedDescription } }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.targetFrame?.isMainFrame != false, let url = action.request.url else { decisionHandler(.allow); return }
            let host = url.host ?? ""
            let sameSource = host == parent.base.host || host.hasPrefix("animevietsub.") || host.hasPrefix("www.animevietsub.")
            if sameSource, action.navigationType == .linkActivated, url.path.hasPrefix("/phim/") {
                parent.selected = Anime(title: url.lastPathComponent.replacingOccurrences(of: "-", with: " "), url: url, imageURL: nil, episodeText: "", quality: "", score: "")
                decisionHandler(.cancel)
            } else { decisionHandler(sameSource ? .allow : .cancel) }
        }
    }
    private static let style = """
    (()=>{
      if(/xác minh|just a moment|verify|checking/i.test(document.title)||document.querySelector('#challenge-form,.cf-turnstile'))return;
      let m=document.querySelector('meta[name=viewport]');if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}m.content='width=device-width,initial-scale=1';
      let s=document.createElement('style');s.textContent='header,footer,.header,.footer,.Adv,.ads,.advertisement,.ad-center,.sidebar{display:none!important}html,body{margin:0!important;max-width:100%!important}';document.head.appendChild(s);
      window.open=()=>null;
    })()
    """
}
