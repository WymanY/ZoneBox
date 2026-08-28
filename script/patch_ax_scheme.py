#!/usr/bin/env python3
from pathlib import Path
import sys

scheme = Path(__file__).resolve().parents[1] / "ZoneBox.xcodeproj/xcshareddata/xcschemes/ZoneBox AX.xcscheme"
text = scheme.read_text()
if 'launchStyle = "1"' in text:
    print("ZoneBox AX scheme already waits for launch")
    sys.exit(0)
needle = 'launchStyle = "0"'
if needle not in text:
    sys.exit(f"could not patch {scheme}")
scheme.write_text(text.replace(needle, 'launchStyle = "1"', 1))
print("patched ZoneBox AX scheme to wait for launch")
