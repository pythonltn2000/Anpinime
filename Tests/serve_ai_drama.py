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
FANTASY = "7628991192537158672"
REVENGE = "7628991193891820560"
SECOND_CHANCE = "7628991193543840769"


def filter_lists():
    """Native four-row metadata, including independent release-time selection."""
    groups = []
    for title, marker, identifier, name in [
            ("Tất cả bối cảnh", "all_settings", FANTASY, "Kỳ ảo"),
            ("Tất cả nhân vật", "all_characters", REVENGE, "Phục thù"),
            ("Tất cả câu chuyện", "all_stories", SECOND_CHANCE, "Cơ hội thứ hai")]:
        groups.append({"category_filters": [
            {"filter_type": 1, "category_id": "0", "name": title, "name_en": marker},
            {"filter_type": 2, "category_id": identifier, "name": name}]})
    groups.append({"category_filters": [
        {"filter_type": 1, "category_id": "0", "name": "Tất cả tác phẩm", "name_en": "all_releases"},
        *[{"filter_type": 3, "category_id": "", "name": f"Trong {days} ngày",
           "recent_days": days} for days in (7, 30)]]})
    return groups


def catalog_row(offset, title):
    return {"collection_id": SERIES_ID + offset, "title": title,
            "description": "Generated portrait test footage. No external film media.",
            "num_videos": EPISODE_COUNT, "num_watched": 120_000 + offset,
            "categories": "Kỳ ảo, Cơ hội thứ hai"}


def pb_varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def pb_field(number, value):
    if isinstance(value, int):
        return pb_varint(number << 3) + pb_varint(value)
    if isinstance(value, str):
        value = value.encode("utf-8")
    return pb_varint(number << 3 | 2) + pb_varint(len(value)) + value


