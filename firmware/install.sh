#!/bin/sh
# Copy the firmware onto a Ting running CircuitPython. code.py reloads on its
# own; changes to boot.py need a hard reset (unplug/replug or the small button).
set -eu
cd "$(dirname "$0")"
V=/Volumes/CIRCUITPY
[ -d "$V" ] || { echo "CIRCUITPY not mounted" >&2; exit 1; }
# Host-side pytest leaves __pycache__ in lib/; the device doesn't want it.
rsync -r --exclude __pycache__ lib/ "$V/lib/"
cp -X boot.py "$V/boot.py"
cp -X code.py "$V/code.py"
# macOS writes AppleDouble ._ files onto FAT volumes; strip them.
dot_clean -m "$V"
sync
echo "installed to $V"
