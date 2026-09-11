#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "/private/tmp/adblocker-cookiebot-public-sdk.XXXXXX")"
LOG="$CODE_DIR/../builds/logs/cookiebot-public-sdk-probe.log"
trap 'rm -rf "$SCRATCH"' EXIT

mkdir -p "$(dirname "$LOG")"
xcrun --toolchain swift swiftc "$CODE_DIR/tests/CookiebotPublicSDKProbe.swift" \
  -o "$SCRATCH/CookiebotPublicSDKProbe" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/CookiebotPublicSDKProbe" 2>&1 | tee "$LOG"

