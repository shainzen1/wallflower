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

# Sparkle (in-app updates) from SwiftPM's artifact: universal, the same version as Package.resolved.
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework not found at $SPARKLE (run swift package resolve)." >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_DIR/$NAME" "$CONTENTS/MacOS/$NAME"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Packaging/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# ditto keeps the framework's symlinks. The binary finds it through the rpath
# @executable_path/../Frameworks (Package.swift). Left out: the headers and module map (build time
# only) and the XPC services, which only a sandboxed app needs.
FRAMEWORK="$CONTENTS/Frameworks/Sparkle.framework"
ditto "$SPARKLE" "$FRAMEWORK"
rm -rf "$FRAMEWORK/Versions/B/XPCServices" "$FRAMEWORK/XPCServices" \
    "$FRAMEWORK/Versions/B/Headers" "$FRAMEWORK/Headers" \
    "$FRAMEWORK/Versions/B/PrivateHeaders" "$FRAMEWORK/PrivateHeaders" \
    "$FRAMEWORK/Versions/B/Modules" "$FRAMEWORK/Modules"

# No debug map or local symbols in the shipped binary: they carry this machine's build paths.
# Only ours: Sparkle's binaries come stripped.
strip -S -x "$CONTENTS/MacOS/$NAME"

# Ad hoc, inside out: Sparkle's helpers, the framework (its seal changed with the removals), the app.
codesign --force --sign - "$FRAMEWORK/Versions/B/Autoupdate"
codesign --force --sign - "$FRAMEWORK/Versions/B/Updater.app"
codesign --force --sign - "$FRAMEWORK"
codesign --force --sign - "$APP"
echo "Bundled: $APP"
