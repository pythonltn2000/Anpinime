"""Local-only media fixture: tests iframe extraction, cookies and Referer."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import json
import time

VIDEO = Path(__file__).with_name("sample.mp4").read_bytes()

class Handler(BaseHTTPRequestHandler):
    watch_requests = 0

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
        movie = {"slug": "fixture-movie", "title": {"vi": "Phim kiểm thử"}, "mediaType": "movie"}
        if path == "/api/home":
            self.send_json({"list": [movie], "genres": ["Hành động"]})
            return
        if path == "/api/title/fixture-movie":
            self.send_json({"movie": movie, "episodes": [], "playable": True})
            return
        if path == "/api/watch/fixture-movie":
            Handler.watch_requests += 1
            stream = "/expired.mp4" if Handler.watch_requests == 1 else "/provider.mp4"
            self.send_json({"movie": movie, "episodes": [], "sources": [{"url": stream}]})
            return
        if path == "/danh-sach/phim-moi-cap-nhat-v3":
            self.send_json({"items": [{"slug": "legacy", "name": "Phim4K kiểm thử"}]})
            return
        if path == "/phim/legacy":
            self.send_json({"movie": {"name": "Phim4K kiểm thử"}, "episodes": [{"server_name": "Vietsub", "server_data": [{"name": "01", "link_m3u8": "http://127.0.0.1:8765/legacy.mp4"}]}]})
            return
        if path == "/expired.mp4":
            self.send_error(410, "Fixture URL expired; resolver must refresh once")
            return
        if path in ("/sample.mp4", "/provider.mp4", "/legacy.mp4"):
            if path == "/sample.mp4" and ("smoke_session=1" not in self.headers.get("Cookie", "") or "/embed.html" not in self.headers.get("Referer", "")):
                self.send_error(403, "Fixture requires embed Referer and session cookie")
                return
            if path == "/provider.mp4" and (self.headers.get("X-F4K-PT") != "fixture-ticket" or "movie_session=1" not in self.headers.get("Cookie", "") or "/watch/fixture-movie" not in self.headers.get("Referer", "")):
                self.send_error(403, "Movie fixture requires ticket, cookie and watch Referer")
                return
            start, end = 0, len(VIDEO) - 1
            value = self.headers.get("Range", "")
            if value.startswith("bytes="):
                left, right = value[6:].split("-", 1)
                start = int(left or 0)
                end = min(int(right) if right else end, end)
            self.send_response(206 if value else 200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            if value:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(VIDEO)}")
            self.end_headers()
            self.wfile.write(VIDEO[start:end + 1])
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
