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
      printf '### Phim AI: PASS — native swipes, 40 episodes, decoded portrait playback, pause lifecycle and player release\n' >> "$GITHUB_STEP_SUMMARY"
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

# Every clip is generated test imagery: moving test bars, a colored title, and a tone.
python3 - "$ANPINIME_TEMP/media" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
fonts = [Path('/System/Library/Fonts/Supplemental/Arial Bold.ttf'),
         Path('/System/Library/Fonts/Helvetica.ttc'),
         Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')]
font = next((str(path) for path in fonts if path.is_file()), None)
if font is None:
    raise SystemExit('A system font is required for visible fixture episode titles')
for episode, color, tone in [(1, '0x1e40af', 440), (3, '0x047857', 660), (40, '0x9d174d', 880)]:
    escaped_font = font.replace('\\', '\\\\').replace(':', '\\:').replace("'", "\\'")
    filters = (f'drawbox=x=0:y=0:w=360:h=180:color={color}:t=fill,'
               f"drawtext=fontfile='{escaped_font}':text='EPISODE {episode:02d}':"
               'fontcolor=white:fontsize=43:x=(w-text_w)/2:y=70')
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', 'lavfi', '-i', 'testsrc2=size=360x640:rate=15',
                    '-f', 'lavfi', '-i', f'sine=frequency={tone}:sample_rate=44100',
                    '-t', '48', '-vf', filters, '-c:v', 'libx264', '-preset', 'ultrafast',
                    '-crf', '30', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '64k',
                    '-movflags', '+faststart', '-shortest', str(root / f'episode-{episode:02d}.mp4')], check=True)
PY

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

set +e
xcodebuild test -project AnyAnime.xcodeproj -scheme AnyAnime -configuration Debug \
  -destination "platform=iOS Simulator,id=$ANPINIME_SIMULATOR_ID" \
  -derivedDataPath "$ANPINIME_TEMP/DerivedData" \
  -resultBundlePath "$ANPINIME_ARTIFACTS/ui.xcresult" \
  -only-testing:AnyAnimeUI/AIDramaUITests -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee "$ANPINIME_ARTIFACTS/xcodebuild.log"
ANPINIME_TEST_STATUS=${PIPESTATUS[0]}
set -e
exit "$ANPINIME_TEST_STATUS"
