#!/bin/bash
# Rebuild the two development tools from the bundled, modified Swift sources.
set -euo pipefail
CODE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d /private/tmp/adblocker-converters.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$CODE_DIR/vendor/bin"
for configuration in release debug; do
  xcrun swift build --package-path "$CODE_DIR/vendor/SafariConverterLib" \
    --scratch-path "$SCRATCH/$configuration" --disable-sandbox \
    -c "$configuration" --product ConverterTool
  # Xcode 27's SwiftPM backend uses Products instead of the older triple path.
  tool="$(find "$SCRATCH/$configuration" -type f -name ConverterTool -perm +111 -print -quit)"
  [[ -n "$tool" ]] || { echo 'ConverterTool build output missing' >&2; exit 1; }
  destination="$CODE_DIR/vendor/bin/ConverterTool"
  [[ "$configuration" == release ]] || destination="$destination-debug"
  cp "$tool" "$destination"
  bundle="$(find "$(dirname "$tool")" -maxdepth 1 -type d -name swift-psl_PublicSuffixList.bundle -print -quit)"
  [[ -n "$bundle" ]] || { echo 'Public Suffix List resource bundle missing' >&2; exit 1; }
  ditto --norsrc --noextattr "$bundle" "$CODE_DIR/vendor/bin/swift-psl_PublicSuffixList.bundle"
done
shasum -a 256 "$CODE_DIR/vendor/bin/ConverterTool" "$CODE_DIR/vendor/bin/ConverterTool-debug"
echo 'To regenerate using these local builds: bash code/tools/generate_blocker_list.sh --local-converter'
