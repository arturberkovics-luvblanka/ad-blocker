#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$CODE_DIR")"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-native-activation.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$PROJECT_DIR/builds/logs"
xcrun swiftc "$CODE_DIR/Sources/App/NativeRuleActivation.swift" "$CODE_DIR/tests/NativeRuleActivationTests.swift" \
  -o "$SCRATCH/NativeRuleActivationTests" -module-cache-path "$SCRATCH/modules"
"$SCRATCH/NativeRuleActivationTests" 2>&1 | tee "$PROJECT_DIR/builds/logs/native-rule-activation.log"
