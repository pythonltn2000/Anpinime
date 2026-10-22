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
    private var revealTimer: Timer?
    private var fallbackLoadedURL: URL?
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
        revealTimer?.invalidate()
        for webView in [directWebView, fallbackWebView] {
            ["videoFound", "iframeFound", "playerReady", "playerError"].forEach {
                webView?.configuration.userContentController.removeScriptMessageHandler(forName: $0)
            }
        }
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

    private func startFallback(url requestedURL: URL? = nil) {
        guard playerController == nil else { return }
        fallbackTimer?.invalidate()
        directWebView?.stopLoading()
        directWebView?.removeFromSuperview()
        directWebView = nil

        let targetURL = requestedURL ?? episodeURL
        if let webView = fallbackWebView {
            guard fallbackLoadedURL?.absoluteString != targetURL.absoluteString else { return }
            fallbackLoadedURL = targetURL
            loadingLabel.isHidden = false
            loadingLabel.text = "Đang mở trình phát toàn màn hình…"
            webView.isHidden = true
            webView.load(playerRequest(for: targetURL))
            scheduleFallbackReveal(for: webView)
            return
        }

        loadingLabel.text = "Đang tải trình phát website…"
        let configuration = playerConfiguration(injectFallbackScript: true)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = AnimeService.userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        view.insertSubview(webView, belowSubview: loadingLabel)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        fallbackWebView = webView
        fallbackLoadedURL = targetURL
        webView.load(playerRequest(for: targetURL))
        scheduleFallbackReveal(for: webView)
    }

    private func playerRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
        request.setValue(AnimeService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(episodeURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    private func scheduleFallbackReveal(for webView: WKWebView) {
        revealTimer?.invalidate()
        revealTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self, weak webView] _ in
            Task { @MainActor in
                guard let self, let webView, webView === self.fallbackWebView, webView.isHidden else { return }
                self.loadingLabel.text = "Không thể tách riêng video — hãy chọn phát trên trang"
                webView.isHidden = false
            }
        }
    }

    private func playerConfiguration(injectFallbackScript: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        ["videoFound", "iframeFound", "playerReady", "playerError"].forEach {
            configuration.userContentController.add(self, name: $0)
        }
        if injectFallbackScript {
            configuration.userContentController.addUserScript(WKUserScript(
                source: fallbackJavaScript,
                injectionTime: .atDocumentStart,
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
        revealTimer?.invalidate()
        directWebView?.removeFromSuperview()
        fallbackWebView?.isHidden = true
        player.play()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "videoFound":
            guard let value = message.body as? String, let url = resolvedURL(from: value) else { return }
            showNativePlayer(url: url)
        case "iframeFound":
            guard let value = message.body as? String, let url = resolvedURL(from: value) else { return }
            startFallback(url: url)
        case "playerReady":
            revealTimer?.invalidate()
            fallbackWebView?.isHidden = false
            loadingLabel.isHidden = true
        case "playerError":
            if let detail = message.body as? String { print("[AnyAnime Player] \(detail)") }
            startFallback()
        default:
            break
        }
    }

    private func resolvedURL(from value: String) -> URL? {
        let cleaned = value
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned, relativeTo: fallbackLoadedURL ?? episodeURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === fallbackWebView else { return }
        webView.evaluateJavaScript("window.__anyanimeFocusPlayer ? window.__anyanimeFocusPlayer() : false") { [weak self, weak webView] result, _ in
            Task { @MainActor in
                guard let self, let webView, webView === self.fallbackWebView else { return }
                if (result as? Bool) == true {
                    self.revealTimer?.invalidate()
                    webView.isHidden = false
                    self.loadingLabel.isHidden = true
                } else {
                    webView.evaluateJavaScript("/cloudflare|captcha|verify you are human|checking your browser/i.test(document.title+' '+(document.body&&document.body.innerText||''))") { result, _ in
                        Task { @MainActor in
                            if (result as? Bool) == true {
                                webView.isHidden = false
                                self.loadingLabel.isHidden = true
                            }
                        }
                    }
                }
            }
        }
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
          function item(v){return typeof v==='string'?v:(v&&(v.file||v.src||v.url));}
          try {
            var j=JSON.parse(data), first=j.sources&&j.sources[0], nested=j.player&&j.player.sources&&j.player.sources[0];
            var direct=item(first)||item(nested)||item(j.data)||item(j.link)||item(j.file)||item(j.url);
            if(direct)return {kind:/\\.(?:m3u8|mp4)(?:$|[?#])/i.test(direct)?'video':'iframe',url:direct};
          } catch(e) {}
          var doc=new DOMParser().parseFromString(data,'text/html');
          var media=doc.querySelector('video[src],source[src]');
          if(media)return {kind:'video',url:media.getAttribute('src')};
          var frame=doc.querySelector('iframe[src]');
          if(frame)return {kind:'iframe',url:frame.getAttribute('src')};
          var normalized=data.replace(/\\\\\\//g,'/');
          var m=normalized.match(/https?:\\/\\/[^\\s\"'<>]+\\.(?:m3u8|mp4)(?:[^\\s\"'<>]*)?/i);
          if(m)return {kind:'video',url:m[0]};
          var u=normalized.match(/https?:\\/\\/[^\\s\"'<>]+/i);
          return u&&{kind:'iframe',url:u[0]};
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
            var found=source(text); if(!found||!found.url) throw Error('Không tìm thấy nguồn video');
            var absolute=new URL(found.url,location.href).href;
            window.webkit.messageHandlers[found.kind==='video'?'videoFound':'iframeFound'].postMessage(absolute);
          } catch(e) {
            var detail=(e&&e.message)||String(e);
            document.title='ERROR:'+detail;
            window.webkit.messageHandlers.playerError.postMessage(detail);
          }
        }
        var checks=0, timer=setInterval(()=>{if(typeof pako!=='undefined'||checks++>30){clearInterval(timer);start();}},100);
        </script></body></html>
        """
    }

    private var fallbackJavaScript: String {
        """
        (function(){
          if(window.__anyanimeInstalled)return; window.__anyanimeInstalled=true;
          var hidden=['.Adv','.ad-center','.ads','.advertisement','[class*="ads"]','[class*="banner"]','[id*="ads"]','iframe[src*="ads"]','.popup','.modal-backdrop','.header-ads-pc','.Adv.ad-center-header','header','footer','.footer','.header','.sidebar','.breadcrumb','.comments','.film-info','.heading-film','.list-episode-box','.server-list','.film-thumb','.film-desc','.film-buttons','.category-heading','.block-film','nav','.navbar','.menu'];
          var reportedFrames={};
          function send(name,value){try{window.webkit.messageHandlers[name].postMessage(value);}catch(e){}}
          function important(el,key,value){if(el)el.style.setProperty(key,value,'important');}
          function hideChrome(){
            hidden.forEach(function(s){try{document.querySelectorAll(s).forEach(function(e){important(e,'display','none');});}catch(e){}});
            important(document.documentElement,'margin','0'); important(document.documentElement,'padding','0');
            important(document.documentElement,'background','#000'); important(document.documentElement,'overflow','hidden');
            important(document.body,'margin','0'); important(document.body,'padding','0');
            important(document.body,'background','#000'); important(document.body,'overflow','hidden');
          }
          function isolate(el){
            if(!el)return false; hideChrome();
            var node=el;
            while(node&&node!==document.body){
              var parent=node.parentElement;
              if(!parent)break;
              Array.prototype.forEach.call(parent.children,function(sibling){if(sibling!==node)important(sibling,'display','none');});
              important(parent,'display','block'); important(parent,'visibility','visible'); important(parent,'opacity','1');
              important(parent,'position','static'); important(parent,'width','100%'); important(parent,'height','100%');
              important(parent,'margin','0'); important(parent,'padding','0'); important(parent,'transform','none');
              node=parent;
            }
            important(el,'display','block'); important(el,'visibility','visible'); important(el,'opacity','1');
            important(el,'position','fixed'); important(el,'inset','0'); important(el,'width','100vw');
            important(el,'height','100vh'); important(el,'max-width','none'); important(el,'max-height','none');
            important(el,'margin','0'); important(el,'padding','0'); important(el,'z-index','2147483647');
            important(el,'background','#000');
            send('playerReady','ready'); return true;
          }
          function mediaURL(v){
            var s=v.currentSrc||v.getAttribute('src')||'';
            if(!s){var source=v.querySelector('source[src]');if(source)s=source.getAttribute('src')||'';}
            try{return s?new URL(s,location.href).href:'';}catch(e){return '';}
          }
          function watch(v){
            if(!v)return false;
            isolate(v); important(v,'object-fit','contain'); v.setAttribute('playsinline','');
            if(!v.__aa){
              v.__aa=true;
              ['playing','loadeddata','canplay'].forEach(function(name){v.addEventListener(name,function(){var s=mediaURL(v);if(/^https?:/i.test(s))send('videoFound',s);});});
            }
            var s=mediaURL(v); if(/^https?:/i.test(s))send('videoFound',s);
            var p=v.play(); if(p&&p.catch)p.catch(function(){});
            return true;
          }
          function usefulFrame(frame){
            var src=frame.getAttribute('src')||'';
            if(!src||/^(?:about:blank|javascript:)/i.test(src)||/(?:doubleclick|googlesyndication|facebook|popads|adservice|\\/ads?[\\/.?])/i.test(src))return false;
            var rect=frame.getBoundingClientRect();
            return rect.width>=240&&rect.height>=120;
          }
          function focus(){
            hideChrome();
            var videos=document.querySelectorAll('video');
            if(videos.length)return watch(videos[0]);
            var selectors=['#media-player','.player-container','.watching_player','#player','.jwplayer','[class*="video-player"]','[class*="player-wrap"]'];
            var player=null;
            for(var i=0;i<selectors.length&&!player;i++){try{player=document.querySelector(selectors[i]);}catch(e){}}
            var frames=Array.prototype.filter.call(document.querySelectorAll('iframe[src]'),usefulFrame);
            frames.sort(function(a,b){var ar=a.getBoundingClientRect(),br=b.getBoundingClientRect();return br.width*br.height-ar.width*ar.height;});
            var frame=frames[0];
            if(frame){
              isolate(frame);
              if(window===window.top){
                try{var url=new URL(frame.getAttribute('src'),location.href).href;if(!reportedFrames[url]){reportedFrames[url]=true;send('iframeFound',url);}}catch(e){}
              }
              return true;
            }
            return player?isolate(player):false;
          }
          window.__anyanimeFocusPlayer=focus;
          function install(){
            if(!document.documentElement){setTimeout(install,20);return;}
            hideChrome(); focus();
            new MutationObserver(function(){focus();}).observe(document.documentElement,{childList:true,subtree:true});
            var tries=0,timer=setInterval(function(){focus();if(++tries>120)clearInterval(timer);},500);
            setTimeout(function(){var b=document.querySelector('.jw-icon-playback,.play-btn,[class*="play-button"],button[aria-label*="Play"],button[title*="Play"]');if(b)b.click();focus();},1800);
          }
          if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
        })();
        """
    }
}
