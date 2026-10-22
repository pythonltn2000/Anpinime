"""Local-only media fixture: tests iframe extraction, cookies and Referer."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

VIDEO = Path(__file__).with_name("sample.mp4").read_bytes()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/sample.mp4":
            if "smoke_session=1" not in self.headers.get("Cookie", "") or "/embed.html" not in self.headers.get("Referer", ""):
                self.send_error(403, "Fixture requires embed Referer and session cookie")
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
