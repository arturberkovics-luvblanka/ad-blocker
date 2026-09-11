#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-popup-webkit.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

RULE='sg.hu#%#//scriptlet("prevent-window-open", "bbelements.com")'
SOURCE_RULES="$CODE_DIR/filters/adguard-base.txt"
ADVANCED_RULES="$CODE_DIR/filters/generated/adguard-base-advanced.txt"

/usr/bin/grep -Fq "$RULE" "$SOURCE_RULES" || {
  echo "FAIL: pinned AdGuard source no longer contains the tested popup rule" >&2
  exit 1
}
/usr/bin/grep -Fq "$RULE" "$ADVANCED_RULES" || {
  echo "FAIL: advanced rule extraction no longer contains the tested popup rule" >&2
  exit 1
}

mkdir -p "$CODE_DIR/../builds/logs"
xcrun swiftc "$CODE_DIR/tests/PopupWebKitSmoke.swift" -o "$SCRATCH/PopupWebKitSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/PopupWebKitSmoke" "$CODE_DIR/extension/advanced-content-runtime.js" \
  2>&1 | tee "$CODE_DIR/../builds/logs/popup-webkit-smoke.log"
