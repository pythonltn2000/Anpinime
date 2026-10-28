#!/bin/bash
set -euo pipefail
cat > "$RUNNER_TEMP/mpv-en.srt" <<'EOF'
1
00:00:00,000 --> 00:00:14,000
Primary subtitle test
EOF
cat > "$RUNNER_TEMP/mpv-vi.srt" <<'EOF'
1
00:00:00,000 --> 00:00:14,000
Phụ đề thứ hai
EOF
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=24 -f lavfi -i sine=frequency=440 -f lavfi -i sine=frequency=660 -i "$RUNNER_TEMP/mpv-en.srt" -i "$RUNNER_TEMP/mpv-vi.srt" -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -c:s srt -metadata:s:a:0 language=eng -metadata:s:a:1 language=vie -metadata:s:s:0 language=eng -metadata:s:s:1 language=vie -t 15 Tests/multitrack.mkv
xcodebuild -quiet -project AnyAnime.xcodeproj -scheme AnyAnime -configuration Debug -sdk iphonesimulator -derivedDataPath build-simulator CODE_SIGNING_ALLOWED=NO build
ANPINIME_SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"] and d["isAvailable"]))')
xcrun simctl boot "$ANPINIME_SIMULATOR_ID"
xcrun simctl bootstatus "$ANPINIME_SIMULATOR_ID" -b
xcrun simctl install "$ANPINIME_SIMULATOR_ID" build-simulator/Build/Products/Debug-iphonesimulator/anpinime.app
python3 Tests/serve_player.py > "$RUNNER_TEMP/anpinime-media-server.log" 2>&1 &
ANPINIME_SERVER_PID=$!
trap 'kill "$ANPINIME_SERVER_PID" || true' EXIT
# Wait for the fixture before launching mpv; otherwise a fast simulator may
# open the URL before the Python server has bound its socket.
ANPINIME_SERVER_READY=0
for attempt in $(seq 1 20); do
  if python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8765),timeout=1); s.close()' 2>/dev/null; then
    ANPINIME_SERVER_READY=1
    break
  fi
  kill -0 "$ANPINIME_SERVER_PID"
  sleep 1
done
if [ "$ANPINIME_SERVER_READY" != 1 ]; then
  cat "$RUNNER_TEMP/anpinime-media-server.log"
  exit 1
fi
xcrun simctl launch "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime --mpv-playback-smoke
ANPINIME_APP_DATA=$(xcrun simctl get_app_container "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime data)
mkdir -p previews
for attempt in $(seq 1 55); do
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-mpv.json" ]; then break; fi
  sleep 1
done
xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot previews/playback-mpv.png
cp "$RUNNER_TEMP/anpinime-media-server.log" previews/mpv-fixture-server.log
cp "$ANPINIME_APP_DATA/Documents/playback-mpv.json" previews/playback-mpv.json
python3 - <<'PY'
import json
r=json.load(open('previews/playback-mpv.json'))
assert r['mkvAudioAndDualSubtitlesVerified'] and r['autoplayVerified'] and r['time'] > 1, r
print(r)
PY
for scene in settings subtitles display speed general info; do
  xcrun simctl launch --terminate-running-process "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime --ui-preview "$scene"
  sleep 2
  xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "previews/player-$scene.png"
done
