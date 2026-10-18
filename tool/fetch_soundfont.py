#!/usr/bin/env python3
"""Reproducibly bundle creator-published GeneralUser GS 2.0.3 SoundFont.
Build-time download only; APK MIDI rendering works entirely offline.
"""
from pathlib import Path
from urllib.request import Request, urlopen

COMMIT = "684543d5e5efaef08d02be50dcda8d552478fa60"
BASE = f"https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/{COMMIT}"
ROOT = Path("assets/soundfonts")
ROOT.mkdir(parents=True, exist_ok=True)

def fetch(remote: str, local: str, binary: bool = True) -> None:
    path = ROOT / local
    if path.is_file() and path.stat().st_size > 500_000:
        if path.suffix == ".sf2":
            with path.open("rb") as f:
                header = f.read(12)
            if header[:4] == b"RIFF" and header[8:12] == b"sfbk":
                print(f"Using verified existing {path}")
                return
    req = Request(f"{BASE}/{remote}", headers={
        "User-Agent": "AmpyScoreStudio-build/0.7"
    })
    with urlopen(req, timeout=90) as r, path.open("wb") as f:
        while True:
            block = r.read(1024 * 512)
            if not block:
                break
            f.write(block)
    if binary:
        with path.open("rb") as f:
            header = f.read(12)
        if header[:4] != b"RIFF" or header[8:12] != b"sfbk":
            path.unlink(missing_ok=True)
            raise RuntimeError(f"Not a SoundFont 2 bank: {path}")
        if not 5_000_000 <= path.stat().st_size <= 100_000_000:
            path.unlink(missing_ok=True)
            raise RuntimeError("Unexpected SoundFont size")
    print(f"Bundled {path} ({path.stat().st_size:,} bytes)")

fetch("GeneralUser-GS.sf2", "GeneralUser-GS.sf2")
fetch("documentation/LICENSE.txt", "GeneralUser-GS-LICENSE.txt", binary=False)
