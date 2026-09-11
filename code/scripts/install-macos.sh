#!/bin/bash
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$CODE_DIR/extension/manifest.json")"
ARCHIVE="$PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
DESTINATION="$HOME/Applications/Ad Blocker.app"
test -f "$ARCHIVE" || { echo 'Előbb futtasd a build.sh macOS parancsot.' >&2; exit 1; }
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$ARCHIVE" "$STAGING"
codesign --verify --deep --strict "$STAGING/Ad Blocker.app"
if [ -e "$DESTINATION" ]; then
  IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
  [ "$IDENTIFIER" = org.local.adblocker ] || { echo 'Másik alkalmazás van ezen a néven; nem írom felül.' >&2; exit 1; }
fi
mkdir -p "$HOME/Applications"
ditto --norsrc --noextattr "$STAGING/Ad Blocker.app" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
python3 "$CODE_DIR/scripts/verify_macos.py" "$DESTINATION"
# Xcode may register its intermediate copy too. Keep the installed one visible.
BUILD_APP="${TMPDIR:-/tmp}/adblocker-$(id -u)/DerivedData-macOS/Build/Products/Debug/Ad Blocker.app"
for EXTENSION in ContentBlocker WebExtension; do
  PLUGIN="$BUILD_APP/Contents/PlugIns/AdBlocker$EXTENSION.appex"
  if [ -d "$PLUGIN" ]; then pluginkit -r "$PLUGIN"; fi
  pluginkit -a "$DESTINATION/Contents/PlugIns/AdBlocker$EXTENSION.appex"
done
echo "Telepítve és ellenőrizve: $DESTINATION"
open "$DESTINATION"
