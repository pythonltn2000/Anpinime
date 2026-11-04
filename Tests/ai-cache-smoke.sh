#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

ANPINIME_SWIFTC=${ANPINIME_SWIFTC:-swiftc}
ANPINIME_TEMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/anpinime-ai-cache.XXXXXX")
ANPINIME_ARTIFACTS="$PWD/previews/ai-cache-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ANPINIME_SERVER_PID=""
ANPINIME_IDENTITY=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
mkdir -p "$ANPINIME_TEMP/media" "$ANPINIME_ARTIFACTS"
cache_cleanup() {
  ANPINIME_STATUS=$?
  trap - EXIT
  if [ -n "$ANPINIME_SERVER_PID" ]; then
    kill "$ANPINIME_SERVER_PID" 2>/dev/null || true
    wait "$ANPINIME_SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$ANPINIME_TEMP"
  echo "AI media cache artifacts: $ANPINIME_ARTIFACTS"
  exit "$ANPINIME_STATUS"
}
trap cache_cleanup EXIT

ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=96x160:rate=10 \
  -t 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -movflags +faststart "$ANPINIME_TEMP/media/episode-01.mp4"
python3 - "$ANPINIME_TEMP/media" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
movie = (root / 'episode-01.mp4').read_bytes()
(root / 'episode-05.mp4').write_bytes(movie)
with (root / 'episode-03.mp4').open('wb') as oversized:
    oversized.write(movie)
    oversized.truncate(25 * 1024 * 1024)
(root / 'episode-40.mp4').write_text('<html>Temporarily unavailable</html>', encoding='utf-8')
PY

python3 -u Tests/serve_ai_drama.py --media-root "$ANPINIME_TEMP/media" --port 0 \
  --identity "$ANPINIME_IDENTITY" --ready-file "$ANPINIME_TEMP/ready.json" \
  > "$ANPINIME_ARTIFACTS/server.log" 2>&1 &
ANPINIME_SERVER_PID=$!
ANPINIME_AI_CACHE_URL=$(python3 - "$ANPINIME_TEMP/ready.json" "$ANPINIME_IDENTITY" <<'PY'
import json
from pathlib import Path
import sys
import time
from urllib.request import ProxyHandler, build_opener
ready = Path(sys.argv[1])
for _ in range(100):
    try:
        state = json.loads(ready.read_text())
        url = f"http://127.0.0.1:{state['port']}/"
        with build_opener(ProxyHandler({})).open(url + '__smoke__/health', timeout=1) as response:
            health = json.load(response)
        if health['identity'] != sys.argv[2]:
            raise RuntimeError('Wrong fixture instance')
        print(url)
        break
    except (OSError, ValueError, KeyError):
        time.sleep(.05)
else:
    raise SystemExit('Cache media fixture did not start')
PY
)
export ANPINIME_AI_CACHE_URL
"$ANPINIME_SWIFTC" -swift-version 5 -parse-as-library AnyAnime/AIDrama/AIDramaModels.swift \
  AnyAnime/AIDrama/AIDramaMediaCache.swift Tests/AIDramaMediaCacheTests.swift -o "$ANPINIME_TEMP/cache-tests"
"$ANPINIME_TEMP/cache-tests" | tee "$ANPINIME_ARTIFACTS/result.log"
python3 - "$ANPINIME_AI_CACHE_URL" "$ANPINIME_ARTIFACTS/fixture-stats.json" <<'PY'
import json
from pathlib import Path
import sys
from urllib.request import ProxyHandler, build_opener
with build_opener(ProxyHandler({})).open(sys.argv[1] + '__smoke__/stats', timeout=2) as response:
    stats = json.load(response)
Path(sys.argv[2]).write_text(json.dumps(stats, indent=2), encoding='utf-8')
completed = {e.get('episodeID') for e in stats['events'] if e['event'] == 'media_complete' and e.get('complete')}
assert {f'clip-{n}' for n in range(1, 11)} <= completed, 'The server did not deliver ten complete movies'
assert 'oversized' not in completed, 'The oversized fixture unexpectedly fit inside the download limit'
print('PASS: Server confirms ten complete media transfers and a bounded oversized range')
PY
