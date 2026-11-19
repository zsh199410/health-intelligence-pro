#!/usr/bin/env python3
"""Read-only XcodeGen bundle identifier audit. No certificates or provisioning data."""
from pathlib import Path
import re
import sys

project = Path(__file__).resolve().parents[1] / "project.yml"
text = project.read_text(encoding="utf-8")

def target_block(name: str) -> str:
    match = re.search(rf"(?m)^  {re.escape(name)}:\s*$", text)
    if not match:
        raise ValueError(f"Missing target {name}")
    tail = text[match.end():]
    next_target = re.search(r"(?m)^  [A-Za-z][A-Za-z0-9_]*:\s*$", tail)
    return tail[:next_target.start()] if next_target else tail

def value(block: str, key: str) -> str:
    match = re.search(rf"(?m)^\s+{re.escape(key)}:\s*([^\n#]+)", block)
    if not match:
        raise ValueError(f"Missing {key}")
    return match.group(1).strip().strip("\u0027\u0022")

iphone = target_block("HealthIntelligence")
watch = target_block("HealthWatch")
iphone_id = value(iphone, "PRODUCT_BUNDLE_IDENTIFIER")
watch_id = value(watch, "PRODUCT_BUNDLE_IDENTIFIER")
companion_id = value(watch, "INFOPLIST_KEY_WKCompanionAppBundleIdentifier")
problems = []
if companion_id != iphone_id:
    problems.append("Watch WKCompanionAppBundleIdentifier does not match iPhone PRODUCT_BUNDLE_IDENTIFIER")
if not watch_id.startswith(iphone_id + "."):
    problems.append("Watch PRODUCT_BUNDLE_IDENTIFIER is not under the iPhone bundle identifier")
print("iPhone bundle:", iphone_id)
print("Watch bundle:", watch_id)
print("Watch companion:", companion_id)
if problems:
    for problem in problems:
        print("FAIL:", problem, file=sys.stderr)
    print("Inspect signing profiles and installed app identifiers before changing project.yml.", file=sys.stderr)
    sys.exit(1)
print("PASS: declared bundle identifier relationships are consistent.")
