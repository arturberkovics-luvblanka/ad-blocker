#!/bin/bash
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
PLATFORM="${1:-macOS}"
CONFIGURATION="${2:-Debug}"
case "$CONFIGURATION" in Debug|Release) ;; *) echo "Ismeretlen konfiguráció: $CONFIGURATION" >&2; exit 2;; esac
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$CODE_DIR/extension/manifest.json")"
# iCloud Desktop adds FinderInfo to .appex folders, which breaks codesigning.
# Keep intermediate products in the user's temporary directory.
DERIVED_DATA="${ADBLOCKER_DERIVED_DATA:-${TMPDIR:-/tmp}/adblocker-$(id -u)/DerivedData-$PLATFORM}"
case "$PLATFORM" in
  macOS) DESTINATION='platform=macOS'; SIGNING=(CODE_SIGN_IDENTITY=-) ;;
  iOS) DESTINATION='generic/platform=iOS'; SIGNING=(CODE_SIGNING_ALLOWED=NO) ;;
  *) echo 'Használat: bash code/scripts/build.sh [macOS|iOS]' >&2; exit 2 ;;
esac
test -s "$CODE_DIR/filters/blockerList.json" || { echo 'Hiányzó szűrőlista.' >&2; exit 1; }
python3 "$CODE_DIR/scripts/verify_runtime.py"
python3 "$CODE_DIR/scripts/generate_project.py"
mkdir -p "$PROJECT_DIR/builds/logs"
xcodebuild -project "$CODE_DIR/AdBlocker.xcodeproj" -scheme "AdBlocker-$PLATFORM" \
  -configuration "$CONFIGURATION" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "${SIGNING[@]}" ARCHS=arm64 build 2>&1 | tee "$PROJECT_DIR/builds/logs/build-$PLATFORM.log"
if [ "$PLATFORM" = macOS ]; then
  APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Ad Blocker.app"
  codesign --verify --deep --strict "$APP"
  python3 "$CODE_DIR/scripts/verify_macos.py" "$APP"
  mkdir -p "$PROJECT_DIR/builds/macOS"
  # Keep a zip on iCloud Desktop: FinderInfo can reappear on unpacked apps.
  ditto -c -k --keepParent --norsrc --noextattr "$APP" "$PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
  echo "Tesztcsomag: $PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
else
  echo 'Az iOS build aláírás nélkül készült; fizikai készülékre még nem telepíthető.'
fi
