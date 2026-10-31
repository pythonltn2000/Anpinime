"""Local-only media fixture: tests iframe extraction, cookies and Referer."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import json
import time
import base64
import sys

SOURCE2_HLS = "--source2-hls" in sys.argv
ANIME_PROVIDER = "--anime-provider" in sys.argv

VIDEO = Path(__file__).with_name("sample.mp4").read_bytes()
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==")

class Handler(BaseHTTPRequestHandler):
    watch_requests = 0

    def send_html(self, body):
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Set-Cookie", "smoke_session=1; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, value, cookie=False):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", "movie_session=1; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == "/api/play-ticket":
            self.send_json({"token": "fixture-ticket", "expires": int(time.time() * 1000) + 180000}, cookie=True)
        else:
            self.send_error(404)

    def do_GET(self):
        path = urlsplit(self.path).path
        if ANIME_PROVIDER:
            if path == "/":
                self.send_html('''<!doctype html><html><head><title>Anime fixture</title></head><body>
                    <section><h2>Anime mới cập nhật</h2><article class="TPost">
                    <a href="/phim/fixture-a1/"><img src="/poster.png" alt="Anime kiểm thử"></a>
                    <h2 class="Title">Anime kiểm thử</h2></article></section></body></html>''')
                return
            if path == "/poster.png":
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(PNG)))
                self.end_headers()
                self.wfile.write(PNG)
                return
            if path == "/phim/fixture-a1/":
                self.send_html('''<!doctype html><html><head><title>Anime kiểm thử</title>
                    <meta property="og:image" content="/poster.png"></head><body>
                    <h1>Anime kiểm thử</h1><div class="Description">Metadata appears before the episode list.</div>
                    <a class="watch-now" href="/phim/fixture-a1/xem-phim.html">Xem phim</a>
                    </body></html>''')
                return
            if path == "/phim/fixture-a1/xem-phim.html":
                self.send_html('''<!doctype html><html><head><title>Xem Anime kiểm thử</title></head><body>
                    <h1>Anime kiểm thử</h1><div class="server-item" data-server="Vietsub">
                    <a href="/phim/fixture-a1/tap-1-101.html">Tập 1</a></div>
                    <script>setTimeout(function(){
                      var episode=document.createElement('a');
                      episode.href='/phim/fixture-a1/tap-2-102.html';
                      episode.textContent='Tập 2';
                      document.querySelector('.server-item').appendChild(episode);
                    },3500);</script>
                    <div class="comments"><a href="/phim/fixture-a1/tap-99-999.html">Tập 99</a></div>
                    <nav><a href="/phim/fixture-a1/tap-88-888.html">Tập 88</a></nav>
                    <a href="/phim/unrelated-a2/tap-1-201.html">Tập 1</a>
                    <a href="/dang-nhap?redirect=/phim/fixture-a1/tap-1-101.html">Đăng nhập</a>
                    </body></html>''')
                return
            if path in ("/phim/fixture-a1/tap-1-101.html", "/phim/fixture-a1/tap-2-102.html"):
                self.send_html('''<!doctype html><html><head><meta name="viewport" content="width=device-width"></head>
                    <body><header>Anime fixture player</header><iframe src="/embed.html" width="640" height="360"
                    allow="autoplay; fullscreen"></iframe></body></html>''')
                return
        movie = {"slug": "fixture-movie", "title": {"vi": "Phim kiểm thử"}, "mediaType": "movie"}
        if path == "/api/home":
            self.send_json({"list": [movie], "genres": ["Hành động"]})
            return
        if path == "/api/title/fixture-movie":
            self.send_json({"movie": movie, "episodes": [], "playable": True})
            return
        if path == "/api/watch/fixture-movie":
            Handler.watch_requests += 1
            stream = "/expired.mp4" if Handler.watch_requests == 1 else "/wrapped/master.m3u8"
            self.send_json({"movie": movie, "episodes": [], "sources": [{"url": stream}]})
            return
        if path == "/danh-sach/phim-moi-cap-nhat-v3":
            self.send_json({"items": [{"slug": "legacy", "name": "Phim4K kiểm thử"}]})
            return
        if path == "/phim/legacy":
            row = {"name": "01", "link": "http://127.0.0.1:8765/api/content/stream/hls?fixture=1"} if SOURCE2_HLS else {"name": "01", "link_m3u8": "http://127.0.0.1:8765/legacy.mp4"}
            self.send_json({"movie": {"name": "Phim4K kiểm thử"}, "episodes": [{"server_name": "Vietsub", "server_data": [row]}]})
            return
        if SOURCE2_HLS and (path == "/api/content/stream/hls" or path.startswith("/source2-hls/")):
            if self.headers.get("User-Agent") != "oxoo" or any(self.headers.get(key) for key in ("Origin", "Referer", "API-KEY", "Authorization", "Cookie")):
                self.send_error(403, "Source 2 media requires its original header map")
                return
            name = "index.m3u8" if path == "/api/content/stream/hls" else path.removeprefix("/source2-hls/")
            if name != "index.m3u8" and ("/" in name or not name.endswith(".ts")):
                self.send_error(404)
                return
            data = Path(__file__).with_name("source2-hls").joinpath(name).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.apple.mpegurl" if name.endswith("m3u8") else "video/mp2t")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/expired.mp4":
            self.send_error(410, "Fixture URL expired; resolver must refresh once")
            return
        if path.startswith("/wrapped/"):
            if self.headers.get("X-F4K-PT") != "fixture-ticket" or "movie_session=1" not in self.headers.get("Cookie", "") or "/watch/fixture-movie" not in self.headers.get("Referer", ""):
                self.send_error(403, "HLS requires ticket, cookie and watch Referer")
                return
            name = path.removeprefix("/wrapped/")
            if name == "master.m3u8":
                data = b'#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",AUTOSELECT=YES,URI="en.m3u8"\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Vietnamese",LANGUAGE="vi",AUTOSELECT=YES,URI="vi.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=320x180,CODECS="avc1.42c00c,mp4a.40.2",SUBTITLES="subs"\nmedia.m3u8\n'
                content_type = "application/vnd.apple.mpegurl"
            elif name in ("en.m3u8", "vi.m3u8"):
                data = (f'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:8\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:8,\n{name[:2]}.vtt\n#EXT-X-ENDLIST\n').encode()
                content_type = "application/vnd.apple.mpegurl"
            elif name in ("en.vtt", "vi.vtt"):
                data = ("WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n00:00:00.000 --> 00:00:08.000\n" + ("Phụ đề kiểm thử" if name == "vi.vtt" else "Subtitle test") + "\n").encode()
                content_type = "text/vtt"
            elif name == "media.m3u8":
                data = Path(__file__).with_name("wrapped-hls").joinpath(name).read_bytes()
                content_type = "application/vnd.apple.mpegurl"
            elif name in ("init.mp4", "media0.m4s", "media1.m4s"):
                data = PNG + Path(__file__).with_name("wrapped-hls").joinpath(name).read_bytes()
                content_type = "image/png"
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path in ("/sample.mp4", "/provider.mp4", "/legacy.mp4", "/multitrack.mkv"):
            media = Path(__file__).with_name("multitrack.mkv").read_bytes() if path == "/multitrack.mkv" else VIDEO
            if path == "/sample.mp4" and ("smoke_session=1" not in self.headers.get("Cookie", "") or "/embed.html" not in self.headers.get("Referer", "")):
                self.send_error(403, "Fixture requires embed Referer and session cookie")
                return
            if path == "/provider.mp4" and (self.headers.get("X-F4K-PT") != "fixture-ticket" or "movie_session=1" not in self.headers.get("Cookie", "") or "/watch/fixture-movie" not in self.headers.get("Referer", "")):
                self.send_error(403, "Movie fixture requires ticket, cookie and watch Referer")
                return
            start, end = 0, len(media) - 1
            value = self.headers.get("Range", "")
            if value.startswith("bytes="):
                left, right = value[6:].split("-", 1)
                start = int(left or 0)
                end = min(int(right) if right else end, end)
            self.send_response(206 if value else 200)
            self.send_header("Content-Type", "video/x-matroska" if path.endswith(".mkv") else "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            if value:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(media)}")
            self.end_headers()
            self.wfile.write(media[start:end + 1])
            return
        if self.path == "/embed.html":
            body = '<html><head><meta name="viewport" content="width=device-width"></head><body style="margin:0;background:black"><video playsinline autoplay preload="auto" src="/sample.mp4" style="width:100vw;height:100vh"></video></body></html>'
        else:
            body = '<html><head><meta name="viewport" content="width=device-width"></head><body><header>Fixture header</header><iframe src="/embed.html" width="640" height="360" allow="autoplay; fullscreen"></iframe></body></html>'
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Set-Cookie", "smoke_session=1; Path=/; SameSite=Lax")
        self.end_headers()
        self.wfile.write(data)

HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
