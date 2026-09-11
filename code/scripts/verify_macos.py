#!/usr/bin/env python3
"""Check signed packaging and that the bundled rules match the reviewed inputs."""
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1])
with (app / "Contents/Info.plist").open("rb") as file:
    host_info = plistlib.load(file)
assert host_info["CFBundleIdentifier"] == "org.local.adblocker", "Wrong app identifier"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

for name, point in (("ContentBlocker", "content-blocker"), ("WebExtension", "web-extension")):
    plugin = app / f"Contents/PlugIns/AdBlocker{name}.appex"
    with (plugin / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    assert info["CFBundleIdentifier"] == f"org.local.adblocker.{name}"
    assert info["NSExtension"]["NSExtensionPointIdentifier"] == f"com.apple.Safari.{point}"
    assert info["CFBundleShortVersionString"] == host_info["CFBundleShortVersionString"]
    if name == "ContentBlocker":
        binary = plugin / "Contents/MacOS/AdBlockerContentBlocker.debug.dylib"
        if not binary.exists():
            binary = plugin / "Contents/MacOS/AdBlockerContentBlocker"
        linked = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        assert "/Cocoa.framework/" in linked or "/AppKit.framework/" in linked, "Missing macOS extension subsystem linkage"

report = json.loads((root / "filters/generated/conversion-report.json").read_text())
bundled_rules = app / "Contents/PlugIns/AdBlockerContentBlocker.appex/Contents/Resources/blockerList.json"
rules_bytes = bundled_rules.read_bytes()
assert hashlib.sha256(rules_bytes).hexdigest() == report["outputs"]["blockerListSHA256"], "Bundled rule hash differs from report"
assert len(json.loads(rules_bytes)) == report["finalSafariRules"], "Rule count mismatch"
resources = app / "Contents/Resources"
assert (resources / "LICENSE").is_file(), "Missing license"
assert (resources / "LICENSE-Hufilter-CC-BY-4.0.txt").is_file(), "Missing Hufilter license"
assert (resources / "THIRD_PARTY_NOTICES.md").is_file(), "Missing notices"
assert json.loads((resources / "conversion-report.json").read_text()) == report, "Bundled report differs"
manifest = json.loads((app / "Contents/PlugIns/AdBlockerWebExtension.appex/Contents/Resources/manifest.json").read_text())
assert manifest["version"] == host_info["CFBundleShortVersionString"]
web_resources = app / "Contents/PlugIns/AdBlockerWebExtension.appex/Contents/Resources"
advanced = (root / "filters/generated/adguard-base-advanced.txt").read_bytes()
assert (web_resources / "adguard-base-advanced.txt").read_bytes() == advanced, "Advanced source differs"
generation = hashlib.sha256(advanced).hexdigest()
assert generation in (root / "Sources/WebExtension/AdvancedRuleStore.swift").read_text(), "Native generation differs"
for source in (root / "extension").iterdir():
    if source.is_file():
        assert (web_resources / source.name).read_bytes() == source.read_bytes(), f"Web resource differs: {source.name}"
psl_bundle = web_resources / "swift-psl_PublicSuffixList.bundle/Contents/Resources"
for name in ("common.bin", "negated.bin", "asterisk.bin", "version.txt"):
    assert (psl_bundle / name).is_file(), f"Missing suffix data: {name}"
print(f"PASS: signed app + two extensions + licenses + {report['finalSafariRules']} native rules + advanced generation {generation} + web resources")
