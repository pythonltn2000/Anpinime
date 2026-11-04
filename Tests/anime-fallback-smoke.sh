#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# mpv-smoke.sh installs the current Debug app and boots the simulator first.
ANPINIME_SIMULATOR_ID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"]))')
ANPINIME_APP_DATA=$(xcrun simctl get_app_container "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime data)
ANPINIME_ARTIFACTS="$PWD/previews/anime-native-fallback"
mkdir -p "$ANPINIME_ARTIFACTS"
python3 - "$ANPINIME_APP_DATA" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'Documents'
for name in ('playback-anime-native-fallback.json', 'playback-anime-native-fallback-diagnostics.json'):
    (root / name).unlink(missing_ok=True)
PY

python3 -u Tests/serve_player.py --anime-native-failure > "$ANPINIME_ARTIFACTS/server.log" 2>&1 &
ANPINIME_SERVER_PID=$!
anime_fallback_cleanup() {
  ANPINIME_STATUS=$?
  trap - EXIT
  xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "$ANPINIME_ARTIFACTS/final-simulator.png" >/dev/null 2>&1 || true
  python3 - "$ANPINIME_ARTIFACTS/server-stats.json" <<'PY' || true
import json
from pathlib import Path
import sys
from urllib.request import ProxyHandler, build_opener
with build_opener(ProxyHandler({})).open('http://127.0.0.1:8765/__smoke__/native-fallback', timeout=2) as response:
    result = json.load(response)
Path(sys.argv[1]).write_text(json.dumps(result, indent=2), encoding='utf-8')
PY
  for ANPINIME_NAME in playback-anime-native-fallback.json playback-anime-native-fallback-diagnostics.json; do
    if [ -f "$ANPINIME_APP_DATA/Documents/$ANPINIME_NAME" ]; then
      cp "$ANPINIME_APP_DATA/Documents/$ANPINIME_NAME" "$ANPINIME_ARTIFACTS/$ANPINIME_NAME"
    fi
  done
  kill "$ANPINIME_SERVER_PID" 2>/dev/null || true
  wait "$ANPINIME_SERVER_PID" 2>/dev/null || true
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if [ "$ANPINIME_STATUS" = 0 ]; then
      echo '### Anime native failure recovery: PASS — real native HTTP 403, same WebKit document, decoded video resumes' >> "$GITHUB_STEP_SUMMARY"
    else
      echo '### Anime native failure recovery: FAIL — see native-fallback diagnostic artifacts' >> "$GITHUB_STEP_SUMMARY"
    fi
  fi
  exit "$ANPINIME_STATUS"
}
trap anime_fallback_cleanup EXIT

# An identity-specific endpoint avoids accepting an unrelated listening server.
python3 - "$ANPINIME_SERVER_PID" <<'PY'
import json
import os
import sys
import time
from urllib.request import ProxyHandler, build_opener
opener = build_opener(ProxyHandler({}))
for _ in range(50):
    os.kill(int(sys.argv[1]), 0)
    try:
        with opener.open('http://127.0.0.1:8765/__smoke__/native-fallback', timeout=.5) as response:
            stats = json.load(response)
        assert stats['service'] == 'anpinime-native-fallback' and stats['pid'] == int(sys.argv[1])
        assert stats['nativeRejectedRequests'] == 0 and stats['embedRequests'] == 0
        break
    except (OSError, ValueError, KeyError, AssertionError):
        time.sleep(.1)
else:
    raise SystemExit('Native fallback fixture did not become ready')
PY
xcrun simctl launch --terminate-running-process "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime --anime-native-failure-smoke --mpv-playback-smoke
for _ in $(seq 1 45); do
  if [ -f "$ANPINIME_APP_DATA/Documents/playback-anime-native-fallback.json" ]; then break; fi
  sleep 1
done
python3 - "$ANPINIME_APP_DATA" <<'PY'
import json
from pathlib import Path
import sys
from urllib.request import ProxyHandler, build_opener
root = Path(sys.argv[1]) / 'Documents'
result = json.loads((root / 'playback-anime-native-fallback.json').read_text())
diagnostics = json.loads((root / 'playback-anime-native-fallback-diagnostics.json').read_text())
assert result['backend'] == 'web' and result['advancingVideoVerified'], result
assert result['nativeFailureRecoveryVerified'] and result['sameWebsiteRestoredVerified'], result
assert result['loadingClearedVerified'], result
assert result['time'] > 1 and result['videoWidth'] > 0 and result['videoHeight'] > 0 and result['landscape'], result
events = diagnostics['events']
failed = next(i for i, row in enumerate(events) if row['event'] == 'anime-native-failed')
restored = next(i for i, row in enumerate(events) if row['event'] == 'anime-web-restored' and row.get('reusedWebsite'))
assert failed < restored, events
with build_opener(ProxyHandler({})).open('http://127.0.0.1:8765/__smoke__/native-fallback', timeout=2) as response:
    stats = json.load(response)
assert stats['nativeRejectedRequests'] >= 1 and stats['validWebMediaRequests'] >= 1, stats
assert stats['nestedAdFrameRequests'] >= 1, stats
assert stats['embedRequests'] == stats['embedRequestsAtFailure'], ('The website was reloaded instead of restored', stats)
print(json.dumps({'result': result, 'fixture': stats}, sort_keys=True))
PY
