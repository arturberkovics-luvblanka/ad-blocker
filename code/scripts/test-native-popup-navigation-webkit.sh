#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
curl --fail --silent --max-time 3 http://127.0.0.1:8765/native-popup-navigation.html >/dev/null || {
  echo 'A meglévő helyi fixture-szerver nem érhető el a 127.0.0.1:8765 címen.' >&2
  exit 1
}
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-native-popup-navigation.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$PROJECT_DIR/builds/logs" "$SCRATCH/rules"
xcrun swiftc "$CODE_DIR/tests/NativePopupNavigationSmoke.swift" -o "$SCRATCH/NativePopupNavigationSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/NativePopupNavigationSmoke" "$SCRATCH/rules" \
  2>&1 | tee "$PROJECT_DIR/builds/logs/native-popup-navigation-webkit-smoke.log"
