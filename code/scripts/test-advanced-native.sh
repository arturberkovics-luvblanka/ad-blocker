#!/bin/bash
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/adblocker-native-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/Sources/NativeTests" "$CODE_DIR/../builds/logs"
cp "$CODE_DIR/Sources/WebExtension/AdvancedRuleStore.swift" "$CODE_DIR/tests/AdvancedRuleStoreTests.swift" "$SCRATCH/Sources/NativeTests/"
python3 - "$CODE_DIR" "$SCRATCH" <<'PY'
import json
import sys
from pathlib import Path
root, scratch = map(Path, sys.argv[1:])
path = json.dumps(str(root / 'vendor/SafariConverterLib'))
(scratch / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "NativeTests", platforms: [.macOS(.v14)],
    dependencies: [.package(path: PATH)],
    targets: [.executableTarget(name: "NativeTests", dependencies: [
        .product(name: "ContentBlockerConverter", package: "SafariConverterLib")
    ])])
'''.replace('PATH', path))
PY
swift run --package-path "$SCRATCH" --scratch-path "${TMPDIR:-/tmp}/adblocker-native-tests-build" NativeTests \
  "$CODE_DIR/filters/generated/adguard-base-advanced.txt" "$SCRATCH/cache" \
  "$CODE_DIR/../builds/logs/youtube-configuration.json" \
  2>&1 | tee "$CODE_DIR/../builds/logs/advanced-native-tests.log"
