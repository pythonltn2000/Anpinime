#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
for ANPINIME_TOOL in xcrun xcodebuild python3 ffmpeg; do
  if ! command -v "$ANPINIME_TOOL" >/dev/null 2>&1; then
    echo "AI drama UI smoke requires $ANPINIME_TOOL on a macOS Xcode runner." >&2
    exit 2
  fi
done

ANPINIME_TEMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/anpinime-ai-drama.XXXXXX")
ANPINIME_ARTIFACTS="$PWD/previews/ai-drama-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ANPINIME_IDENTITY=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
ANPINIME_SERVER_PID=""
ANPINIME_SIMULATOR_ID=""
mkdir -p "$ANPINIME_ARTIFACTS" "$ANPINIME_TEMP/media"

ai_drama_cleanup() {
  ANPINIME_STATUS=$?
  trap - EXIT
  if [ -n "$ANPINIME_SERVER_PID" ]; then
    python3 - "$ANPINIME_ARTIFACTS/fixture-stats.json" "$ANPINIME_IDENTITY" <<'PY' || true
import json
from pathlib import Path
import sys
from urllib.request import ProxyHandler, build_opener
try:
    with build_opener(ProxyHandler({})).open('http://127.0.0.1:8768/__smoke__/stats', timeout=2) as response:
        stats = json.load(response)
    if stats.get('identity') == sys.argv[2]:
        Path(sys.argv[1]).write_text(json.dumps(stats, indent=2), encoding='utf-8')
except (OSError, ValueError):
    pass
PY
    kill "$ANPINIME_SERVER_PID" 2>/dev/null || true
    wait "$ANPINIME_SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$ANPINIME_SIMULATOR_ID" ]; then
    xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "$ANPINIME_ARTIFACTS/final-simulator.png" >/dev/null 2>&1 || true
  fi
  if [ -d "$ANPINIME_ARTIFACTS/ui.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$ANPINIME_ARTIFACTS/ui.xcresult" \
      --output-path "$ANPINIME_ARTIFACTS/attachments" > "$ANPINIME_ARTIFACTS/attachment-export.log" 2>&1 || true
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if [ "$ANPINIME_STATUS" = 0 ]; then
      printf '### Phim AI: PASS — independent library, native catalog paging and filters, 40-episode playback, history and player lifecycle\n' >> "$GITHUB_STEP_SUMMARY"
    else
      printf '### Phim AI: FAIL — see AI drama UI xcresult and fixture artifacts\n' >> "$GITHUB_STEP_SUMMARY"
    fi
  fi
  echo "AI drama UI artifacts: $ANPINIME_ARTIFACTS"
  if [ "$ANPINIME_STATUS" != 0 ] && [ -f "$ANPINIME_ARTIFACTS/server.log" ]; then
    cat "$ANPINIME_ARTIFACTS/server.log"
  fi
  exit "$ANPINIME_STATUS"
}
trap ai_drama_cleanup EXIT

# Generated test imagery with a colored panel, moving bars, tone and embedded episode label.
python3 - "$ANPINIME_TEMP/media" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
for episode, color, tone in [(1, '0x1e40af', 440), (3, '0x047857', 660), (40, '0x9d174d', 880)]:
    # mov_text is built into minimal ffmpeg; no drawtext, font or subtitle filter is needed.
    subtitle = root / f'episode-{episode:02d}.srt'
    subtitle.write_text(f'1\n00:00:00,000 --> 00:00:48,000\nEPISODE {episode:02d}\n', encoding='utf-8')
    filters = f'drawbox=x=0:y=0:w=360:h=180:color={color}:t=fill'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', 'lavfi', '-i', 'testsrc2=size=360x640:rate=15',
                    '-f', 'lavfi', '-i', f'sine=frequency={tone}:sample_rate=44100',
                    '-f', 'srt', '-i', str(subtitle), '-map', '0:v:0', '-map', '1:a:0', '-map', '2:s:0',
                    '-t', '48', '-vf', filters, '-c:v', 'libx264', '-preset', 'ultrafast',
                    '-crf', '30', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '64k',
                    '-c:s', 'mov_text', '-metadata:s:s:0', 'language=vie',
                    '-metadata:s:s:0', f'title=EPISODE {episode:02d}', '-disposition:s:0', 'default',
                    '-movflags', '+faststart', str(root / f'episode-{episode:02d}.mp4')], check=True)
