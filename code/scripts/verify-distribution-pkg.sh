#!/bin/bash
# Verify the exact, already-notarized Developer ID package that will be shared.
set -euo pipefail

usage() {
  echo "Használat: verify-distribution-pkg.sh PKG TEAM_ID 'Developer ID Application: …' 'Developer ID Installer: …'" >&2
  exit 2
}

fail() {
  echo "HIBA: $*" >&2
  exit 1
}

[[ $# == 4 ]] || usage
PACKAGE="$1"
TEAM="$2"
APPLICATION_IDENTITY="$3"
INSTALLER_IDENTITY="$4"
[[ -f "$PACKAGE" && "$PACKAGE" == *.pkg && ! -L "$PACKAGE" ]] || fail "Érvénytelen .pkg fájl: $PACKAGE"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || usage
[[ "$APPLICATION_IDENTITY" == Developer\ ID\ Application:* ]] || usage
[[ "$INSTALLER_IDENTITY" == Developer\ ID\ Installer:* ]] || usage

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
for command in pkgutil spctl xcrun mktemp; do command -v "$command" >/dev/null || fail "Hiányzó eszköz: $command"; done

signature="$(pkgutil --check-signature "$PACKAGE")" || fail "A .pkg aláírása nem ellenőrizhető."
grep -Fq "$INSTALLER_IDENTITY" <<< "$signature" || fail "A .pkg nem a várt Developer ID Installer identityvel aláírt."
grep -Fqi "trusted" <<< "$signature" || fail "A .pkg tanúsítványlánca nem megbízható."

# Gatekeeper és a beágyazott notarizációs ticket ellenőrzése külön kapu.
spctl -a -vv -t install "$PACKAGE" >/dev/null
xcrun stapler validate "$PACKAGE" >/dev/null

scratch="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-distribution-verify.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
pkgutil --expand-full "$PACKAGE" "$scratch/expanded"
payload="$scratch/expanded/Payload"
[[ -d "$payload/Applications" ]] || fail "A payloadból hiányzik az Applications mappa."
[[ "$(find "$payload" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == 1 ]] || \
  fail "A payload az Applications mappán kívül további fájlt tartalmaz."
[[ "$(find "$payload/Applications" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == 1 ]] || \
  fail "Az Applications payload pontosan egy appot tartalmazzon."
apps=()
while IFS= read -r app; do apps+=("$app"); done < <(find "$scratch/expanded" -type d -name '*.app' -path '*/Payload/Applications/*.app' -prune -print)
[[ ${#apps[@]} == 1 ]] || fail "A .pkg pontosan egy /Applications alatti appot tartalmazzon."
[[ "${apps[0]}" == "$payload/Applications/Ad Blocker.app" ]] || fail "A csomag appútvonala nem az exact /Applications/Ad Blocker.app."
app_plist="${apps[0]}/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_plist")"
marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_plist")"
package_info="$(find "$scratch/expanded" -type f -name PackageInfo -print -quit)"
[[ -n "$package_info" ]] || fail "A csomag PackageInfo fájlja hiányzik."
grep -Fq 'install-location="/"' "$package_info" || fail "A package install-location nem a payload gyökere."
grep -Fq "identifier=\"$bundle_id.installer\"" "$package_info" || fail "A package identifier eltér az apptól."
grep -Fq "version=\"$marketing_version.$build_number\"" "$package_info" || fail "A package verzió eltér az apptól."
scripts="$scratch/expanded/Scripts"
[[ -d "$scripts" && ! -L "$scripts" ]] || fail "A csomag Scripts mappája hibás."
[[ "$(find "$scripts" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == 2 ]] || fail "A csomag nem pontosan két installer scriptet tartalmaz."
python3 - "$scripts" "$CODE_DIR/installer/preinstall" "$CODE_DIR/installer/postinstall" "$bundle_id" "$marketing_version" "$build_number" <<'PY'
from pathlib import Path
import sys

scripts = Path(sys.argv[1])
pre_source, post_source = map(Path, sys.argv[2:4])
bundle_id, version, build = sys.argv[4:]
expected_pre = pre_source.read_bytes()
for marker, value in {
    b"__ADBLOCKER_BUNDLE_ID__": bundle_id.encode(),
    b"__ADBLOCKER_MARKETING_VERSION__": version.encode(),
    b"__ADBLOCKER_BUNDLE_BUILD__": build.encode(),
}.items():
    if expected_pre.count(marker) != 1:
        raise SystemExit(f"Invalid preinstall template marker: {marker!r}")
    expected_pre = expected_pre.replace(marker, value)
expected = {"preinstall": expected_pre, "postinstall": post_source.read_bytes()}
actual_entries = {entry.name: entry for entry in scripts.iterdir()}
if set(actual_entries) != set(expected):
    raise SystemExit("Unexpected installer script names")
for name, contents in expected.items():
    actual = actual_entries[name]
    if not actual.is_file() or actual.is_symlink() or not (actual.stat().st_mode & 0o111):
        raise SystemExit(f"Invalid installer script: {name}")
    if actual.read_bytes() != contents:
        raise SystemExit(f"Installer script differs: {name}")
PY
python3 "$CODE_DIR/scripts/verify_macos.py" --distribution \
  --team "$TEAM" --application-identity "$APPLICATION_IDENTITY" "${apps[0]}"

echo "PASS: exact notarized Developer ID distribution package: $PACKAGE"
