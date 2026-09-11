#!/usr/bin/env python3
"""Reject stale generated JS without installing Node packages during app builds."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
upstream = root / "vendor/SafariConverterLib/Extension"
report = json.loads((root / "extension-runtime/build-manifest.json").read_text())
assert report["schemaVersion"] == 2

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

sources = hashlib.sha256()
for path in sorted((upstream / "src").rglob("*")):
    if path.is_file():
        sources.update(str(path.relative_to(upstream / "src")).encode())
        sources.update(b"\0")
        sources.update(path.read_bytes())
        sources.update(b"\0")

frontend = hashlib.sha256()
for path in sorted((root / "extension").rglob("*")):
    if path.is_file() and str(path.relative_to(root / "extension")) not in {"advanced-content-runtime.js", "advanced-background-runtime.js", "early-youtube.js"}:
        frontend.update(str(path.relative_to(root / "extension")).encode())
        frontend.update(b"\0")
        frontend.update(path.read_bytes())
        frontend.update(b"\0")

expected = {
    "generator": digest(root / "scripts/build-extension-runtime.mjs"),
    "contentEntry": digest(root / "extension-runtime/content-entry.mjs"),
    "frontendSource": frontend.hexdigest(),
    "documentBackground": digest(root / "extension-runtime/document-background.mjs"),
    "earlyYoutubePolicy": digest(root / "extension-runtime/early-youtube-policy.mjs"),
    "upstreamSource": sources.hexdigest(),
    "upstreamPackage": digest(upstream / "package.json"),
    "upstreamTsconfig": digest(upstream / "tsconfig.json"),
    "upstreamLock": digest(upstream / "pnpm-lock.yaml"),
    "advancedRules": digest(root / "filters/generated/adguard-base-advanced.txt"),
}
assert report["inputs"] == expected, "Runtime source changed; run node code/scripts/build-extension-runtime.mjs"
revision = hashlib.sha256(json.dumps(expected, separators=(",", ":")).encode()).hexdigest()
assert report["runtimeRevision"] == revision, "Wrong runtime revision"
assert report["generation"] == expected["advancedRules"], "Wrong runtime rule generation"
assert set(report["outputs"]) == {"advanced-content-runtime.js", "advanced-background-runtime.js", "early-youtube.js"}
for name, expected_hash in report["outputs"].items():
    assert digest(root / "extension" / name) == expected_hash, f"Runtime output changed: {name}"
print("PASS: generated JS matches pinned inputs and rule generation")
