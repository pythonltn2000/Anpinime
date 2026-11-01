"""Replay the exact captured Core 10403 metadata; media and gateway stay live.

Numeric loopback only. No signed URLs, stream keys, account fields or gateway
responses are served here. The simulator uses the production provider/resolver.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
import hashlib
import json
import os
import socketserver

FIXTURE = Path(__file__).with_name("Fixtures") / "phim4k-original-core-metadata.json"
BODY = FIXTURE.read_bytes()
METADATA = json.loads(BODY)
EXPECTED_IDS = {"31937", "33090", "27463", "31938", "31939"}
assert set(METADATA) == {"videos_id", "title", "videos"}
assert METADATA["videos_id"] == "10403"
assert len(METADATA["videos"]) == 5
assert {row["video_file_id"] for row in METADATA["videos"]} == EXPECTED_IDS
for row in METADATA["videos"]:
    assert set(row) == {"video_file_id", "label", "file_type", "file_url"}
    source = urlsplit(row["file_url"])
    assert source.scheme == "https" and source.hostname == "cdn.phim4k.lol"
    assert not source.query and not source.fragment and not source.username and not source.password


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        request = urlsplit(self.path)
        if request.path == "/__health" and not request.query:
            health = {"service": "anpinime-core-metadata", "pid": os.getpid(),
                      "movieID": "10403", "metadataSHA256": hashlib.sha256(BODY).hexdigest()}
            self.send_json(200, json.dumps(health).encode())
        elif request.path == "/rest-api/v130/single_details" and parse_qs(request.query) == {"type": ["movie"], "id": ["10403"]}:
            self.send_json(200, BODY)
        else:
            self.send_json(404, b'{"error":"captured Core route unavailable"}')


class CoreMetadataServer(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer.server_bind calls getfqdn even for a numeric address.
        # This local fixture must never wait for reverse DNS during startup.
        socketserver.TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]


def main():
    print("CORE_METADATA_STARTUP pid=" + str(os.getpid()) + " bind=127.0.0.1:8767", flush=True)
    server = CoreMetadataServer(("127.0.0.1", 8767), Handler)
    print("CORE_METADATA_READY pid=" + str(os.getpid()) + " movieID=10403", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
