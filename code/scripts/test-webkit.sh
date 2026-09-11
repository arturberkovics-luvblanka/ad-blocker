#!/bin/bash
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
if ! curl --fail --silent --max-time 3 http://127.0.0.1:8765/ >/dev/null; then
  echo 'Előbb indítsd el külön terminálban: python3 code/scripts/serve_fixture.py' >&2
  exit 1
fi
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-webkit.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/rules" "$PROJECT_DIR/builds/logs"
xcrun swiftc "$CODE_DIR/tests/WebKitSmoke.swift" -o "$SCRATCH/WebKitSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/WebKitSmoke" "$CODE_DIR/filters/blockerList.json" "$SCRATCH/rules" \
  2>&1 | tee "$PROJECT_DIR/builds/logs/webkit-smoke.log"

REPORT="$CODE_DIR/filters/generated/conversion-report.json"
RULE_SHA="$(shasum -a 256 "$CODE_DIR/filters/blockerList.json" | awk '{print $1}')"
OS_VERSION="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
REPORT_TMP="$(mktemp "${TMPDIR:-/tmp}/adblocker-webkit-report.XXXXXX")"
trap 'rm -rf "$SCRATCH" "$REPORT_TMP"' EXIT
jq --arg sha "$RULE_SHA" --arg tested_on "$(date -u +%F)" --arg macos "$OS_VERSION" \
  '.verification.webKitCompilation = {
    status: "passed",
    testedOutputSHA256: $sha,
    testedOn: $tested_on,
    macOS: $macos
  }' "$REPORT" > "$REPORT_TMP"
mv "$REPORT_TMP" "$REPORT"
