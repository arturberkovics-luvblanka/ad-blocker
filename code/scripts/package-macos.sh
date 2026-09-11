#!/bin/bash
set -euo pipefail

usage() {
  echo 'Használat: package-macos.sh APP_PATH [OUTPUT_DIR]' >&2
  exit 2
}

fail() {
  echo "HIBA: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
APP_PATH="$1"
OUTPUT_DIR="${2:-$PROJECT_DIR/builds/macOS}"
MANIFEST="$CODE_DIR/extension/manifest.json"

[[ -d "$APP_PATH" && "$APP_PATH" == *.app ]] || fail "Az appPath nem .app csomag: $APP_PATH"
[[ ! -L "$APP_PATH" ]] || fail "Az appPath nem lehet szimbolikus link."
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "Az alkalmazás Info.plist fájlja hiányzik."
[[ -f "$MANIFEST" ]] || fail "A WebExtension manifest hiányzik: $MANIFEST"
command -v python3 >/dev/null || fail "A python3 nem érhető el."
command -v pkgbuild >/dev/null || fail "A pkgbuild nem érhető el."
command -v pkgutil >/dev/null || fail "A pkgutil nem érhető el."
command -v codesign >/dev/null || fail "A codesign nem érhető el."
command -v lipo >/dev/null || fail "A lipo nem érhető el."

VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$MANIFEST")"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
  fail "A manifest verziója nem major.minor.patch alakú: $VERSION"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" ]] || \
  fail "Az app verziója ($APP_VERSION) nem egyezik a manifest verziójával ($VERSION)."

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail "Érvénytelen bundle identifier: $BUNDLE_ID"
PACKAGE_ID="$BUNDLE_ID.installer"
PACKAGE_NAME="AdBlocker-$VERSION-macOS-arm64.pkg"

verify_bundle_architectures() {
  local root="$1"
  while IFS= read -r -d '' bundle; do
    local plist="$bundle/Contents/Info.plist"
    [[ -f "$plist" ]] || fail "A beágyazott bundle Info.plist fájlja hiányzik: $bundle"
    local executable
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
    local binary="$bundle/Contents/MacOS/$executable"
    [[ -f "$binary" ]] || fail "A bundle futtatható fájlja hiányzik: $binary"
    local architectures
    architectures="$(lipo -archs "$binary")"
    [[ "$architectures" == "arm64" ]] || \
      fail "A csomag csak arm64 binárisokat tartalmazhat: $binary ($architectures)"
  done < <(find "$root" -type d \( -name '*.app' -o -name '*.appex' \) -print0)
}

codesign --verify --deep --strict "$APP_PATH"
verify_bundle_architectures "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/$PACKAGE_NAME"
[[ ! -e "$OUTPUT_PATH" ]] || fail "A kimeneti csomag már létezik: $OUTPUT_PATH"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-macos-package.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
STAGED_PACKAGE="$SCRATCH/$PACKAGE_NAME"
PAYLOAD_ROOT="$SCRATCH/root"
STAGED_APP="$PAYLOAD_ROOT/Applications/$(basename "$APP_PATH")"
COMPONENT_PLIST="$SCRATCH/components.plist"

mkdir -p "$PAYLOAD_ROOT/Applications"
ditto --norsrc --noextattr "$APP_PATH" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
verify_bundle_architectures "$STAGED_APP"
/usr/bin/diff -qr "$APP_PATH" "$STAGED_APP" >/dev/null || \
  fail "A staging alkalmazás fájljai eltérnek az eredeti app fájljaitól."

pkgbuild --analyze --root "$PAYLOAD_ROOT" "$COMPONENT_PLIST"
python3 - "$COMPONENT_PLIST" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as source:
    components = plistlib.load(source)

count = 0

def configure(value):
    global count
    if isinstance(value, list):
        for item in value:
            configure(item)
    elif isinstance(value, dict):
        if "RootRelativeBundlePath" in value:
            count += 1
            value["BundleIsRelocatable"] = False
            value["BundleIsVersionChecked"] = False
            value["BundleHasStrictIdentifier"] = True
            value["BundleOverwriteAction"] = "upgrade"
        for child in value.values():
            configure(child)

configure(components)
if count == 0:
    raise SystemExit("A pkgbuild nem talált bundle-t a staging rootban.")

with open(path, "wb") as destination:
    plistlib.dump(components, destination, sort_keys=True)
PY

if security find-identity -v -p basic 2>/dev/null | tail -n 1 | grep -Fq '0 valid identities found'; then
  echo "Nincs érvényes Installer identity; az elkészülő .pkg nincs aláírva."
else
  echo "A script nem választ automatikusan tanúsítványt; az elkészülő .pkg nincs aláírva."
fi

pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --install-location / \
  --identifier "$PACKAGE_ID" \
  --version "$VERSION" \
  "$STAGED_PACKAGE"

EXPANDED="$SCRATCH/expanded"
pkgutil --expand-full "$STAGED_PACKAGE" "$EXPANDED"

[[ -z "$(find "$EXPANDED" -type d -name Payload -prune -o -type d -name Scripts -print -quit)" ]] || \
  fail "A csomag váratlan installer scriptet tartalmaz."
[[ -z "$(find "$EXPANDED/Payload" \( -name '._*' -o -name '.DS_Store' \) -print -quit)" ]] || \
  fail "A payload váratlan Finder/AppleDouble metadatafájlt tartalmaz."

PACKAGE_INFO="$(find "$EXPANDED" -type f -name PackageInfo -print -quit)"
[[ -n "$PACKAGE_INFO" ]] || fail "A kibontott csomag PackageInfo fájlja hiányzik."
grep -Fq 'install-location="/"' "$PACKAGE_INFO" || \
  fail "A csomag install-location értéke nem a payload root."
grep -Fq "identifier=\"$PACKAGE_ID\"" "$PACKAGE_INFO" || \
  fail "A csomag identifier értéke eltér az elvárttól."
grep -Fq "version=\"$VERSION\"" "$PACKAGE_INFO" || \
  fail "A csomag verziója eltér az elvárttól."

EXTRACTED_APPS="$(find "$EXPANDED" -type d -name '*.app' -prune -print)"
EXTRACTED_APP_COUNT="$(printf '%s\n' "$EXTRACTED_APPS" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$EXTRACTED_APP_COUNT" == "1" ]] || \
  fail "A csomag payloadjában pontosan egy .app szükséges; talált: $EXTRACTED_APP_COUNT"
EXTRACTED_APP="$EXTRACTED_APPS"
[[ "$EXTRACTED_APP" == */Payload/Applications/*.app ]] || \
  fail "A kibontott alkalmazás nem a determinisztikus /Applications payloadútvonalon van."

codesign --verify --deep --strict "$EXTRACTED_APP"
verify_bundle_architectures "$EXTRACTED_APP"
/usr/bin/diff -qr "$APP_PATH" "$EXTRACTED_APP" >/dev/null || \
  fail "A kibontott alkalmazás fájljai eltérnek az eredeti app fájljaitól."

mv "$STAGED_PACKAGE" "$OUTPUT_PATH"
PACKAGE_SHA256="$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
echo "Kész: $OUTPUT_PATH"
echo "SHA-256: $PACKAGE_SHA256"
echo "Megjegyzés: a .pkg nincs Developer ID Installer tanúsítvánnyal aláírva és nincs notarizálva."
