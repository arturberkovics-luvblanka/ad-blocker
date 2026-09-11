#!/bin/bash
# Install a local test build without creating a second implicit user copy.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Használat: install-macos.sh [--local-test-path /abszolút/teszt.app]

Alapértelmezésben a helyi .pkg-t az Installerrel az exact
/Applications/Ad Blocker.app útvonalra telepíti. A --local-test-path kizárólag
kifejezett, elkülönített fejlesztői próbához való; nem regisztrál Safari
bővítményt és nem indítja el az appot.
EOF
  exit 2
}

fail() {
  echo "HIBA: $*" >&2
  exit 1
}

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$CODE_DIR/extension/manifest.json")"
ARCHIVE="$PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
MODE="applications"
DESTINATION="/Applications/Ad Blocker.app"
if [[ "${1:-}" == "--local-test-path" ]]; then
  [[ $# == 2 && "$2" == /* && "$2" == *.app ]] || usage
  MODE="local-test"
  DESTINATION="$2"
elif [[ $# != 0 ]]; then
  usage
fi

[[ -f "$ARCHIVE" ]] || fail "Előbb futtasd a build.sh macOS parancsot."
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$ARCHIVE" "$STAGING"
APP="$STAGING/Ad Blocker.app"
codesign --verify --deep --strict "$APP"
python3 "$CODE_DIR/scripts/verify_macos.py" "$APP"

if [[ "$MODE" == "local-test" ]]; then
  [[ "$DESTINATION" != "/Applications/Ad Blocker.app" ]] || fail "A helyi tesztútvonal nem lehet a normál /Applications hely."
  [[ ! -e "$DESTINATION" ]] || fail "A helyi tesztcél már létezik; nem írom felül."
  mkdir -p "$(dirname "$DESTINATION")"
  ditto --norsrc --noextattr "$APP" "$DESTINATION"
  codesign --verify --deep --strict "$DESTINATION"
  python3 "$CODE_DIR/scripts/verify_macos.py" "$DESTINATION"
  echo "Elkülönített helyi tesztpéldány: $DESTINATION"
  exit 0
fi

# Use the same package path as a real update: it verifies bundle identity and
# CFBundleVersion before replacing /Applications/Ad Blocker.app, and starts the
# first-run walkthrough in the active desktop session where possible.
PACKAGE_DIR="$STAGING/package"
mkdir -p "$PACKAGE_DIR"
bash "$CODE_DIR/scripts/package-macos.sh" --local "$APP" "$PACKAGE_DIR"
PACKAGE="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name '*.pkg' -print -quit)"
[[ -n "$PACKAGE" ]] || fail "A helyi .pkg nem készült el."

if [[ $EUID == 0 ]]; then
  installer -pkg "$PACKAGE" -target /
else
  sudo installer -pkg "$PACKAGE" -target /
fi
[[ -d "$DESTINATION" ]] || fail "Az Installer után hiányzik az exact /Applications app."
codesign --verify --deep --strict "$DESTINATION"
python3 "$CODE_DIR/scripts/verify_macos.py" "$DESTINATION"
/usr/bin/diff -qr "$APP" "$DESTINATION" >/dev/null || \
  fail "A telepített app fájljai eltérnek az ellenőrzött package payloadtól."
echo "Telepítve és ellenőrizve: $DESTINATION"