class FixtureState:
    def __init__(self, media_root, identity):
        self.media_root = media_root
        self.identity = identity
        self.lock = threading.Lock()
        self.events = deque(maxlen=512)
        self.started = time.monotonic()
        self.port = None
        self.resolve_gate_armed = False
        self.resolve_gate = threading.Event()
        self.resolve_gate.set()

    def record(self, event, **fields):
        # Never log request queries, headers, cookies, or media contents.
        row = {"event": event, "elapsed": round(time.monotonic() - self.started, 6), **fields}
        with self.lock:
            self.events.append(row)
        print(json.dumps(row, separators=(",", ":")), flush=True)

    def health(self):
        return {"service": SERVICE, "identity": self.identity, "pid": os.getpid(),
                "port": self.port, "episodeCount": EPISODE_COUNT,
                "seriesID": str(SERIES_ID), "fixtureVersion": 2}

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

    def do_POST(self):
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
        if path == "/__smoke__/arm-delayed-resolution" and self.command == "GET":
            # Explicit test control: hold only the next fixture-series episode 2
            # response until episode 3 reaches the server. XCTest/AX latency must
            # not decide whether the stale-response race is actually exercised.
            with self.fixture.lock:
                self.fixture.resolve_gate_armed = True
                self.fixture.resolve_gate.clear()
            self.fixture.record("resolution_gate_armed")
            self.send_json({"armed": True}, head=head)
            return
        if path == "/tiktok/md/mini_drama/category_filter/v1" and self.command == "POST":
            self.send_categories()
            return
        if self.command == "POST":
            self.send_json({"error": "unknown fixture POST route"}, 404)
            return
        if head and not path.startswith("/media/"):
            self.send_json({"error": "GET required"}, 405, head=True)
            return
        if path == "/tiktok/md/mini_drama/feed/v1":
            self.send_short_feed(query)
            return
        if path == "/tiktok/md/mini_drama_center/v1":
            self.send_catalog(query)
            return
        if path == "/tiktok/md/collection/episode_panel/v1":
            series = query.get("collection_id", [""])[0]
            if not self.valid_series(series):
                self.send_json({"status_code": 1}, 404)
                return
            base = self.episode_base(series)
            self.fixture.record("playlist", seriesID=series, count=EPISODE_COUNT)
            # Numeric Int64 IDs deliberately exceed JavaScript's exact-integer range.
            rows = [{"video_id": base + number, "seq_id": number, "num": number,
                     "is_paid": True, "has_purchased": False, "is_limited_free": True}
                    for number in range(1, EPISODE_COUNT + 1)]
            self.send_json({"status_code": 0, "episode_list": rows, "num_videos": EPISODE_COUNT})
            return
        if path == "/tiktok/md/collection/video/v1":
            series = query.get("collection_id", [""])[0]
            base = self.episode_base(series) if self.valid_series(series) else 0
            raw_sequence = query.get("current_seq_id", [""])[0]
            if (not self.valid_series(series)
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
            if number == 3 and raw_id == str(EPISODE_BASE + 3) and not self.fixture.resolve_gate.is_set():
                self.fixture.resolve_gate.set()
                self.fixture.record("resolution_gate_released", episode=number, episodeID=raw_id)
            if number == 2 and raw_id == str(EPISODE_BASE + 2):
                with self.fixture.lock:
                    gated = self.fixture.resolve_gate_armed
                    self.fixture.resolve_gate_armed = False
                if gated:
                    self.fixture.record("resolution_gate_waiting", episode=number, episodeID=raw_id)
                    if not self.fixture.resolve_gate.wait(timeout=20):
                        self.fixture.record("resolution_gate_timeout", episode=number, episodeID=raw_id)
                else:
                    time.sleep(4)
            elif number == 2 or (number == 3 and raw_id == "7000000000000000203"):
                time.sleep(4)
            url = f"http://127.0.0.1:{self.fixture.port}/media/episode-{number:02d}.mp4?clip_id={raw_id}"
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

    @staticmethod
    def valid_series(series):
        return series.isdecimal() and SERIES_ID <= int(series) < SERIES_ID + 10_000

    @staticmethod
    def episode_base(series):
        return EPISODE_BASE + (int(series) - SERIES_ID) * 100

    def bad_catalog_request(self):
        self.fixture.record("invalid_catalog_request", method=self.command)
        self.send_json({"status_code": 1, "error": "invalid native catalog contract"}, 400)

    def send_short_feed(self, query):
        loaded = query.get("drama_current_items", [""])[0]
        first_ids = [str(EPISODE_BASE + number + index * 100) for index, number in enumerate((5, 3, 40, 1, 3, 1))]
        page = 1 if not loaded else 2
        if (query.get("count") != ["6"] or loaded not in ("", ",".join(first_ids))
                or query.get("drama_request_type") != ["init_fetch" if page == 1 else "load_more"]
                or query.get("item_count_in_session") != ["0" if page == 1 else "6"]):
            self.bad_catalog_request()
            return
        self.fixture.record("short_feed", page=page)
        rows = []
        for index, number in (list(enumerate((5, 3, 40, 1, 3, 1))) if page == 1 else [(6, 40), (7, 1), (8, 3), (9, 1), (10, 40), (11, 3)]):
            series = SERIES_ID + index
            video = EPISODE_BASE + index * 100 + number
            paid = (pb_field(1, series) + pb_field(3, number) + pb_field(13, f"Short Feed Fixture {index + 1}")
                    + pb_field(25, 1) + pb_field(31, json.dumps({"video_total_nums": EPISODE_COUNT})))
            media = pb_field(4, 640 if number == 5 else 360) + pb_field(3, 360 if number == 5 else 640)
            rows.append(pb_field(4, pb_field(1, str(video)) + pb_field(317, paid) + pb_field(7, media)))
        body = pb_field(1, 0) + pb_field(3, int(page == 1)) + b"".join(rows)
        self.send_response(200)
        self.send_header("Content-Type", "application/x-protobuf")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_catalog(self, query):
        scene = query.get("scene", [""])[0]
        cursor = query.get("cursor", [""])[0]
        if query.get("category_id") != ["0"] or scene not in ("1", "6", "7", "8"):
            self.bad_catalog_request()
            return
        if query.get("count") != ["14" if scene == "1" else "12"]:
            self.bad_catalog_request()
            return
        feed, offset = {"1": ("home", 0), "6": ("hot", 1000),
                        "7": ("latest", 2000), "8": ("new", 3000)}[scene]
        if scene == "1":
            loaded = query.get("drama_current_collections", [""])[0]
            page = 1 if not loaded else 2
            expected = ",".join(str(SERIES_ID + n) for n in range(6)) if page == 2 else ""
            if (cursor or loaded != expected
                    or query.get("drama_request_type") != ["init_fetch" if page == 1 else "load_more"]
                    or query.get("collection_count_in_session") != ["0" if page == 1 else "6"]):
                self.bad_catalog_request()
                return
        else:
            if cursor not in ("", f"fixture-{feed}:2"):
                self.bad_catalog_request()
                return
            page = 1 if not cursor else 2
        count = 6 if scene == "1" else 12
        self.fixture.record("catalog_started", feed=feed, page=page)
        # A real in-flight socket response lets the UI prove ranking changes are isolated.
        if feed == "hot":
            time.sleep(4)
        rows = [catalog_row(offset + n, "AI Drama Fixture" if offset + n == 0 else f"{feed.title()} Fixture {n + 1}")
                for n in range(0 if page == 1 else count, count if page == 1 else count + 4)]
        try:
            self.send_json({"status_code": 0, "collections": rows, "has_more": page == 1,
                            "cursor": f"fixture-{feed}:2" if page == 1 and scene != "1" else ""})
        finally:
            self.fixture.record("catalog_finished", feed=feed, page=page)

    def send_categories(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 16_384 or self.headers.get("Agw-Js-Conv") != "str":
                raise ValueError()
            if not self.headers.get("Content-Type", "").startswith("application/json"):
                raise ValueError()
            payload = json.loads(self.rfile.read(size))
            if set(payload) != {"category_filters", "cursor", "count"} or payload["count"] != 12:
                raise ValueError()
            filters = payload["category_filters"]
            if not isinstance(filters, list) or len(filters) not in (0, 4):
                raise ValueError()
            categories, days = [], 0
            for index, selection in enumerate(filters):
                # The shipped client posts the entire selected object from every row,
                # including the native "all" option and its descriptive fields.
                if selection not in filter_lists()[index]["category_filters"]:
                    raise ValueError()
                if selection["filter_type"] == 2:
                    categories.append(selection["category_id"])
                elif selection["filter_type"] == 3:
                    days = selection["recent_days"]
            if len(categories) != len(set(categories)):
                raise ValueError()
            mask = sum(1 << index for index, value in enumerate((FANTASY, REVENGE, SECOND_CHANCE)) if value in categories)
            signature = f"{mask}-{days}"
            cursor = payload["cursor"]
            if cursor not in ("", f"fixture-category-{signature}:2"):
                raise ValueError()
        except (ValueError, TypeError, KeyError, json.JSONDecodeError):
            self.bad_catalog_request()
            return
        page = 1 if not cursor else 2
        self.fixture.record("catalog_started", feed="category", page=page, mask=mask, days=days)
        # Selecting another row while Fantasy alone resolves exercises stale-result rejection.
        if mask == 1 and days == 0:
            time.sleep(4)
        offset = 4000 + mask * 100 + days
        rows = [catalog_row(offset + n, f"Category {signature} Fixture {n + 1}")
                for n in range(0 if page == 1 else 12, 12 if page == 1 else 16)]
        try:
            self.send_json({"status_code": 0, "collections": rows,
                            "category_filter_lists": filter_lists(), "has_more": page == 1,
                            "cursor": f"fixture-category-{signature}:2" if page == 1 else ""})
        finally:
            self.fixture.record("catalog_finished", feed="category", page=page, mask=mask, days=days)

    def send_media(self, episode, head):
        clip = episode if episode in (3, 5, 40) else 1
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
                            partial=bool(range_header), episodeID=parse_qs(urlsplit(self.path).query).get("clip_id", [""])[0])
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
            self.fixture.record("media_complete", episode=episode, episodeID=parse_qs(urlsplit(self.path).query).get("clip_id", [""])[0], complete=start == 0 and end == size - 1)

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
    for episode in (1, 3, 5, 40):
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
