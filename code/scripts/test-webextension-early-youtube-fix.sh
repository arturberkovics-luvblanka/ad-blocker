#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$CODE_DIR/tests/webextension-early-youtube-fix-fixture"
SCRATCH="$(mktemp -d "/private/tmp/adblocker-webextension-early-youtube-fix.XXXXXX")"

cleanup() {
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

python3 "$CODE_DIR/scripts/verify_runtime.py" >/dev/null

EXTENSION="$SCRATCH/extension"
cp -R "$FIXTURE/extension" "$EXTENSION"
cp "$CODE_DIR/extension/early-youtube.js" "$EXTENSION/early-youtube.js"
cp "$CODE_DIR/extension/advanced-background-runtime.js" "$EXTENSION/advanced-background-runtime.js"

APP="$SCRATCH/WebExtensionEarlyYouTubeFixSmoke.app"
mkdir -p "$APP/Contents/MacOS"
cp "$FIXTURE/Info.plist" "$APP/Contents/Info.plist"
xcrun --toolchain swift swiftc "$CODE_DIR/tests/WebExtensionEarlyYouTubeFixSmoke.swift" \
  -o "$APP/Contents/MacOS/WebExtensionEarlyYouTubeFixSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
codesign --force --sign - "$APP" >/dev/null 2>&1
[[ "$(codesign -d --entitlements - "$APP" 2>&1)" != *"<key>"* ]] || {
  echo "FAIL: scratch harness unexpectedly has code-signing entitlements" >&2
  exit 1
}

mkdir -p "$CODE_DIR/../builds/logs"
"$APP/Contents/MacOS/WebExtensionEarlyYouTubeFixSmoke" "$EXTENSION" \
  2>&1 | tee "$CODE_DIR/../builds/logs/webextension-early-youtube-fix-smoke.log"
