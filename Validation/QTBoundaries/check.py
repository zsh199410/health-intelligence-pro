"""Compare automatic QRS boundaries with QT Database annotations on four fixed records."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[2]
BLOBS = {
    "sel100": "1b8ece0de0c6f936fd1dc136cd1846a2fcfef315",
    "sel102": "d4b33ae32b10c20d9dcc17acc550e3446358c09d",
    "sel103": "b094e6ac9aa204f01b6bf5e4b7bc14c6e9c434e6",
    "sel104": "3dc4ba2176c2fa585b650e15c144546c3de2b16b",
}


def fixtures(directory):
    # MAT adapter uses marker positions as zero-based indices (upstream QTloader).
    # Only immediately bracketed R labels have unambiguous reference boundaries.
    for name, expected in BLOBS.items():
        path = directory / (name + ".mat")
        blob = subprocess.check_output(["git", "hash-object", str(path)], text=True).strip()
        if blob != expected:
            raise ValueError(f"Unexpected {name} fixture")
        data = loadmat(path)
        signal, time = data["sig"][0], data["time"].ravel()
        assert len(signal) == len(time) and np.allclose(np.diff(time), 1 / 250)
        labels = sorted((int(index), label.item()) for label, group in
                        zip(data["code_label"][0], data["markercell"][0]) for index in group.ravel())
        for i, (peak, kind) in enumerate(labels):
            if kind != "R" or i == 0 or i + 1 == len(labels):
                continue
            left, right = labels[i - 1], labels[i + 1]
            if left[1] != "lp" or right[1] != "rp":
                continue
            # Overlapping ten-second contexts benchmark labeled complexes only.
            # Reference locations are used for matching after the detector returns.
            start = max(0, min(peak - 1250, len(signal) - 2500))
            yield dict(record=name, samples=signal[start:start + 2500].tolist(),
                       onset=(left[0] - start) / 250, peak=(peak - start) / 250,
                       offset=(right[0] - start) / 250)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        exe = Path(tmp) / "check"
        core = ROOT / "Core/Sources/HealthCore"
        subprocess.run(["swiftc", "-O", *(core / (name + ".swift") for name in
                        ["Models", "ECGWaveform", "ECGBeatDetector", "ExperimentalQRSDuration"]),
                        ROOT / "Validation/QTBoundaries/main.swift", "-o", exe], check=True)
        subprocess.run([exe], input=json.dumps(list(fixtures(args.data)), allow_nan=False), text=True, check=True)


if __name__ == "__main__":
    main()
