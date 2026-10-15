# Portkeeper disk image

The release DMG opens a branded Finder window with the app on the left and an Applications shortcut on the right. Drag the app across, eject the disk, and open the installed app from Applications. Installing does not launch the app or any managed services.

The DMG contains the same app as the release ZIP. It adds only the Applications symlink, hidden artwork, and Finder layout metadata. The app remains ad-hoc signed and unnotarized. No certificate or notarization step is part of this packaging workflow.

## Build

After `zsh build.sh`, run:

```sh
zsh scripts/build-dmg.sh
```

The script creates a temporary Python environment and installs the pinned packaging dependencies from `scripts/dmg-requirements.txt`. It does not install global tools. To reuse an existing environment, set `DMGBUILD=/path/to/venv/bin/dmgbuild`.

You can supply an existing release ZIP and a new output path:

```sh
zsh scripts/build-dmg.sh /path/to/Portkeeper.zip /path/to/Portkeeper.dmg
```

The script refuses to overwrite an existing image. It checks the input app signature, creates a compressed read-only image, verifies the image checksum, and mounts it temporarily to compare every app file against the ZIP. It also verifies the Applications target, Finder positions, hidden artwork, and absence of personal home paths in layout metadata. Temporary verification mounts are ejected automatically.

`Assets/Installer/background.svg` is the editable artwork. The TIFF contains 1× and 2× renditions for sharp Retina display. The README illustration is generated with `scripts/render-installer-preview.swift`; it is a layout illustration, not a screenshot.

Refresh release SHA256SUMS whenever adding a DMG. Existing ZIPs and version tags stay unchanged for a packaging-only addition.