PY

ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=24 -f lavfi -i sine=frequency=530 -t 30 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac "$ANPINIME_TEMP/media/episode-05.mp4"
python3 -u Tests/serve_ai_drama.py --media-root "$ANPINIME_TEMP/media" --port 8768 \
  --identity "$ANPINIME_IDENTITY" --ready-file "$ANPINIME_TEMP/ready.json" \
  > "$ANPINIME_ARTIFACTS/server.log" 2>&1 &
ANPINIME_SERVER_PID=$!

# A listening port alone is insufficient: both health and readiness must identify our PID.
python3 - "$ANPINIME_TEMP/ready.json" "$ANPINIME_SERVER_PID" "$ANPINIME_IDENTITY" <<'PY'
import json
import os
from pathlib import Path
import sys
import time
from urllib.request import ProxyHandler, build_opener

ready_path, pid, identity = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
opener = build_opener(ProxyHandler({}))
for _ in range(100):
    try:
        os.kill(pid, 0)
        ready = json.loads(ready_path.read_text(encoding='utf-8'))
        with opener.open('http://127.0.0.1:8768/__smoke__/health', timeout=0.5) as response:
            health = json.load(response)
        assert ready == health
        assert health['service'] == 'anpinime-ai-drama-fixture'
        assert health['pid'] == pid and health['identity'] == identity and health['port'] == 8768
        assert health['episodeCount'] == 40
        assert health['fixtureVersion'] == 2
        break
    except ProcessLookupError:
        raise SystemExit('AI drama fixture process exited before readiness')
    except (OSError, ValueError, AssertionError, KeyError):
        time.sleep(0.1)
else:
    raise SystemExit('AI drama fixture PID/identity health check failed')
PY
cp "$ANPINIME_TEMP/ready.json" "$ANPINIME_ARTIFACTS/fixture-ready.json"

xcrun simctl list devices available -j > "$ANPINIME_TEMP/simulators.json"
ANPINIME_SIMULATOR_ID=$(python3 - "$ANPINIME_TEMP/simulators.json" "${ANPINIME_AI_SIMULATOR_ID:-}" <<'PY'
import json
import sys
devices = [device for group in json.load(open(sys.argv[1]))['devices'].values()
           for device in group if device.get('isAvailable', True) and 'iPhone' in device['name']]
requested = sys.argv[2]
if requested:
    selected = next((device for device in devices if device['udid'] == requested), None)
else:
    selected = next((device for device in devices if device['state'] == 'Booted'), None)
    selected = selected or next((device for device in devices if device['name'] == 'iPhone 17 Pro'), None)
    selected = selected or next(iter(devices), None)
if selected is None:
    raise SystemExit('No available iPhone simulator matches the requested device')
print(selected['udid'])
PY
)
xcrun simctl boot "$ANPINIME_SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$ANPINIME_SIMULATOR_ID" -b
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
elif [ ! -d AnyAnime.xcodeproj ]; then
  echo "Generate AnyAnime.xcodeproj with XcodeGen before running the UI smoke test." >&2
  exit 2
fi

ANPINIME_UI_FILTERS=(
  -only-testing:AnyAnimeUI/AIDramaUITests/testShortFeedSwipeFullscreenAndFullPlaylist
  -only-testing:AnyAnimeUI/MovieSearchUITests
  -only-testing:AnyAnimeUI/AIDramaUITests/testCatalogPagingFiltersAndLibraryChoices
  -only-testing:AnyAnimeUI/AIDramaUITests/testVerticalEpisodesPlaylistAndLifecycle
)
if [ "${ANPINIME_AI_SHORTS_ONLY:-false}" = true ]; then
  ANPINIME_UI_FILTERS=(-only-testing:AnyAnimeUI/AIDramaUITests/testShortFeedSwipeFullscreenAndFullPlaylist)
fi

set +e
xcodebuild test -project AnyAnime.xcodeproj -scheme AnyAnime -configuration Debug \
  -destination "platform=iOS Simulator,id=$ANPINIME_SIMULATOR_ID" \
  -derivedDataPath "${ANPINIME_AI_DERIVED_DATA:-$ANPINIME_TEMP/DerivedData}" \
  -resultBundlePath "$ANPINIME_ARTIFACTS/ui.xcresult" \
  "${ANPINIME_UI_FILTERS[@]}" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 240 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee "$ANPINIME_ARTIFACTS/xcodebuild.log"
ANPINIME_TEST_STATUS=${PIPESTATUS[0]}
set -e
exit "$ANPINIME_TEST_STATUS"
