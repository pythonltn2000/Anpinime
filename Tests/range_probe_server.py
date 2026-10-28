"""A virtual 12 GB resource. Never stores the file and stops when a client closes."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

TOTAL = 12_285_989_889
MAGIC = b'\x00\x00\x00\x18ftypisom'
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_HEAD(self):
        self.send_response(405); self.end_headers()
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/redirect':
            self.send_response(302); self.send_header('Location', '/range'); self.end_headers(); return
        if path == '/denied':
            self.send_response(403); self.end_headers(); return
        if path == '/json':
            body=b'{"error":"not media"}'
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
        value = self.headers.get('Range', '')
        start, end = 0, TOTAL-1
        if value.startswith('bytes=') and path != '/ignore':
            left, right = value[6:].split('-',1)
            if left: start = int(left); end = min(int(right),end) if right else end
            else: start = max(0, TOTAL-int(right))
            if start >= TOTAL or start > end:
                self.send_response(416); self.send_header('Content-Range',f'bytes */{TOTAL}'); self.end_headers(); return
            self.send_response(206); self.send_header('Content-Range',f'bytes {start}-{end}/{TOTAL}')
        else: self.send_response(200)
        self.send_header('Content-Type','application/octet-stream')
        self.send_header('Content-Length',str(end-start+1))
        self.send_header('Accept-Ranges','bytes')
        self.end_headers()
        try:
            cursor=start
            while cursor<=end:
                length=min(8192,end-cursor+1)
                chunk=bytearray((i%251 for i in range(cursor,cursor+length)))
                if cursor < len(MAGIC):
                    for i in range(min(length,len(MAGIC)-cursor)): chunk[i]=MAGIC[cursor+i]
                self.wfile.write(chunk); self.wfile.flush(); cursor+=length
        except (BrokenPipeError,ConnectionResetError): pass
ThreadingHTTPServer(('127.0.0.1',8766), Handler).serve_forever()
