#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$CODE_DIR/tests/webextension-early-timing-fixture"
SCRATCH="$(mktemp -d "/private/tmp/adblocker-webextension-early-timing.XXXXXX")"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

RULE="youtube.com#%#//scriptlet('set-constant', 'google_ad_status', '1')"
/usr/bin/grep -Fq "$RULE" "$CODE_DIR/filters/adguard-base.txt" || {
  echo "FAIL: pinned AdGuard source no longer contains the timing rule" >&2
  exit 1
}
/usr/bin/grep -Fq "$RULE" "$CODE_DIR/filters/generated/adguard-base-advanced.txt" || {
  echo "FAIL: advanced extraction no longer contains the timing rule" >&2
  exit 1
}

python3 "$FIXTURE/server.py" "$SCRATCH/port" &
SERVER_PID=$!
for _ in {1..100}; do
  [[ -s "$SCRATCH/port" ]] && break
  kill -0 "$SERVER_PID" 2>/dev/null || {
    echo "FAIL: isolated fixture server exited before publishing its port" >&2
    exit 1
  }
  sleep 0.05
done
[[ -s "$SCRATCH/port" ]] || {
  echo "FAIL: isolated fixture server did not publish its port" >&2
  exit 1
}

PORT="$(cat "$SCRATCH/port")"
EXTENSION="$SCRATCH/extension"
cp -R "$FIXTURE/extension" "$EXTENSION"
cp "$CODE_DIR/extension/advanced-background-runtime.js" "$EXTENSION/advanced-background-runtime.js"

APP="$SCRATCH/WebExtensionEarlyTimingSmoke.app"
mkdir -p "$APP/Contents/MacOS"
cp "$FIXTURE/Info.plist" "$APP/Contents/Info.plist"
xcrun --toolchain swift swiftc "$CODE_DIR/tests/WebExtensionEarlyTimingSmoke.swift" \
  -o "$APP/Contents/MacOS/WebExtensionEarlyTimingSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
codesign --force --sign - "$APP" >/dev/null 2>&1
[[ "$(codesign -d --entitlements - "$APP" 2>&1)" != *"<key>"* ]] || {
  echo "FAIL: scratch harness unexpectedly has code-signing entitlements" >&2
  exit 1
}

mkdir -p "$CODE_DIR/../builds/logs"
"$APP/Contents/MacOS/WebExtensionEarlyTimingSmoke" "$EXTENSION" \
  "http://127.0.0.1:$PORT/page.html" \
  2>&1 | tee "$CODE_DIR/../builds/logs/webextension-early-timing-smoke.log"
