#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANDIDATE="${1:-$CODE_DIR/filters/blockerList.json}"

[[ -f "$CANDIDATE" ]] || { echo "Hiányzó jelölt lista: $CANDIDATE" >&2; exit 1; }
curl --fail --silent --max-time 3 http://127.0.0.1:8765/media-net-script.js >/dev/null || {
  echo 'A meglévő helyi fixture-szerver nem érhető el a 127.0.0.1:8765 címen.' >&2
  exit 1
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-media-net-webkit.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
xcrun swiftc "$CODE_DIR/tests/MediaNetWebKitSmoke.swift" -o "$SCRATCH/MediaNetWebKitSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/MediaNetWebKitSmoke" "$CANDIDATE" "$SCRATCH/rules"
