#!/usr/bin/env python3
"""Loopback-only PineDrama wire fixture and generated portrait media for UI tests."""

import argparse
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import socketserver
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid


SERIES_ID = 7000000000000000001
EPISODE_BASE = 7000000000000000100
EPISODE_COUNT = 40
SERVICE = "anpinime-ai-drama-fixture"


class FixtureState:
    def __init__(self, media_root, identity):
        self.media_root = media_root
        self.identity = identity
        self.lock = threading.Lock()
        self.events = deque(maxlen=512)
        self.started = time.monotonic()
        self.port = None

    def record(self, event, **fields):
        # Never log request queries, headers, cookies, or media contents.
        row = {"event": event, "elapsed": round(time.monotonic() - self.started, 3), **fields}
        with self.lock:
            self.events.append(row)
        print(json.dumps(row, separators=(",", ":")), flush=True)

    def health(self):
        return {"service": SERVICE, "identity": self.identity, "pid": os.getpid(),
                "port": self.port, "episodeCount": EPISODE_COUNT,
                "seriesID": str(SERIES_ID), "fixtureVersion": 1}

    def snapshot(self):
        with self.lock:
            events = list(self.events)
        return {**self.health(), "events": events}


class NumericLoopbackServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False
    allow_reuse_address = True

    def server_bind(self):
        # HTTPServer.server_bind calls getfqdn; neither binding nor logs need DNS.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    @property
    def fixture(self):
        return self.server.fixture

    def address_string(self):
        return self.client_address[0]

    def log_message(self, format, *args):
        pass

    def send_json(self, value, status=200, head=False):
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def do_HEAD(self):
        self.handle_request(head=True)

    def do_GET(self):
        self.handle_request()

    def handle_request(self, head=False):
        try:
            self.route(head)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Cancellation is an expected part of the rapid-swipe test.
            pass

    def route(self, head):
        request = urlsplit(self.path)
        path = request.path.rstrip("/")
        query = parse_qs(request.query, keep_blank_values=True)
        if path == "/__smoke__/health":
            self.send_json(self.fixture.health(), head=head)
            return
        if path == "/__smoke__/stats":
            # A bounded wait avoids racing the app's resolving flag with its socket write.
            event = query.get("wait_for", [""])[0]
            episode = query.get("episode", [""])[0]
            if event in ("resolve_started", "resolve_finished") and episode.isdecimal():
                deadline = time.monotonic() + 1
                while time.monotonic() < deadline:
                    if any(row.get("event") == event and row.get("episode") == int(episode)
                           for row in self.fixture.snapshot()["events"]):
                        break
                    time.sleep(0.01)
            self.send_json(self.fixture.snapshot(), head=head)
            return
        if head and not path.startswith("/media/"):
            self.send_json({"error": "GET required"}, 405, head=True)
            return
        if path == "/tiktok/md/mini_drama_center/v1":
            cursor = query.get("cursor", [""])[0]
            if cursor not in ("", "fixture-page-2"):
                self.send_json({"status_code": 1, "error": "unknown cursor"}, 400)
                return
            page = 1 if not cursor else 2
            self.fixture.record("catalog", page=page)
            self.send_json({"status_code": 0, "collections": [{
                "collection_id": SERIES_ID + page - 1,
                "title": "AI Drama Fixture" if page == 1 else "AI Drama Fixture Two",
                "description": "Generated portrait test footage. No external film media.",
                "num_videos": EPISODE_COUNT,
            }], "has_more": page == 1, "cursor": "fixture-page-2" if page == 1 else ""})
            return
        if path == "/tiktok/md/collection/episode_panel/v1":
            series = query.get("collection_id", [""])[0]
            if series not in (str(SERIES_ID), str(SERIES_ID + 1)):
                self.send_json({"status_code": 1}, 404)
                return
            base = EPISODE_BASE if series == str(SERIES_ID) else EPISODE_BASE + 100
            self.fixture.record("playlist", seriesID=series, count=EPISODE_COUNT)
            # Numeric Int64 IDs deliberately exceed JavaScript's exact-integer range.
            rows = [{"video_id": base + number, "seq_id": number, "num": number,
                     "is_paid": True, "has_purchased": False, "is_limited_free": True}
                    for number in range(1, EPISODE_COUNT + 1)]
            self.send_json({"status_code": 0, "episode_list": rows, "num_videos": EPISODE_COUNT})
            return
        if path == "/tiktok/md/collection/video/v1":
            series = query.get("collection_id", [""])[0]
            base = EPISODE_BASE if series == str(SERIES_ID) else EPISODE_BASE + 100
            raw_sequence = query.get("current_seq_id", [""])[0]
            if (series not in (str(SERIES_ID), str(SERIES_ID + 1))
                    or not raw_sequence.isdecimal() or not 1 <= int(raw_sequence) <= EPISODE_COUNT
                    or query.get("query_type") != ["seq_id"]
                    or query.get("root_scene") != ["2"]
                    or query.get("drama_request_type") != ["load_more"]
                    or query.get("need_collection_detail") != ["0"]):
                self.send_json({"status_code": 1}, 404)
                return
            number = int(raw_sequence)
            raw_id = str(base + number)
            self.fixture.record("resolve_started", episode=number, episodeID=raw_id)
            if number == 2:
                time.sleep(4)
            url = f"http://127.0.0.1:{self.fixture.port}/media/episode-{number:02d}.mp4"
            payload = {"status_code": 0, "collection": {"collection_id": int(series)},
                       "num_videos": EPISODE_COUNT, "paid_videos": [{
                           "paid_video_id": int(raw_id), "seq_id": number,
                           "is_limited_free": True,
                           "aweme": {"aweme_id": raw_id, "video": {
                               "play_addr": {"url_list": [url]}, "width": 360, "height": 640,
                           }},
                       }]}
            try:
                self.send_json(payload)
            finally:
                self.fixture.record("resolve_finished", episode=number, episodeID=raw_id)
            return
        match = re.fullmatch(r"/media/episode-(\d{2})\.mp4", path)
        if match and 1 <= int(match[1]) <= EPISODE_COUNT:
            self.send_media(int(match[1]), head)
            return
        self.fixture.record("unknown_route", method=self.command)
        self.send_json({"error": "unknown fixture route"}, 404, head=head)

    def send_media(self, episode, head):
        clip = episode if episode in (3, 40) else 1
        media = self.fixture.media_root / f"episode-{clip:02d}.mp4"
        size = media.stat().st_size
        start, end = 0, size - 1
        range_header = self.headers.get("Range")
        if range_header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header.strip())
            if not match or not any(match.groups()):
                self.send_range_error(size)
                return
            left, right = match.groups()
            if left:
                start = int(left)
                end = min(int(right), end) if right else end
            else:
                start = max(0, size - int(right))
            if start > end or start >= size:
                self.send_range_error(size)
                return
        self.send_response(206 if range_header else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-store")
        if range_header:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        self.fixture.record("media", episode=episode, clip=clip, method=self.command,
                            partial=bool(range_header))
        if not head:
            with media.open("rb") as stream:
                stream.seek(start)
                remaining = end - start + 1
                while remaining:
                    chunk = stream.read(min(64 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)

    def send_range_error(self, size):
        self.send_response(416)
        self.send_header("Content-Range", f"bytes */{size}")
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8768)
    parser.add_argument("--media-root", type=Path, required=True)
    parser.add_argument("--identity", default=None)
    parser.add_argument("--ready-file", type=Path)
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 and 65535")
    for episode in (1, 3, 40):
        if not (args.media_root / f"episode-{episode:02d}.mp4").is_file():
            parser.error(f"missing generated clip for episode {episode}")
    state = FixtureState(args.media_root.resolve(), args.identity or uuid.uuid4().hex)
    with NumericLoopbackServer(("127.0.0.1", args.port), Handler) as server:
        server.fixture = state
        state.port = server.server_address[1]
        if args.ready_file:
            temporary = args.ready_file.with_name(args.ready_file.name + f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps(state.health()), encoding="utf-8")
            temporary.replace(args.ready_file)
        state.record("ready", **state.health())
        server.serve_forever(poll_interval=0.1)


if __name__ == "__main__":
    main()
