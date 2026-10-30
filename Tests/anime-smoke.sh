#!/bin/bash
set -euo pipefail
ANPINIME_MODE=${1:-fixture}
ANPINIME_RESULT=anime-provider
ANPINIME_FLAG=--anime-provider-smoke
if [ "$ANPINIME_MODE" = live ]; then
  ANPINIME_RESULT=anime-live
  ANPINIME_FLAG=--anime-live-smoke
elif [ "$ANPINIME_MODE" != fixture ]; then
  echo "Usage: bash Tests/anime-smoke.sh [fixture|live]" >&2
  exit 2
fi
ANPINIME_SIMULATOR_ID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"]))')
ANPINIME_APP_DATA=$(xcrun simctl get_app_container "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime data)
mkdir -p previews
python3 - "$ANPINIME_APP_DATA" "$ANPINIME_RESULT" <<'PY'
from pathlib import Path
import sys
for directory in (Path(sys.argv[1])/'Documents', Path('previews')):
    for suffix in ('', '-diagnostics'):
        (directory/('playback-'+sys.argv[2]+suffix+'.json')).unlink(missing_ok=True)
PY

capture_result() {
  xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "previews/$ANPINIME_RESULT.png" || true
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" ]; then
    cp "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" previews/
    cat "previews/playback-$ANPINIME_RESULT-diagnostics.json"
  fi
  if [ "$ANPINIME_MODE" = fixture ] && [ -f "$RUNNER_TEMP/anpinime-anime-server.log" ]; then
    cp "$RUNNER_TEMP/anpinime-anime-server.log" previews/
  fi
}

if [ "$ANPINIME_MODE" = fixture ]; then
  python3 Tests/serve_player.py --anime-provider > "$RUNNER_TEMP/anpinime-anime-server.log" 2>&1 &
  ANPINIME_SERVER_PID=$!
  trap 'kill "$ANPINIME_SERVER_PID" || true' EXIT
  ANPINIME_READY=0
  for attempt in $(seq 1 20); do
    if python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8765),timeout=1); s.close()' 2>/dev/null; then ANPINIME_READY=1; break; fi
    if ! kill -0 "$ANPINIME_SERVER_PID"; then capture_result; exit 1; fi
    sleep 1
  done
  if [ "$ANPINIME_READY" != 1 ]; then capture_result; exit 1; fi
fi

if ! xcrun simctl launch --terminate-running-process "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime "$ANPINIME_FLAG" --mpv-playback-smoke; then
  capture_result
  exit 1
fi
for attempt in $(seq 1 90); do
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" ]; then break; fi
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" ] && python3 -c 'import json,sys; sys.exit(0 if any(e["event"]=="failure" for e in json.load(open(sys.argv[1]))["events"]) else 1)' "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json"; then break; fi
  sleep 1
done
capture_result
if [ ! -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" ]; then
  echo "### $ANPINIME_RESULT: FAIL — no verified anime episode playback" >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi
cp "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" previews/
python3 - "$ANPINIME_RESULT" <<'PY'
import json,sys
r=json.load(open('previews/playback-'+sys.argv[1]+'.json'))
assert r['advancingVideoVerified'] and r['videoWidth']>0 and r['videoHeight']>0 and r['time']>1 and r['landscape'], r
assert r['episodeCount']>=2 and r['selectedEpisodeNumber']==1, r
print(r)
PY
echo "### $ANPINIME_RESULT: PASS — anime episodes and advancing decoded video verified" >> "$GITHUB_STEP_SUMMARY"
