#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
data=${1:?Pass a directory containing 100.dat and 100.atr from the WFDB sample-data fixture}
test "$(git hash-object "$data/100.dat")" = 3c523c2ef34e693ebb6a4ada7a4feef71e64f8c6
test "$(git hash-object "$data/100.atr")" = 720c15b5cc44ea45fd09e4db1a7d0c8e9aea02f7
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -O "$root"/Core/Sources/HealthCore/{Models,ECGWaveform,ECGBeatDetector}.swift "$root/Validation/ECG100/main.swift" -o "$out/check"
"$out/check" "$data/100.dat" "$data/100.atr"
