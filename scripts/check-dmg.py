#!/usr/bin/env python3
"""Mount a DMG read-only and verify its installer layout and unchanged release app."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from ds_store import DSStore

image, archive, app = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix="installer-check-") as tmp:
    mount = Path(tmp) / "volume"
    mount.mkdir()
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), image], check=True, stdout=subprocess.DEVNULL)
    try:
        assert os.readlink(mount / "Applications") == "/Applications", "Applications target changed"
        bundle = mount / (app + ".app")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
        with zipfile.ZipFile(archive) as source:
            expected = {entry.filename for entry in source.infolist() if not entry.is_dir()}
            actual = {str(path.relative_to(mount)) for path in bundle.rglob("*") if path.is_file()}
            assert actual == expected, "App files differ from the released ZIP"
            for name in expected:
                assert (mount / name).read_bytes() == source.read(name), "Changed app file: " + name
        background = mount / ".background.tiff"
        assert background.is_file()
        flags = bytes.fromhex(subprocess.check_output(["xattr", "-px", "com.apple.FinderInfo", str(background)], text=True))
        assert int.from_bytes(flags[8:10], "big") & 0x4000, "Background is not hidden"
        with DSStore.open(str(mount / ".DS_Store"), "r") as store:
            assert store[app + ".app"]["Iloc"] == (204, 258)
            assert store["Applications"]["Iloc"] == (516, 258)
            assert store["."]["icvp"]["backgroundType"] == 2
            assert store["."]["icvp"]["iconSize"] == 104
            assert store["."]["bwsp"]["WindowBounds"] == "{{200, 160}, {720, 512}}"
        raw = (mount / ".DS_Store").read_bytes()
        for data in (raw, raw.replace(b"\x00", b"")):
            assert not re.search(rb"/(?:Users|home)/[^/\s]+/", data), "Installer metadata contains a home path"
        print("Verified: unchanged signed app, Applications shortcut, hidden artwork, layout, and metadata privacy.")
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
