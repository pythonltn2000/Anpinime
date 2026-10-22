import SwiftUI
import WebKit
import AVKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: AnimeService
    let episode: Episode

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerControllerView(episodeURL: episode.url, baseURL: service.baseURL)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .padding(.top, 10).padding(.trailing, 14)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
    let episodeURL: URL
    let baseURL: URL

    func makeUIViewController(context: Context) -> AnimePlayerViewController {
        AnimePlayerViewController(episodeURL: episodeURL, baseURL: baseURL)
    }

    func updateUIViewController(_ uiViewController: AnimePlayerViewController, context: Context) { }
}

@MainActor
private final class AnimePlayerViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let episodeURL: URL
    private let baseURL: URL
    private var directWebView: WKWebView?
    private var fallbackWebView: WKWebView?
    private var playerController: AVPlayerViewController?
    private var fallbackTimer: Timer?
    private let loadingLabel = UILabel()

    init(episodeURL: URL, baseURL: URL) {
        self.episodeURL = episodeURL
        self.baseURL = baseURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadingLabel.text = "Đang tải thông tin video…"
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        attemptDirectPlayer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        fallbackTimer?.invalidate()
        directWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "videoFound")
        fallbackWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "videoFound")
    }

    private func attemptDirectPlayer() {
        var request = URLRequest(url: episodeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")

        Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = URLSessionConfiguration.default
                configuration.httpCookieStorage = .shared
                configuration.httpShouldSetCookies = true
                let (data, response) = try await URLSession(configuration: configuration).data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                      let html = String(data: data, encoding: .utf8),
                      let values = HTMLParser.playerParameters(from: html) else {
                    self.startFallback()
                    return
                }
                self.startDirect(parameters: PlayerParameters(filmID: values.filmID, hash: values.hash))
            } catch {
                self.startFallback()
            }
        }
    }

    private func startDirect(parameters: PlayerParameters) {
        loadingLabel.text = "Đang giải mã luồng phát…"
        let configuration = playerConfiguration(injectFallbackScript: false)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = AnimeService.userAgent
        webView.isHidden = true
        view.addSubview(webView)
        directWebView = webView

        let hash64 = Data(parameters.hash.utf8).base64EncodedString()
        let film64 = Data(parameters.filmID.utf8).base64EncodedString()
        let key64 = Data("dm_thang_suc_vat_get_link_an_dbt".utf8).base64EncodedString()
        let html = directPlayerHTML(hash64: hash64, film64: film64, key64: key64)
        webView.loadHTMLString(html, baseURL: baseURL)

        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 14, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.startFallback() }
        }
    }

    private func startFallback() {
        guard fallbackWebView == nil, playerController == nil else { return }
        fallbackTimer?.invalidate()
        loadingLabel.text = "Đang tải trình phát website…"
        let configuration = playerConfiguration(injectFallbackScript: true)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = AnimeService.userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, belowSubview: loadingLabel)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        fallbackWebView = webView
        var request = URLRequest(url: episodeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    private func playerConfiguration(injectFallbackScript: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(self, name: "videoFound")
        if injectFallbackScript {
            configuration.userContentController.addUserScript(WKUserScript(
                source: fallbackJavaScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }
        return configuration
    }

    private func showNativePlayer(url: URL) {
        fallbackTimer?.invalidate()
        let headers = ["User-Agent": AnimeService.userAgent, "Referer": episodeURL.absoluteString]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        let controller = AVPlayerViewController()
        controller.player = player
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(controller.view, at: 0)
        controller.didMove(toParent: self)
        playerController = controller
        loadingLabel.isHidden = true
        directWebView?.removeFromSuperview()
        fallbackWebView?.isHidden = true
        player.play()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "videoFound", let value = message.body as? String,
              let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        showNativePlayer(url: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === fallbackWebView { loadingLabel.isHidden = true }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === directWebView { startFallback() }
        else { loadingLabel.text = "Không tải được video: \(error.localizedDescription)" }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === directWebView { startFallback() }
        else { loadingLabel.text = "Không kết nối được trình phát" }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.host == episodeURL.host { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Trình phát", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    private func directPlayerHTML(hash64: String, film64: String, key64: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width"><style>body{background:#000}</style>
        <script src="/js/pako.min.js"></script></head><body><script>
        function bytes(s){return Uint8Array.from(atob(s),c=>c.charCodeAt(0));}
        function source(data){
          try { var j=JSON.parse(data); return (j.sources&&j.sources[0]&&j.sources[0].file)||j.link||j.file||j.url||(j.player&&j.player.sources&&j.player.sources[0].file); } catch(e) {}
          var m=data.match(/https?:\\/\\/[^\\s\"'<>]+\\.(?:m3u8|mp4)[^\\s\"'<>]*/); return m&&m[0];
        }
        async function start(){
          try {
            if(typeof pako==='undefined'){await new Promise((ok,no)=>{var s=document.createElement('script');s.src='https://cdnjs.cloudflare.com/ajax/libs/pako/2.1.0/pako.min.js';s.onload=ok;s.onerror=no;document.head.appendChild(s);});}
            var hash=atob('\(hash64)'), id=atob('\(film64)'), keyText=atob('\(key64)');
            var digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(keyText));
            var key=await crypto.subtle.importKey('raw',digest,{name:'AES-CBC'},false,['decrypt']);
            var form=new FormData(); form.append('link',hash); form.append('id',id);
            var response=await fetch('/ajax/player',{method:'POST',headers:{'X-Requested-With':'XMLHttpRequest'},body:form,credentials:'include'});
            if(!response.ok) throw Error('HTTP '+response.status);
            var value=await response.text(), encrypted=value;
            try { var json=JSON.parse(value); encrypted=json.data||json.link||json.html||value; } catch(e) {}
            encrypted=encrypted.replace(/-/g,'+').replace(/_/g,'/'); while(encrypted.length%4)encrypted+='=';
            var raw=bytes(encrypted);
            var clear=await crypto.subtle.decrypt({name:'AES-CBC',iv:raw.slice(0,16)},key,raw.slice(16));
            var text; try{text=pako.inflateRaw(new Uint8Array(clear),{to:'string'});}catch(e){text=new TextDecoder().decode(clear);}
            var found=source(text); if(!found) throw Error('No source');
            window.webkit.messageHandlers.videoFound.postMessage(found);
          } catch(e) { document.title='ERROR:'+e.message; }
        }
        var checks=0, timer=setInterval(()=>{if(typeof pako!=='undefined'||checks++>30){clearInterval(timer);start();}},100);
        </script></body></html>
        """
    }

    private var fallbackJavaScript: String {
        """
        (function(){
          if(window.__anyanimeInstalled)return; window.__anyanimeInstalled=true;
          ['.Adv','.ad-center','.ads','.advertisement','[class*="banner"]','.popup','.modal-backdrop','header','footer','.sidebar','.breadcrumb','.comments','.film-info','.heading-film','.list-episode-box','.server-list','nav','.navbar','.menu'].forEach(function(s){document.querySelectorAll(s).forEach(function(e){e.style.display='none';});});
          document.body.style.background='#000';
          function report(v){var s=v.currentSrc||v.src||'';if(!s&&v.querySelector('source'))s=v.querySelector('source').src||'';if(/^https?:/.test(s))window.webkit.messageHandlers.videoFound.postMessage(s);}
          function watch(v){if(v.__aa)return;v.__aa=true;v.addEventListener('playing',function(){report(v)});v.addEventListener('loadeddata',function(){report(v)});report(v);}
          document.querySelectorAll('video').forEach(watch);
          new MutationObserver(function(ms){ms.forEach(function(m){m.addedNodes.forEach(function(n){if(n.nodeName==='VIDEO')watch(n);if(n.querySelectorAll)n.querySelectorAll('video').forEach(watch);});});}).observe(document.documentElement,{childList:true,subtree:true});
          setTimeout(function(){var b=document.querySelector('.jw-icon-playback,.play-btn,[class*="play-button"],button[aria-label*="Play"]');if(b)b.click();},2500);
        })();
        """
    }
}
