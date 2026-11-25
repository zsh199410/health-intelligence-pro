#!/usr/bin/env python3
"""Normalize xcresulttool screenshot exports to reviewable file names.

`xcrun xcresulttool export attachments` writes every screenshot under a
UUID file name (e.g. 03374A4A-97FC-....png). The same directory's
manifest.json (a top-level JSON array of test entries) records, per
attachment, the exportedFileName and the suggestedHumanReadableName,
which carries the test's attachment name, e.g.
    light-today_0_DA4F592B-F8B8-....png
This script copies (never moves, never deletes the source) each
screenshot attachment whose human-readable name strictly matches
    ^(light|dark|large-text)-(welcome|today|settings|sleep|heart|records|report)_
to the standard name <mode>-<page>.png in the same directory, then
strictly verifies the result: all 21 files present, each decodes as a
PNG, each has the expected iPhone 17 Pro size (1206x2622). Duplicates,
missing files, corrupt PNGs, unexpected names or wrong sizes all fail
loudly. The original xcresult and the export manifest are kept as
evidence; nothing is deleted.

Usage: normalize_screenshots.py <screenshots dir> [--with-ppg]
With --with-ppg the separately named light-ppg-idle screenshot is required too.
Exit 0 only when all 21 normalized files exist and verify.
"""
import json
import os
import re
import shutil
import struct
import sys
import zlib

NAME_RE = re.compile(
    r"^(light|dark|large-text)-"
    r"(welcome|today|settings|sleep|heart|records|report|ppg-idle)_"
)
EXPECTED = {
    (mode, page)
    for mode in ("light", "dark", "large-text")
    for page in ("welcome", "today", "settings", "sleep", "heart", "records", "report")
}
EXPECTED_SIZE = (1206, 2622)  # iPhone 17 Pro full screen


def fail(message):
    print(f"FAIL: {message}")
    sys.exit(1)


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(33)
    if len(head) < 26 or head[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path} is not a PNG")
    width, height = struct.unpack(">II", head[16:24])
    # Prove the whole file decodes, not just the header.
    with open(path, "rb") as f:
        data = f.read()
    pos = 8
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        chunk = data[pos + 4:pos + 8]
        if chunk == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        elif chunk == b"IEND":
            break
        pos += 12 + length
    try:
        zlib.decompress(idat)
    except zlib.error as exc:
        fail(f"{path} has corrupt PNG data: {exc}")
    return width, height


def main(argv):
    with_ppg = argv[2:] == ["--with-ppg"]
    if len(argv) != 2 and not with_ppg:
        print("usage: normalize_screenshots.py <screenshots dir> [--with-ppg]")
        return 2
    expected = EXPECTED | ({("light", "ppg-idle")} if with_ppg else set())
    directory = argv[1]
    manifest_path = os.path.join(directory, "manifest.json")
    if not os.path.isfile(manifest_path):
        fail(f"manifest.json missing in {directory}; cannot map UUID names")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    found = {}
    for entry in manifest:
        for att in entry.get("attachments", []):
            exported = att.get("exportedFileName", "")
            human = att.get("suggestedHumanReadableName", "")
            if not exported.endswith(".png"):
                continue
            match = NAME_RE.match(human)
            if not match:
                continue
            key = (match.group(1), match.group(2))
            if key[1] == "ppg-idle" and not with_ppg:
                continue
            if key in found:
                fail(f"duplicate screenshot for {key[0]}-{key[1]}: "
                     f"{found[key][0]} and {exported}")
            found[key] = (exported, human)

    missing = expected - set(found)
    if missing:
        fail("missing screenshots: " + ", ".join(
            sorted(f"{m}-{p}" for m, p in missing)))
    unexpected = set(found) - expected
    if unexpected:
        fail("unexpected screenshots: " + ", ".join(
            sorted(f"{m}-{p}" for m, p in unexpected)))

    for (mode, page), (exported, human) in sorted(found.items()):
        src = os.path.join(directory, exported)
        dst = os.path.join(directory, f"{mode}-{page}.png")
        if not os.path.isfile(src):
            fail(f"source file missing for {mode}-{page}: {exported}")
        shutil.copyfile(src, dst)
        print(f"{exported} -> {mode}-{page}.png  (from {human})")

    print("== verify normalized set ==")
    for mode, page in sorted(expected):
        path = os.path.join(directory, f"{mode}-{page}.png")
        width, height = png_size(path)
        if (width, height) != EXPECTED_SIZE:
            fail(f"{mode}-{page}.png is {width}x{height}, "
                 f"expected {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]} "
                 f"(iPhone 17 Pro full screen)")
        print(f"{mode}-{page}.png: {width}x{height} OK")
    print(f"OK: {len(expected)} screenshots normalized and verified")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
