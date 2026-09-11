#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$CODE_DIR/tests/webextension-integration-fixture"
SCRATCH="$(mktemp -d "/private/tmp/adblocker-webextension-integration.XXXXXX")"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

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
APP="$SCRATCH/WebExtensionIntegrationSmoke.app"
mkdir -p "$APP/Contents/MacOS"
cp "$FIXTURE/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$CODE_DIR/../builds/logs"
xcrun --toolchain swift swiftc "$CODE_DIR/tests/WebExtensionIntegrationSmoke.swift" \
  -o "$APP/Contents/MacOS/WebExtensionIntegrationSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
codesign --force --sign - "$APP" >/dev/null
[[ "$(codesign -d --entitlements - "$APP" 2>&1)" != *"<key>"* ]] || {
  echo "FAIL: scratch harness unexpectedly has code-signing entitlements" >&2
  exit 1
}
"$APP/Contents/MacOS/WebExtensionIntegrationSmoke" "$EXTENSION" \
  "http://127.0.0.1:$PORT/page.html" \
  2>&1 | tee "$CODE_DIR/../builds/logs/webextension-integration-smoke.log"
