#!/usr/bin/env bash
# Builds the release binary and assembles build/Wallflower.app, ad-hoc signed.
# Extra arguments go to `swift build` (release.sh passes `--arch` flags).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
APP="$ROOT/build/$NAME.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release --product "$NAME" "$@"
BIN_DIR="$(swift build -c release --product "$NAME" "$@" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$NAME" "$CONTENTS/MacOS/$NAME"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Packaging/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# No debug map or local symbols in the shipped binary: they carry this machine's build paths.
strip -S -x "$CONTENTS/MacOS/$NAME"
codesign --force --sign - --deep "$APP"
echo "Bundled: $APP"
