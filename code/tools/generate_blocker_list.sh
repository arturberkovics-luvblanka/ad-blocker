#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
code_dir="$(cd "$script_dir/.." && pwd)"
converter="$code_dir/vendor/bin/ConverterTool"
debug_converter="$code_dir/vendor/bin/ConverterTool-debug"
base_input="$code_dir/filters/adguard-base.txt"
hufilter_input="$code_dir/filters/hufilter-adguard.txt"
local_input="$code_dir/filters/local-rules.txt"
output="$code_dir/filters/blockerList.json"
generated_dir="$code_dir/filters/generated"
advanced="$generated_dir/adguard-base-advanced.txt"
unsupported="$generated_dir/adguard-base-unsupported.log"
report="$generated_dir/conversion-report.json"

expected_base_input_sha="f55c87d2a6c08149f306fe62a8a3f42b5edc0663c897a3ae25a8d7c6a794fb4e"
expected_hufilter_input_sha="211b63f31366a3e70bca1cb764356628eefa62be08a896ee4165f856c652df1b"
expected_local_input_sha="757a320fdc3d49a5f12e5c0fee0c90b3aadf4770fbe1a2f0cad5ebade9f232ee"
expected_converter_sha="261c737bcf8392d6ebf427ae078f1cd29b7d2a9011a1ad502477170efad1bd59"
expected_debug_sha="9596017dcbad2d60cd52093340dd879b27c3e616f9ecded080231a6771a0b5e2"
expected_rule_set_sha="ec6869474fa0b6386228759d95d28774faf6e1e54f97d353c5790fcad4f800a3"
safari_version="26"

for command in jq rg shasum; do
    command -v "$command" >/dev/null || {
        echo "Hiányzó parancs: $command" >&2
        exit 1
    }
done

check_sha() {
    local expected="$1"
    local path="$2"
    local actual
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "SHA-256 eltérés: $path" >&2
        echo "Várt: $expected" >&2
        echo "Kapott: $actual" >&2
        exit 1
    fi
}

# Rebuilt executables vary with Xcode and the build path. This explicit mode
# records their actual hashes; source-list and expected-rule-set checks remain.
if [[ "${1:-}" == "--local-converter" && "$#" -eq 1 ]]; then
    expected_converter_sha="$(shasum -a 256 "$converter" | awk '{print $1}')"
    expected_debug_sha="$(shasum -a 256 "$debug_converter" | awk '{print $1}')"
elif [[ "$#" -ne 0 ]]; then
    echo 'Usage: generate_blocker_list.sh [--local-converter]' >&2
    exit 2
fi

check_sha "$expected_base_input_sha" "$base_input"
check_sha "$expected_hufilter_input_sha" "$hufilter_input"
check_sha "$expected_local_input_sha" "$local_input"
check_sha "$expected_converter_sha" "$converter"
check_sha "$expected_debug_sha" "$debug_converter"

mkdir -p "$generated_dir"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/adblock-conversion.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

input="$temporary_dir/combined-input.txt"
# The Base file has no final newline. Keep the independently frozen lists as
# distinct filter rules when building the temporary, offline converter input.
{
    cat "$base_input"
    printf '\n'
    cat "$hufilter_input"
    printf '\n'
    cat "$local_input"
} > "$input"

native="$temporary_dir/native.json"
debug_native="$temporary_dir/debug-native.json"
debug_advanced="$temporary_dir/debug-advanced.txt"
debug_log="$temporary_dir/debug.log"
metrics="$temporary_dir/metrics.json"
staged_output="$temporary_dir/blockerList.json"
staged_advanced="$temporary_dir/adguard-base-advanced.txt"
staged_unsupported="$temporary_dir/adguard-base-unsupported.log"
staged_report="$temporary_dir/conversion-report.json"

"$converter" convert \
    --input-path "$input" \
    --safari-version "$safari_version" \
    --advanced-blocking true \
    --safari-rules-json-path "$native" \
    --advanced-blocking-rules-path "$staged_advanced"

