#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
for ANPINIME_TOOL in xcrun xcodebuild python3; do
  if ! command -v "$ANPINIME_TOOL" >/dev/null 2>&1; then
    echo "Live AI drama UI smoke requires $ANPINIME_TOOL on a macOS Xcode runner." >&2
    exit 2
  fi
done

ANPINIME_TEMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/anpinime-ai-drama-live.XXXXXX")
ANPINIME_ARTIFACTS="$PWD/previews/ai-drama-live-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ANPINIME_SIMULATOR_ID=""
mkdir -p "$ANPINIME_ARTIFACTS"

ai_drama_live_cleanup() {
  ANPINIME_STATUS=$?
  trap - EXIT
  if [ -n "$ANPINIME_SIMULATOR_ID" ]; then
    xcrun simctl io "$ANPINIME_SIMULATOR_ID" screenshot "$ANPINIME_ARTIFACTS/final-simulator.png" >/dev/null 2>&1 || true
    xcrun simctl terminate "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime >/dev/null 2>&1 || true
  fi
  if [ -d "$ANPINIME_ARTIFACTS/ui.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$ANPINIME_ARTIFACTS/ui.xcresult" \
      --output-path "$ANPINIME_ARTIFACTS/attachments" > "$ANPINIME_ARTIFACTS/attachment-export.log" 2>&1 || true
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if [ "$ANPINIME_STATUS" = 0 ]; then
      printf '### Live Phim AI: PASS — the first fresh catalog series plays its exact first, second and last episodes\n' >> "$GITHUB_STEP_SUMMARY"
    else
      printf '### Live Phim AI: FAIL — see the bounded live UI xcresult and screenshots\n' >> "$GITHUB_STEP_SUMMARY"
    fi
  fi
  echo "Live AI drama UI artifacts: $ANPINIME_ARTIFACTS"
  exit "$ANPINIME_STATUS"
}
trap ai_drama_live_cleanup EXIT

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
  echo "Generate AnyAnime.xcodeproj with XcodeGen before running the live UI smoke test." >&2
  exit 2
fi

# Reset only simulator test-app data on ephemeral CI or an explicit local opt-in.
if [ "${GITHUB_ACTIONS:-}" = true ] || [ "${ANPINIME_AI_RESET_TEST_APP:-}" = 1 ]; then
  xcrun simctl uninstall "$ANPINIME_SIMULATOR_ID" com.xemphim.aipinime >/dev/null 2>&1 || true
fi

set +e
xcodebuild test -project AnyAnime.xcodeproj -scheme AnyAnime -configuration Debug \
  -destination "platform=iOS Simulator,id=$ANPINIME_SIMULATOR_ID" \
  -derivedDataPath "${ANPINIME_AI_DERIVED_DATA:-$ANPINIME_TEMP/DerivedData}" \
  -resultBundlePath "$ANPINIME_ARTIFACTS/ui.xcresult" \
  -only-testing:AnyAnimeUI/AIDramaUITests/testLivePineDramaShortFeedAndPlaylist \
  -only-testing:AnyAnimeUI/AIDramaUITests/testLivePineDramaPlaylistAndVideo \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 200 -maximum-test-execution-time-allowance 200 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | \
  python3 -u -c 'import re, sys
for line in sys.stdin:
    sys.stdout.write(re.sub(r"https?://\S+", "[URL redacted]", line))' | tee "$ANPINIME_ARTIFACTS/xcodebuild.log"
ANPINIME_TEST_STATUS=${PIPESTATUS[0]}
set -e
exit "$ANPINIME_TEST_STATUS"
