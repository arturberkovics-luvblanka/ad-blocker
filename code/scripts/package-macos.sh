#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Használat: package-macos.sh [--local|--distribution] APP_PATH [OUTPUT_DIR]

Az alapértelmezett --local csak helyi tesztcsomagot készít. A --distribution
Developer ID Installer aláírást, Apple-notarizálást és staple-ellenőrzést
követel. Kötelező környezeti változók: ADBLOCKER_DEVELOPMENT_TEAM,
ADBLOCKER_DEVELOPER_ID_APPLICATION, ADBLOCKER_DEVELOPER_ID_INSTALLER és
ADBLOCKER_NOTARY_PROFILE (a notarytool Keychain-profil neve).
EOF
  exit 2
}

fail() {
  echo "HIBA: $*" >&2
  exit 1
}

MODE="local"
if [[ "${1:-}" == "--local" || "${1:-}" == "--distribution" ]]; then
  MODE="${1#--}"
  shift
fi
[[ $# -ge 1 && $# -le 2 ]] || usage

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
APP_PATH="$1"
OUTPUT_DIR="${2:-$PROJECT_DIR/builds/macOS}"
MANIFEST="$CODE_DIR/extension/manifest.json"

[[ -d "$APP_PATH" && "$APP_PATH" == *.app ]] || fail "Az appPath nem .app csomag: $APP_PATH"
[[ "$(basename "$APP_PATH")" == "Ad Blocker.app" ]] || fail "Az app csomagneve pontosan Ad Blocker.app legyen."
[[ ! -L "$APP_PATH" ]] || fail "Az appPath nem lehet szimbolikus link."
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "Az alkalmazás Info.plist fájlja hiányzik."
[[ -f "$MANIFEST" ]] || fail "A WebExtension manifest hiányzik: $MANIFEST"
command -v python3 >/dev/null || fail "A python3 nem érhető el."
command -v pkgbuild >/dev/null || fail "A pkgbuild nem érhető el."
command -v pkgutil >/dev/null || fail "A pkgutil nem érhető el."
command -v codesign >/dev/null || fail "A codesign nem érhető el."
command -v lipo >/dev/null || fail "A lipo nem érhető el."
command -v security >/dev/null || fail "A security nem érhető el."

VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$MANIFEST")"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
  fail "A manifest verziója nem major.minor.patch alakú: $VERSION"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" ]] || \
  fail "Az app verziója ($APP_VERSION) nem egyezik a manifest verziójával ($VERSION)."
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
[[ "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+)*$ ]] || \
  fail "Az app CFBundleVersion értéke csak pontokkal tagolt egész lehet: $BUILD_NUMBER"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail "Érvénytelen bundle identifier: $BUNDLE_ID"
PACKAGE_ID="$BUNDLE_ID.installer"
PACKAGE_VERSION="$VERSION.$BUILD_NUMBER"
PACKAGE_NAME="AdBlocker-$VERSION-build$BUILD_NUMBER-macOS-arm64.pkg"

if [[ "$MODE" == "distribution" ]]; then
  TEAM="${ADBLOCKER_DEVELOPMENT_TEAM:-}"
  APPLICATION_IDENTITY="${ADBLOCKER_DEVELOPER_ID_APPLICATION:-}"
  INSTALLER_IDENTITY="${ADBLOCKER_DEVELOPER_ID_INSTALLER:-}"
  NOTARY_PROFILE="${ADBLOCKER_NOTARY_PROFILE:-}"
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail "Az ADBLOCKER_DEVELOPMENT_TEAM értéke egy 10 karakteres Team ID legyen."
  [[ "$APPLICATION_IDENTITY" == Developer\ ID\ Application:* ]] || \
    fail "Az ADBLOCKER_DEVELOPER_ID_APPLICATION Developer ID Application identity legyen."
  [[ "$INSTALLER_IDENTITY" == Developer\ ID\ Installer:* ]] || \
    fail "Az ADBLOCKER_DEVELOPER_ID_INSTALLER Developer ID Installer identity legyen."
  [[ "$APPLICATION_IDENTITY" == *"($TEAM)" && "$INSTALLER_IDENTITY" == *"($TEAM)" ]] || \
    fail "A Developer ID identityk Team ID-ja eltér az ADBLOCKER_DEVELOPMENT_TEAM értékétől."
  [[ -n "$NOTARY_PROFILE" ]] || fail "Az ADBLOCKER_NOTARY_PROFILE Keychain-profil neve kötelező."
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$APPLICATION_IDENTITY" || \
    fail "A Developer ID Application identity nem található a Keychainben."
  security find-identity -v -p basic 2>/dev/null | grep -Fq "$INSTALLER_IDENTITY" || \
    fail "A Developer ID Installer identity nem található a Keychainben."
  command -v xcrun >/dev/null || fail "Az xcrun/notarytool nem érhető el."
  python3 "$CODE_DIR/scripts/verify_macos.py" --distribution \
    --team "$TEAM" --application-identity "$APPLICATION_IDENTITY" "$APP_PATH"
fi

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
INSTALLER_SCRIPTS="$SCRATCH/installer-scripts"
PREINSTALL="$CODE_DIR/installer/preinstall"
POSTINSTALL="$CODE_DIR/installer/postinstall"

[[ -f "$PREINSTALL" && ! -L "$PREINSTALL" ]] || fail "A saját preinstall script hiányzik vagy symlink."
[[ -f "$POSTINSTALL" && ! -L "$POSTINSTALL" ]] || fail "A saját postinstall script hiányzik vagy symlink."
/bin/bash -n "$PREINSTALL" || fail "A preinstall script szintaktikája hibás."
/bin/bash -n "$POSTINSTALL" || fail "A postinstall script szintaktikája hibás."
mkdir -p "$INSTALLER_SCRIPTS"
python3 - "$PREINSTALL" "$INSTALLER_SCRIPTS/preinstall" "$BUNDLE_ID" "$VERSION" "$BUILD_NUMBER" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
bundle_id = sys.argv[3]
version = sys.argv[4]
build = sys.argv[5]
text = source.read_text()
for marker, value in {
    "__ADBLOCKER_BUNDLE_ID__": bundle_id,
    "__ADBLOCKER_MARKETING_VERSION__": version,
    "__ADBLOCKER_BUNDLE_BUILD__": build,
}.items():
    if text.count(marker) != 1:
        raise SystemExit(f"Invalid preinstall template marker: {marker}")
    text = text.replace(marker, value)
destination.write_text(text)
PY
cp "$POSTINSTALL" "$INSTALLER_SCRIPTS/postinstall"
chmod 755 "$INSTALLER_SCRIPTS/preinstall"
chmod 755 "$INSTALLER_SCRIPTS/postinstall"

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
            # The preinstall script compares CFBundleVersion before payload
            # replacement. Equal versions repair an install; a higher existing
            # build fails before any file is modified.
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

if [[ "$MODE" == "distribution" ]]; then
  pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --component-plist "$COMPONENT_PLIST" \
    --scripts "$INSTALLER_SCRIPTS" \
    --install-location / \
    --identifier "$PACKAGE_ID" \
    --version "$PACKAGE_VERSION" \
    --sign "$INSTALLER_IDENTITY" \
    --timestamp \
    "$STAGED_PACKAGE"
else
  pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --component-plist "$COMPONENT_PLIST" \
    --scripts "$INSTALLER_SCRIPTS" \
    --install-location / \
    --identifier "$PACKAGE_ID" \
    --version "$PACKAGE_VERSION" \
    "$STAGED_PACKAGE"
fi

EXPANDED="$SCRATCH/expanded"
pkgutil --expand-full "$STAGED_PACKAGE" "$EXPANDED"

python3 - "$EXPANDED" "$PREINSTALL" "$POSTINSTALL" "$BUNDLE_ID" "$VERSION" "$BUILD_NUMBER" <<'PY'
import hashlib
from pathlib import Path
import sys

expanded = Path(sys.argv[1])
preinstall_source = Path(sys.argv[2])
postinstall_source = Path(sys.argv[3])
bundle_id, version, build = sys.argv[4:]
expected_sources = {"preinstall": preinstall_source, "postinstall": postinstall_source}
scripts = expanded / "Scripts"
if not scripts.is_dir() or scripts.is_symlink():
    raise SystemExit("A csomag saját Scripts mappája hiányzik.")
entries = list(scripts.iterdir())
if {entry.name for entry in entries} != set(expected_sources):
    raise SystemExit("A csomag váratlan installer scriptet tartalmaz.")
for name, source in expected_sources.items():
    actual = scripts / name
    if not actual.is_file() or actual.is_symlink() or not (actual.stat().st_mode & 0o111):
        raise SystemExit(f"A csomag {name} fájlja nem szabályos futtatható script.")
    expected_bytes = source.read_bytes()
    actual_bytes = actual.read_bytes()
    if name == "preinstall":
        expected_bytes = expected_bytes.replace(b"__ADBLOCKER_BUNDLE_ID__", bundle_id.encode())
        expected_bytes = expected_bytes.replace(b"__ADBLOCKER_MARKETING_VERSION__", version.encode())
        expected_bytes = expected_bytes.replace(b"__ADBLOCKER_BUNDLE_BUILD__", build.encode())
    if actual_bytes != expected_bytes or hashlib.sha256(actual_bytes).digest() != hashlib.sha256(expected_bytes).digest():
        raise SystemExit(f"A csomag {name} tartalma eltér az ellenőrzött forrástól.")
PY
[[ -z "$(find "$EXPANDED/Payload" \( -name '._*' -o -name '.DS_Store' \) -print -quit)" ]] || \
  fail "A payload váratlan Finder/AppleDouble metadatafájlt tartalmaz."

PACKAGE_INFO="$(find "$EXPANDED" -type f -name PackageInfo -print -quit)"
[[ -n "$PACKAGE_INFO" ]] || fail "A kibontott csomag PackageInfo fájlja hiányzik."
grep -Fq 'install-location="/"' "$PACKAGE_INFO" || \
  fail "A csomag install-location értéke nem a payload root."
grep -Fq "identifier=\"$PACKAGE_ID\"" "$PACKAGE_INFO" || \
  fail "A csomag identifier értéke eltér az elvárttól."
grep -Fq "version=\"$PACKAGE_VERSION\"" "$PACKAGE_INFO" || \
  fail "A csomag verziója eltér az elvárttól."

EXTRACTED_APPS="$(find "$EXPANDED" -type d -name '*.app' -prune -print)"
EXTRACTED_APP_COUNT="$(printf '%s\n' "$EXTRACTED_APPS" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$EXTRACTED_APP_COUNT" == "1" ]] || \
  fail "A csomag payloadjában pontosan egy .app szükséges; talált: $EXTRACTED_APP_COUNT"
EXTRACTED_APP="$EXTRACTED_APPS"
[[ "$EXTRACTED_APP" == */Payload/Applications/Ad\ Blocker.app ]] || \
  fail "A kibontott alkalmazás nem a determinisztikus /Applications payloadútvonalon van."

codesign --verify --deep --strict "$EXTRACTED_APP"
verify_bundle_architectures "$EXTRACTED_APP"
/usr/bin/diff -qr "$APP_PATH" "$EXTRACTED_APP" >/dev/null || \
  fail "A kibontott alkalmazás fájljai eltérnek az eredeti app fájljaitól."

if [[ "$MODE" == "distribution" ]]; then
  notary_result="$(xcrun notarytool submit "$STAGED_PACKAGE" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  python3 - "$notary_result" <<'PY'
import json
import sys

try:
    result = json.loads(sys.argv[1])
except json.JSONDecodeError as error:
    raise SystemExit(f"A notarytool nem értelmezhető választ adott: {error}")
if result.get("status") != "Accepted":
    raise SystemExit("A notarizálás nem Accepted eredménnyel zárult.")
PY
  xcrun stapler staple "$STAGED_PACKAGE"
  xcrun stapler validate "$STAGED_PACKAGE"
  bash "$CODE_DIR/scripts/verify-distribution-pkg.sh" "$STAGED_PACKAGE" "$TEAM" \
    "$APPLICATION_IDENTITY" "$INSTALLER_IDENTITY"
fi

mv "$STAGED_PACKAGE" "$OUTPUT_PATH"
PACKAGE_SHA256="$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
echo "Kész: $OUTPUT_PATH"
echo "SHA-256: $PACKAGE_SHA256"
if [[ "$MODE" == "distribution" ]]; then
  echo "Kiadási csomag: Developer ID-val aláírva, notarizálva és staplelve."
else
  echo "Helyi tesztcsomag: nincs Developer ID Installer aláírás vagy notarizálás."
fi