"$converter" convert \
    --input-path "$input" \
    --safari-version "$safari_version" \
    --advanced-blocking true \
    | jq '{sourceRulesCount, sourceSafariCompatibleRulesCount, safariRulesCount,
        advancedRulesCount, discardedSafariRules, errorsCount,
        safariRulesJSONBytes: (.safariRulesJSON | utf8bytelength),
        advancedRulesTextBytes: ((.advancedRulesText // "") | utf8bytelength)}' \
        > "$metrics"

"$debug_converter" convert \
    --input-path "$input" \
    --safari-version "$safari_version" \
    --advanced-blocking true \
    --safari-rules-json-path "$debug_native" \
    --advanced-blocking-rules-path "$debug_advanced" \
    > "$debug_log"

rg '^\((RuleFactory|BlockerEntryFactory)\) - Unexpected error:' \
    "$debug_log" > "$staged_unsupported"

jq -S -c '. + [
    {
      "trigger": {
        "url-filter": "^http://127\\.0\\.0\\.1:8765/fixture-ad\\.js",
        "resource-type": ["script"]
      },
      "action": {"type": "block"}
    },
    {
      "trigger": {
        "url-filter": ".*",
        "if-domain": ["127.0.0.1"]
      },
      "action": {
        "type": "css-display-none",
        "selector": "#fixture-ad-box"
      }
    },
    {
      "trigger": {
        "url-filter": "^http://127\\.0\\.0\\.1:[0-9]+/adblocker-self-test-blocked\\.svg[?]session=[0-9a-f]+$",
        "resource-type": ["image"]
      },
      "action": {"type": "block"}
    }
  ]' "$native" > "$staged_output"

native_count="$(jq -r '.safariRulesCount' "$metrics")"
advanced_count="$(jq -r '.advancedRulesCount' "$metrics")"
errors_count="$(jq -r '.errorsCount' "$metrics")"
unsupported_count="$(wc -l < "$staged_unsupported" | tr -d ' ')"
final_count="$(jq 'length' "$staged_output")"

[[ "$final_count" -eq $((native_count + 3)) ]]
[[ "$unsupported_count" -eq "$errors_count" ]]
[[ "$(wc -l < "$staged_advanced" | tr -d ' ')" -eq $((advanced_count - 1)) ]]

output_sha="$(shasum -a 256 "$staged_output" | awk '{print $1}')"
advanced_sha="$(shasum -a 256 "$staged_advanced" | awk '{print $1}')"
unsupported_sha="$(shasum -a 256 "$staged_unsupported" | awk '{print $1}')"
combined_input_sha="$(shasum -a 256 "$input" | awk '{print $1}')"
rule_set_sha="$(jq -S -c '.[]' "$staged_output" | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')"

if [[ "$rule_set_sha" != "$expected_rule_set_sha" ]]; then
    echo "A végleges lista szabálykészlete eltér a rögzített eredménytől." >&2
    echo "Várt: $expected_rule_set_sha" >&2
    echo "Kapott: $rule_set_sha" >&2
    exit 1
fi

jq -n \
    --slurpfile metrics "$metrics" \
    --arg converterVersion "4.3.0" \
    --arg converterRevision "7a2e93f0afa70479cc59985f332025236c3f0c39" \
    --arg converterSHA256 "$expected_converter_sha" \
    --arg baseVersion "2.4.89.22" \
    --arg baseUpdated "2026-09-09T12:20:56+00:00" \
    --arg baseSHA256 "$expected_base_input_sha" \
    --arg hufilterVersion "202609081912" \
    --arg hufilterUpdated "2026-09-08T19:12:00+00:00" \
    --arg hufilterSHA256 "$expected_hufilter_input_sha" \
    --arg localSHA256 "$expected_local_input_sha" \
    --arg combinedInputSHA256 "$combined_input_sha" \
    --argjson safariVersion "$safari_version" \
    --argjson sentinelRules 3 \
    --argjson finalSafariRules "$final_count" \
    --arg outputSHA256 "$output_sha" \
    --arg ruleSetSHA256 "$rule_set_sha" \
    --arg advancedSHA256 "$advanced_sha" \
    --arg unsupportedSHA256 "$unsupported_sha" \
    '{
      converter: {
        version: $converterVersion,
        revision: $converterRevision,
        localPatches: ["native-popup-resource-type-with-document-fallback"],
        binarySHA256: $converterSHA256
      },
      inputs: {
        combinedSHA256: $combinedInputSHA256,
        sources: [
          {
            name: "AdGuard Base filter",
            version: $baseVersion,
            updated: $baseUpdated,
            sha256: $baseSHA256
          },
          {
            name: "Hufilter for AdGuard",
            version: $hufilterVersion,
            updated: $hufilterUpdated,
            revision: "1832f017a963e4b96183e7865670a5cdd91ce263",
            sourceRevision: "9a62d00504244bcbab1051e49acd5240997332a6",
            sha256: $hufilterSHA256
          },
          {
            name: "Ad Blocker local supplementary rules",
            sha256: $localSHA256
          }
        ]
      },
      safariVersion: $safariVersion,
      conversion: $metrics[0],
      projectSentinelRules: $sentinelRules,
      finalSafariRules: $finalSafariRules,
      outputs: {
        blockerListSHA256: $outputSHA256,
        ruleMultisetSHA256: $ruleSetSHA256,
        advancedRulesSHA256: $advancedSHA256,
        unsupportedRulesSHA256: $unsupportedSHA256
      },
      verification: {
        jsonRuleCountCheck: "passed",
        errorLogCountCheck: "passed",
        webKitCompilation: {
          status: "not-run-by-generator"
        }
      }
    }' > "$staged_report"

# Csak az összes ellenőrzés után cseréljük le a befagyasztott fájlokat.
mv "$staged_output" "$output"
mv "$staged_advanced" "$advanced"
mv "$staged_unsupported" "$unsupported"
mv "$staged_report" "$report"

echo "Kész: $output ($final_count szabály)"
echo "Advanced: $advanced_count; konverziós hiba: $errors_count"
echo "A generált pontos bájtsorrend WebKit-ellenőrzése még nem futott le."
