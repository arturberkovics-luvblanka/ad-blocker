#!/bin/bash
set -euo pipefail

CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$CODE_DIR/tests/fixture/popup-projection-native.json"
SCRATCH="$(mktemp -d "/private/tmp/adblocker-native-popup-projection.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

/usr/bin/grep -Fq '/^https?:\/\/(35|104)\.(\d){1,3}\.(\d){1,3}\.(\d){1,3}\//$popup,third-party' \
  "$CODE_DIR/filters/adguard-base.txt"
/usr/bin/grep -Fq '/^https?:\/\/146\.59\.211\.(\d){1,3}.*/$popup,third-party' \
  "$CODE_DIR/filters/adguard-base.txt"

mkdir -p "$SCRATCH/rules" "$CODE_DIR/../builds/logs"
python3 - "$RULES" "$CODE_DIR/filters/blockerList.json" "$SCRATCH/product.json" <<'PYTHON'
import json, sys
legacy, product = (json.load(open(path)) for path in sys.argv[1:3])
selected = []
for rule in legacy:
    matches = [entry for entry in product if entry['action']['type'] == 'block'
               and entry['trigger']['url-filter'] == rule['trigger']['url-filter']]
    assert len(matches) == 1, matches
    selected.append(matches[0])
with open(sys.argv[3], 'w') as output:
    json.dump(selected, output)
PYTHON
xcrun --toolchain swift swiftc "$CODE_DIR/tests/NativePopupProjectionSmoke.swift" \
  -o "$SCRATCH/NativePopupProjectionSmoke" \
  -framework WebKit -framework AppKit -module-cache-path "$SCRATCH/modules"
"$SCRATCH/NativePopupProjectionSmoke" "$RULES" "$SCRATCH/rules" "$SCRATCH/product.json" \
  2>&1 | tee "$CODE_DIR/../builds/logs/native-popup-projection-webkit-smoke.log"
