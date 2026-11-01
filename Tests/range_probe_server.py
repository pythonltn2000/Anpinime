"""A virtual 12 GB resource. Never stores the file and stops when a client closes."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
from pathlib import Path
import json
import os

TOTAL = 12_285_989_889
MAGIC = b'\x00\x00\x00\x18ftypisom'
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_HEAD(self):
        self.send_response(405); self.end_headers()
    def do_GET(self):
        path = urlsplit(self.path).path
        print(json.dumps({'event':'request', 'method':'GET', 'path':path,
                          'range':self.headers.get('Range','')}), flush=True)
        if path == '/health':
            body=json.dumps({'server':'AnPinime.RangeFixture', 'pid':os.getpid(),
                             'port':self.server.server_port}).encode()
            self.send_response(200); self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
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
        print(json.dumps({'event':'response-finished', 'path':path, 'bytesWritten':cursor-start}), flush=True)

server=ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('ANPINIME_RANGE_PORT','8766'))), Handler)
ready={'server':'AnPinime.RangeFixture', 'host':'127.0.0.1', 'port':server.server_port, 'pid':os.getpid()}
if os.environ.get('ANPINIME_RANGE_READY_FILE'):
    ready_path=Path(os.environ['ANPINIME_RANGE_READY_FILE'])
    ready_path.parent.mkdir(parents=True,exist_ok=True)
    temporary=ready_path.with_name(ready_path.name+'.tmp')
    temporary.write_text(json.dumps(ready)+'\n')
    temporary.replace(ready_path)
print(json.dumps({'event':'ready', **ready}), flush=True)
server.serve_forever()
