#!/usr/bin/env bash
# Builds the drag-to-install disk image from an app bundle: the app, an Applications symlink, the
# black background with the arrow, the Finder layout (window size, no toolbar or sidebar, icon size
# and positions) and the app icon as the volume icon, compressed with LZFSE (ULFO). scripts/release.sh
# calls it; signing and notarizing the image happen there.
#
#   scripts/make-dmg.sh <Wallflower.app> <out.dmg>
#
# Only built-in tools (hdiutil, tiffutil, xattr): the layout is the committed Packaging/dmg/DS_Store,
# made once by Packaging/dmg/make-layout.sh. It names the volume, /.background.tiff and the two items,
# so those are fixed here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
VOLUME="Wallflower"
LAYOUT="$ROOT/Packaging/dmg"

fail() { printf 'make-dmg.sh: %s\n' "$1" >&2; exit 1; }

[[ $# -eq 2 ]] || { sed -n '7p' "$0" | sed 's/^# *//' >&2; exit 2; }
APP="$1"
OUT="$2"
[[ -d "$APP" && "$(basename "$APP")" == "$NAME.app" ]] || fail "$APP is not a $NAME.app bundle."
[[ "$OUT" == *.dmg ]] || fail "the output must end in .dmg."
for file in DS_Store background.png background@2x.png; do
    [[ -f "$LAYOUT/$file" ]] || fail "missing $LAYOUT/$file."
done

WORK="$(mktemp -d)"
STAGE="$WORK/$VOLUME"
MOUNT="$WORK/mount"
cleanup() {
    if [[ -d "$MOUNT" ]]; then hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# The volume's contents. ditto keeps the app's signature, symlinks and stapled ticket.
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
# One TIFF with the 1x and 2x pictures, so Finder picks the sharp one on a Retina display.
tiffutil -cathidpicheck "$LAYOUT/background.png" "$LAYOUT/background@2x.png" -out "$STAGE/.background.tiff" \
    >/dev/null 2>&1 || fail "tiffutil could not combine the background pictures."
cp "$LAYOUT/DS_Store" "$STAGE/.DS_Store"
cp "$ROOT/Packaging/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# A writable image first: the volume icon needs a flag on the mounted root folder.
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
mkdir "$MOUNT"
# -nobrowse keeps Finder (and its own .DS_Store writes) away from the volume.
hdiutil attach -quiet -nobrowse -noautoopen -noverify -mountpoint "$MOUNT" "$WORK/rw.dmg"
# kHasCustomIcon (0x0400) in the root folder's Finder flags, bytes 8 and 9 of its 32-byte Finder info.
xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"
chflags hidden "$MOUNT/.background.tiff" "$MOUNT/.VolumeIcon.icns"
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$OUT"
hdiutil verify -quiet "$OUT"
echo "Disk image: $OUT"
