"""Bounded public transport observations. This does not verify video playback.

Uses the app's documented samples and public client header. Never signs URLs,
changes a host, uses an account session or substitutes another provider.
"""
import json
import pathlib
import urllib.error
import urllib.parse
import urllib.request

AGENT = "Dart/3.12 (dart:io)"
FREE = "https://free.cryboiz.workers.dev"
CORE = "https://api.phim4k.space"
observations = {"playbackVerified": False, "scope": "network prefixes only", "requests": []}


def read(label, url, *, headers=None, limit=2048):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, **(headers or {})})
    entry = {"label": label, "host": urllib.parse.urlsplit(url).hostname}
    try:
        try:
            response = urllib.request.urlopen(request, timeout=12)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(limit)
            entry.update(status=response.status, contentType=response.headers.get("Content-Type", ""), bytesRead=len(body))
            entry["signature"] = ("hls" if body.startswith(b"#EXTM3U") else "ts" if body[:1] == b"G" else
                                  "mkv" if body.startswith(bytes.fromhex("1a45dfa3")) else "other")
        observations["requests"].append(entry)
        return body if entry["status"] == 200 else None
    except Exception as error:
        # Error strings can contain URLs with credentials or signed queries.
        entry["errorType"] = type(error).__name__
        observations["requests"].append(entry)
        return None


def object(body):
    try:
        value = json.loads(body or b"")
        return value if isinstance(value, dict) else {}
    except (ValueError, UnicodeError):
        return {}


detail = object(read("Free1 sample detail", FREE + "/phim/thuong-nguyen-do", limit=262144))
groups = detail.get("episodes", [])
if groups and groups[0].get("server_data"):
    row = groups[0]["server_data"][0]
    url = next((row[key] for key in ["link_m3u8", "m3u8", "stream_url", "video_url", "file_url", "link"] if row.get(key)), None)
    if url and urllib.parse.urlsplit(url).scheme == "https":
        headers = {"User-Agent": "oxoo"}
        manifest = read("Free1 original manifest", url, headers=headers, limit=65536)
        if manifest and manifest.startswith(b"#EXTM3U"):
            lines = manifest.decode("utf-8").splitlines()
            for index, segment in enumerate([line.strip() for line in lines if line.strip() and not line.startswith("#")][:2]):
                segment = urllib.parse.urljoin(url, segment)
                if urllib.parse.urlsplit(segment).scheme == "https":
                    read("Free1 segment " + str(index), segment, headers={**headers, "Range": "bytes=0-2047"})

detail = object(read("Core Wakanda detail", CORE + "/rest-api/v130/single_details?type=movie&id=10403",
                     headers={"API-KEY": "bbbb411dea44849"}, limit=262144))
videos = detail.get("videos", [])
observations["coreServerIDs"] = [row.get("video_file_id") for row in videos]
if videos:
    url = next((row.get("file_url") for row in videos if row.get("video_file_id") == "31937"), None)
    if url and urllib.parse.urlsplit(url).scheme == "https":
        read("Core virtual URL before gateway exchange (not resolved playback)", url, headers={"User-Agent": "exoplayer", "Range": "bytes=0-2047"})

pathlib.Path("previews").mkdir(exist_ok=True)
pathlib.Path("previews/source2-live-network.json").write_text(json.dumps(observations, indent=2))
print(json.dumps(observations, indent=2))
