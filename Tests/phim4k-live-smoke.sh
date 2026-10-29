#!/bin/bash
set -euo pipefail
ANPINIME_SIMULATOR_ID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"]))')
ANPINIME_APP_DATA=$(xcrun simctl get_app_container "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime data)
rm -f "$ANPINIME_APP_DATA/Documents/playback-phim4k-live.json"
xcrun simctl launch --terminate-running-process "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime --phim4k-live-smoke --mpv-playback-smoke
for attempt in $(seq 1 75); do
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-phim4k-live.json" ]; then break; fi
  sleep 1
done
mkdir -p previews
xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot previews/phim4k-free1-live.png
test -f "$ANPINIME_APP_DATA/Documents/playback-phim4k-live.json"
cp "$ANPINIME_APP_DATA/Documents/playback-phim4k-live.json" previews/
