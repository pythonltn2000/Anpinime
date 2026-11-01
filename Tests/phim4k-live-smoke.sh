#!/bin/bash
set -euo pipefail
ANPINIME_MODE=${1:-live}
ANPINIME_RESULT=phim4k-live
ANPINIME_FLAG=--phim4k-live-smoke
cleanup() {
  if [ -n "${ANPINIME_SIMULATOR_ID:-}" ]; then
    xcrun simctl terminate "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime >/dev/null 2>&1 || true
  fi
  if [ -n "${ANPINIME_SERVER_PID:-}" ]; then
    kill "$ANPINIME_SERVER_PID" || true
    wait "$ANPINIME_SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
if [ "$ANPINIME_MODE" = vip ]; then
  ANPINIME_RESULT=phim4k-vip
  ANPINIME_FLAG=--phim4k-vip-smoke
fi
if [ "$ANPINIME_MODE" = gateway ]; then
  ANPINIME_RESULT=phim4k-gateway
  ANPINIME_FLAG=--phim4k-gateway-smoke
  python3 -u Tests/serve_core_metadata.py > "$RUNNER_TEMP/anpinime-core-metadata-server.log" 2>&1 &
  ANPINIME_SERVER_PID=$!
  ANPINIME_READY=0
  for attempt in $(seq 1 20); do
    if python3 - "$ANPINIME_SERVER_PID" <<'PY'
import http.client,json,sys
try:
    connection=http.client.HTTPConnection('127.0.0.1',8767,timeout=1)
    connection.request('GET','/__health')
    response=connection.getresponse()
    health=json.loads(response.read(2048))
    valid=response.status==200 and health.get('service')=='anpinime-core-metadata' and health.get('pid')==int(sys.argv[1]) and health.get('movieID')=='10403'
    connection.close()
    sys.exit(0 if valid else 1)
except (OSError,ValueError,http.client.HTTPException):
    sys.exit(1)
PY
    then ANPINIME_READY=1; break; fi
    if ! kill -0 "$ANPINIME_SERVER_PID" 2>/dev/null; then
      cat "$RUNNER_TEMP/anpinime-core-metadata-server.log"
      exit 1
    fi
    sleep 1
  done
  if [ "$ANPINIME_READY" != 1 ]; then
    cat "$RUNNER_TEMP/anpinime-core-metadata-server.log"
    exit 1
  fi
fi
if [ "$ANPINIME_MODE" = hls ]; then
  ANPINIME_RESULT=phim4k-hls
  ANPINIME_FLAG=--phim4k-hls-smoke
  mkdir -p Tests/source2-hls
  ffmpeg -hide_banner -loglevel error -y -i Tests/multitrack.mkv -map 0:v:0 -map 0:a:0 -c copy -t 12 -f hls -hls_time 3 -hls_list_size 0 -hls_base_url /source2-hls/ Tests/source2-hls/index.m3u8
  python3 Tests/serve_player.py --source2-hls > "$RUNNER_TEMP/anpinime-source2-hls-server.log" 2>&1 &
  ANPINIME_SERVER_PID=$!
  ANPINIME_READY=0
  for attempt in $(seq 1 20); do
    if python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8765),timeout=1); s.close()' 2>/dev/null; then ANPINIME_READY=1; break; fi
    kill -0 "$ANPINIME_SERVER_PID"
    sleep 1
  done
  test "$ANPINIME_READY" = 1
fi
ANPINIME_SIMULATOR_ID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"]))')
ANPINIME_APP_DATA=$(xcrun simctl get_app_container "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime data)
python3 - "$ANPINIME_APP_DATA" "$ANPINIME_RESULT" <<'PY'
from pathlib import Path
import sys
for directory in (Path(sys.argv[1])/'Documents', Path('previews')):
    for suffix in ('', '-diagnostics'):
        (directory/('playback-'+sys.argv[2]+suffix+'.json')).unlink(missing_ok=True)
PY
xcrun simctl launch --terminate-running-process "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime "$ANPINIME_FLAG" --mpv-playback-smoke
for attempt in $(seq 1 75); do
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" ]; then
    # The movie opens on a black intro. Capture the live gateway proof later
    # while retaining the same overall wait and app/network cleanup bounds.
    if [ "$ANPINIME_MODE" != gateway ] || python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["time"]>=15 else 1)' "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json"; then break; fi
  fi
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" ] && python3 -c 'import json,sys; sys.exit(0 if any(e["event"]=="failure" for e in json.load(open(sys.argv[1]))["events"]) else 1)' "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json"; then break; fi
  sleep 1
done
mkdir -p previews
xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "previews/$ANPINIME_RESULT.png"
if [ -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" ]; then
  cp "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT-diagnostics.json" previews/
  cat "previews/playback-$ANPINIME_RESULT-diagnostics.json"
fi
if [ "$ANPINIME_MODE" = hls ]; then cp "$RUNNER_TEMP/anpinime-source2-hls-server.log" previews/; fi
if [ "$ANPINIME_MODE" = gateway ]; then cp "$RUNNER_TEMP/anpinime-core-metadata-server.log" previews/; fi
if [ ! -f "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" ]; then
  echo "### $ANPINIME_RESULT: FAIL — no verified video playback" >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi
cp "$ANPINIME_APP_DATA/Documents/playback-$ANPINIME_RESULT.json" previews/
python3 - "$ANPINIME_RESULT" <<'PY'
import json,sys
r=json.load(open('previews/playback-'+sys.argv[1]+'.json'))
assert r['backend']=='mpv' and r['advancingVideoVerified'] and r['videoWidth']>0 and r['videoHeight']>0 and r['time']>1 and r['landscape'], r
if sys.argv[1]=='phim4k-gateway':
    assert r['time']>=15, r
    assert r['coreMetadataReplayed'] is True and r['liveGateway'] is True and r['metadataServerCount']==5 and r['selectedServerID']=='31937', r
    assert set(r['replayedCoreServerIDs'])=={'31937','33090','27463','31938','31939'}, r
    assert not r.get('fullCoreLive',False), r
print(r)
PY
if [ "$ANPINIME_MODE" = gateway ]; then
  echo "### $ANPINIME_RESULT: PASS — Core metadata replayed; live gateway and decoded media playback verified past 15 seconds; full Core API playback not verified" >> "$GITHUB_STEP_SUMMARY"
else
  echo "### $ANPINIME_RESULT: PASS — decoded video dimensions and advancing playback verified" >> "$GITHUB_STEP_SUMMARY"
fi
