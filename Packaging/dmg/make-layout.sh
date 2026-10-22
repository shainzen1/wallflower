#!/usr/bin/env bash
# Regenerates Packaging/dmg/DS_Store, the Finder layout of the release disk image (window size, no
# toolbar or sidebar, icon size and positions, the background picture), from layout.py. Run it after
# changing layout.py or the background's size, then commit the DS_Store.
#
#   Packaging/dmg/make-layout.sh
#
# Installs dmgbuild (pinned) into a throwaway virtualenv, so it needs the network once; the release
# never does: scripts/make-dmg.sh only copies the DS_Store into the image. Mounts a scratch image as
# /Volumes/Wallflower while it runs, so eject any other "Wallflower" volume first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/Packaging/dmg"
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
cleanup() {
    [[ -d "$MOUNT" ]] && hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

[[ ! -e /Volumes/Wallflower ]] || { echo "Stopped: /Volumes/Wallflower is mounted; eject it first." >&2; exit 1; }

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q --disable-pip-version-check "dmgbuild==1.6.5" "ds-store==1.3.1" "mac-alias==2.2.2"

tiffutil -cathidpicheck "$DIR/background.png" "$DIR/background@2x.png" -out "$WORK/background.tiff"
mkdir "$WORK/Wallflower.app"
"$WORK/venv/bin/dmgbuild" -s "$DIR/layout.py" -D app="$WORK/Wallflower.app" -D background="$WORK/background.tiff" \
    Wallflower "$WORK/layout.dmg"

mkdir "$MOUNT"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" "$WORK/layout.dmg"
cp "$MOUNT/.DS_Store" "$DIR/DS_Store"
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT"
echo "Layout: $DIR/DS_Store ($(stat -f %z "$DIR/DS_Store") bytes)"
