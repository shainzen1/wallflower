#!/usr/bin/env bash
# Builds the release zip: build/release/Wallflower-<version>.zip with Wallflower.app inside,
# universal (arm64 and x86_64) when the toolchain can build it, arm64 only otherwise, ad-hoc
# signed. Prints the zip's sha256. Local only: never publishes or uploads anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
PLIST="$ROOT/Packaging/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
APP="$ROOT/build/$NAME.app"
OUT="$ROOT/build/release"
ZIP="$OUT/$NAME-$VERSION.zip"

cd "$ROOT"
echo "Release $NAME $VERSION (build $BUILD)"

# bundle.sh builds in release mode, assembles the app and signs it ad hoc.
if "$ROOT/scripts/bundle.sh" --arch arm64 --arch x86_64; then
    ARCHS="universal (arm64, x86_64)"
else
    echo "The universal build failed with this toolchain; building for arm64 only." >&2
    "$ROOT/scripts/bundle.sh" --arch arm64
    ARCHS="arm64 only (no universal build with this toolchain)"
fi
lipo -info "$APP/Contents/MacOS/$NAME"
codesign --verify --strict "$APP"

mkdir -p "$OUT"
rm -f "$ZIP"
# --norsrc drops resource forks and extended attributes (no local provenance, no ._ files).
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

echo "Architectures: $ARCHS"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
