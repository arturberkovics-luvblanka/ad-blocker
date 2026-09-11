#!/bin/bash
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-advanced-webkit.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$CODE_DIR/../builds/logs"
xcrun swiftc "$CODE_DIR/tests/AdvancedWebKitSmoke.swift" -o "$SCRATCH/AdvancedSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/AdvancedSmoke" "$CODE_DIR/extension/advanced-content-runtime.js" \
  "$CODE_DIR/extension-runtime/build-manifest.json" \
  2>&1 | tee "$CODE_DIR/../builds/logs/advanced-webkit-smoke.log"
