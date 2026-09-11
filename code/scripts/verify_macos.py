#!/usr/bin/env python3
"""Check a macOS app's structure, bundled inputs, and optional release signing."""
import hashlib
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

def usage():
    raise SystemExit(
        "Usage: verify_macos.py [--distribution --team TEAM_ID "
        "--application-identity 'Developer ID Application: …'] APP_PATH"
    )


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def signing_details(bundle: Path) -> str:
    result = subprocess.run(
        ["codesign", "-dvv", "--verbose=4", str(bundle)],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout + result.stderr


def entitlements(bundle: Path) -> dict:
    result = subprocess.run(
        ["codesign", "--display", "--entitlements", ":-", str(bundle)],
        capture_output=True,
        check=True,
    )
    raw = result.stdout
    start = raw.find(b"<?xml")
    if start < 0:
        return {}
    return plistlib.loads(raw[start:])


arguments = sys.argv[1:]
distribution = False
team = None
application_identity = None
if arguments and arguments[0] == "--distribution":
    distribution = True
    arguments = arguments[1:]
    while arguments and arguments[0].startswith("--"):
        option = arguments.pop(0)
        if option == "--team" and arguments:
            team = arguments.pop(0)
        elif option == "--application-identity" and arguments:
            application_identity = arguments.pop(0)
        else:
            usage()
if len(arguments) != 1:
    usage()
if distribution and (not team or not application_identity or not team.isalnum() or len(team) != 10):
    usage()

root = Path(__file__).resolve().parents[1]
app = Path(arguments[0])
with (app / "Contents/Info.plist").open("rb") as file:
    host_info = plistlib.load(file)
require(host_info["CFBundleIdentifier"] == "org.local.adblocker", "Wrong app identifier")
require(host_info.get("LSUIElement") is True, "macOS host must run without a Dock icon")
source_manifest = json.loads((root / "extension/manifest.json").read_text())
require(host_info["CFBundleShortVersionString"] == source_manifest["version"], "Wrong app version")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

if distribution:
    for bundle in [app, *(app / "Contents/PlugIns").glob("*.appex")]:
        details = signing_details(bundle)
        require(f"TeamIdentifier={team}" in details, f"Wrong Team ID: {bundle}")
        require(f"Authority={application_identity}" in details, f"Missing Developer ID Application signing: {bundle}")
        require("Timestamp=" in details, f"Missing secure signing timestamp: {bundle}")
        require(re.search(r"^flags=.*\(.*runtime", details, re.MULTILINE) is not None, f"Missing Hardened Runtime: {bundle}")
        require(entitlements(bundle).get("get-task-allow") is not True, f"Debug entitlement is enabled: {bundle}")
    require(entitlements(app).get("com.apple.security.network.server") is True, "Missing loopback-server entitlement")

plugins = sorted((app / "Contents/PlugIns").glob("*.appex"), key=lambda path: path.name)
require([plugin.name for plugin in plugins] == ["AdBlockerContentBlocker.appex", "AdBlockerWebExtension.appex"],
        "The host must contain exactly the two expected Safari extensions")
for name, point in (("ContentBlocker", "content-blocker"), ("WebExtension", "web-extension")):
    plugin = app / f"Contents/PlugIns/AdBlocker{name}.appex"
    with (plugin / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    require(info["CFBundleIdentifier"] == f"org.local.adblocker.{name}", f"Wrong extension identifier: {name}")
    require(info["NSExtension"]["NSExtensionPointIdentifier"] == f"com.apple.Safari.{point}", f"Wrong extension point: {name}")
    require(info["CFBundleShortVersionString"] == host_info["CFBundleShortVersionString"], f"Mixed extension version: {name}")
    require(info["CFBundleVersion"] == host_info["CFBundleVersion"], f"Mixed extension build versions: {name}")
    if name == "ContentBlocker":
        binary = plugin / "Contents/MacOS/AdBlockerContentBlocker.debug.dylib"
        if not binary.exists():
            binary = plugin / "Contents/MacOS/AdBlockerContentBlocker"
        linked = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        require("/Cocoa.framework/" in linked or "/AppKit.framework/" in linked, "Missing macOS extension subsystem linkage")

report = json.loads((root / "filters/generated/conversion-report.json").read_text())
bundled_rules = app / "Contents/PlugIns/AdBlockerContentBlocker.appex/Contents/Resources/blockerList.json"
rules_bytes = bundled_rules.read_bytes()
require(hashlib.sha256(rules_bytes).hexdigest() == report["outputs"]["blockerListSHA256"], "Bundled rule hash differs from report")
require(len(json.loads(rules_bytes)) == report["finalSafariRules"], "Rule count mismatch")
resources = app / "Contents/Resources"
require((resources / "LICENSE").is_file(), "Missing license")
require((resources / "LICENSE-Hufilter-CC-BY-4.0.txt").is_file(), "Missing Hufilter license")
require((resources / "THIRD_PARTY_NOTICES.md").is_file(), "Missing notices")
require(json.loads((resources / "conversion-report.json").read_text()) == report, "Bundled report differs")
runtime_manifest = root / "extension-runtime/build-manifest.json"
require((resources / "build-manifest.json").read_bytes() == runtime_manifest.read_bytes(), "Bundled runtime manifest differs")
for fixture in sorted((root / "Resources/SelfTest").iterdir()):
    if fixture.is_file():
        bundled_fixture = resources / fixture.name
        require(bundled_fixture.read_bytes() == fixture.read_bytes(), f"Bundled self-test fixture differs: {fixture.name}")
manifest = json.loads((app / "Contents/PlugIns/AdBlockerWebExtension.appex/Contents/Resources/manifest.json").read_text())
require(manifest["version"] == host_info["CFBundleShortVersionString"], "Web manifest version differs")
web_resources = app / "Contents/PlugIns/AdBlockerWebExtension.appex/Contents/Resources"
advanced = (root / "filters/generated/adguard-base-advanced.txt").read_bytes()
require((web_resources / "adguard-base-advanced.txt").read_bytes() == advanced, "Advanced source differs")
generation = hashlib.sha256(advanced).hexdigest()
require(generation in (root / "Sources/WebExtension/AdvancedRuleStore.swift").read_text(), "Native generation differs")
for source in (root / "extension").iterdir():
    if source.is_file():
        require((web_resources / source.name).read_bytes() == source.read_bytes(), f"Web resource differs: {source.name}")
psl_bundle = web_resources / "swift-psl_PublicSuffixList.bundle/Contents/Resources"
for name in ("common.bin", "negated.bin", "asterisk.bin", "version.txt"):
    require((psl_bundle / name).is_file(), f"Missing suffix data: {name}")
mode = "Developer ID-signed distribution app" if distribution else "local test app"
print(f"PASS: {mode} + two extensions + licenses + {report['finalSafariRules']} native rules + advanced generation {generation} + web resources")
