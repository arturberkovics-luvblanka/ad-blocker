#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Használat: build.sh [macOS|iOS] [Debug|Release] [--distribution]

A --distribution csak macOS Release builddel használható. Kötelező környezeti
változók: ADBLOCKER_DEVELOPMENT_TEAM és ADBLOCKER_DEVELOPER_ID_APPLICATION.
Az utóbbi pontosan a Keychainben levő "Developer ID Application: ..." identity.
EOF
  exit 2
}

fail() {
  echo "HIBA: $*" >&2
  exit 1
}

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
PLATFORM="${1:-macOS}"
CONFIGURATION="${2:-Debug}"
MODE="local"
if [[ "${3:-}" == "--distribution" ]]; then
  MODE="distribution"
elif [[ -n "${3:-}" ]]; then
  usage
fi
case "$PLATFORM" in macOS|iOS) ;; *) usage ;; esac
case "$CONFIGURATION" in Debug|Release) ;; *) usage ;; esac
[[ "$MODE" == "local" || ("$PLATFORM" == "macOS" && "$CONFIGURATION" == "Release") ]] || \
  fail "A kiadási build kizárólag macOS Release konfiguráció lehet."
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$CODE_DIR/extension/manifest.json")"
# iCloud Desktop adds FinderInfo to .appex folders, which breaks codesigning.
# Keep intermediate products in the user's temporary directory.
DERIVED_DATA="${ADBLOCKER_DERIVED_DATA:-${TMPDIR:-/tmp}/adblocker-$(id -u)/DerivedData-$PLATFORM-$MODE}"
case "$PLATFORM" in
  macOS)
    DESTINATION='platform=macOS'
    if [[ "$MODE" == "distribution" ]]; then
      TEAM="${ADBLOCKER_DEVELOPMENT_TEAM:-}"
      APPLICATION_IDENTITY="${ADBLOCKER_DEVELOPER_ID_APPLICATION:-}"
      [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail "Az ADBLOCKER_DEVELOPMENT_TEAM értéke egy 10 karakteres Team ID legyen."
      [[ "$APPLICATION_IDENTITY" == Developer\ ID\ Application:* ]] || \
        fail "Az ADBLOCKER_DEVELOPER_ID_APPLICATION Developer ID Application identity legyen."
      [[ "$APPLICATION_IDENTITY" == *"($TEAM)" ]] || \
        fail "A Developer ID Application identity Team ID-ja eltér az ADBLOCKER_DEVELOPMENT_TEAM értékétől."
      security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$APPLICATION_IDENTITY" || \
        fail "A megadott Developer ID Application identity nem található a bejelentkezett Keychainben."
      SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES "CODE_SIGN_IDENTITY=$APPLICATION_IDENTITY" "DEVELOPMENT_TEAM=$TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp)
    else
      SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-)
    fi
    ;;
  iOS) DESTINATION='generic/platform=iOS'; SIGNING=(CODE_SIGNING_ALLOWED=NO) ;;
esac
test -s "$CODE_DIR/filters/blockerList.json" || { echo 'Hiányzó szűrőlista.' >&2; exit 1; }
python3 "$CODE_DIR/scripts/verify_runtime.py"
python3 "$CODE_DIR/scripts/generate_project.py"
mkdir -p "$PROJECT_DIR/builds/logs"
LOG_FILE="$(mktemp "$PROJECT_DIR/builds/logs/build-${PLATFORM}-${MODE}.XXXXXX")"
# Apply the mapping to package targets as well as the three app targets.
# Xcode expands each quoted SRCROOT, including roots that contain spaces.
PREFIX_MAP_FLAGS='$(inherited) -debug-prefix-map "$(SRCROOT)=/AdBlocker" -file-prefix-map "$(SRCROOT)=/AdBlocker"'
xcodebuild -project "$CODE_DIR/AdBlocker.xcodeproj" -scheme "AdBlocker-$PLATFORM" \
  -configuration "$CONFIGURATION" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  "${SIGNING[@]}" "OTHER_SWIFT_FLAGS=$PREFIX_MAP_FLAGS" ARCHS=arm64 build 2>&1 | tee "$LOG_FILE"
if [ "$PLATFORM" = macOS ]; then
  APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Ad Blocker.app"
  codesign --verify --deep --strict "$APP"
  if [[ "$MODE" == "distribution" ]]; then
    python3 "$CODE_DIR/scripts/verify_macos.py" --distribution \
      --team "$TEAM" --application-identity "$APPLICATION_IDENTITY" "$APP"
    echo "Aláírt alkalmazás készült. Ez még nem kiadható: a .pkg notarizálását a package-macos.sh --distribution végzi."
  else
    python3 "$CODE_DIR/scripts/verify_macos.py" "$APP"
  fi
  mkdir -p "$PROJECT_DIR/builds/macOS"
  if [[ "$MODE" == "local" ]]; then
    # Keep a test zip on iCloud Desktop: FinderInfo can reappear on unpacked apps.
    ditto -c -k --keepParent --norsrc --noextattr "$APP" "$PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
    echo "Helyi tesztcsomag: $PROJECT_DIR/builds/macOS/AdBlocker-$VERSION-macOS.zip"
  fi
else
  echo 'Az iOS build aláírás nélkül készült; fizikai készülékre még nem telepíthető.'
fi
echo "Buildnapló: $LOG_FILE"
