#!/usr/bin/env bash
# Builds the release binary and assembles build/Wallflower.app, ad-hoc signed.
# Extra arguments go to `swift build` (release.sh passes `--arch` flags).
#
# WALLFLOWER_SIGN_IDENTITY set to a Developer ID identity signs with it instead, with the hardened
# runtime and a secure timestamp (which asks Apple's timestamp server); release.sh sets it when it
# finds one. Unset or "-": ad hoc, offline. Exits 3 when signing fails, with the app removed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
APP="$ROOT/build/$NAME.app"
CONTENTS="$APP/Contents"
IDENTITY="${WALLFLOWER_SIGN_IDENTITY:--}"

cd "$ROOT"
HELPER="wallflower-hook"
swift build -c release --product "$NAME" "$@"
swift build -c release --product "$HELPER" "$@"
BIN_DIR="$(swift build -c release --product "$NAME" "$@" --show-bin-path)"

# Sparkle (in-app updates) from SwiftPM's artifact: universal, the same version as Package.resolved.
SPARKLE_ARTIFACT="$ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE="$SPARKLE_ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework not found at $SPARKLE (run swift package resolve)." >&2; exit 1; }
# Its license (with the notices of the code it bundles) must ship with the framework.
[[ -f "$SPARKLE_ARTIFACT/LICENSE" ]] || { echo "Sparkle's LICENSE not found at $SPARKLE_ARTIFACT." >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks" "$CONTENTS/Helpers"
cp "$BIN_DIR/$NAME" "$CONTENTS/MacOS/$NAME"
# The hook helper agents' hooks run (docs/agents.md). The app copies it to a stable path on Connect.
cp "$BIN_DIR/$HELPER" "$CONTENTS/Helpers/$HELPER"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Packaging/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
# The default notification sound, "Wallflower ping" (SoundLibrary; terms in THIRD_PARTY_NOTICES.md).
cp "$ROOT/Packaging/Sounds/ping.wav" "$CONTENTS/Resources/ping.wav"
# The licenses travel with the app: ours, and Sparkle's (THIRD_PARTY_NOTICES.md).
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
cp "$SPARKLE_ARTIFACT/LICENSE" "$CONTENTS/Resources/Sparkle-LICENSE.txt"
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
strip -S -x "$CONTENTS/MacOS/$NAME" "$CONTENTS/Helpers/$HELPER"

# Inside out, in Sparkle's documented order: its helpers, the framework (its seal changed with the
# removals), then the hook helper and the app. Never --deep. No entitlements: the app is not sandboxed, loads no foreign code
# and sends no Apple events.
if [[ "$IDENTITY" == "-" ]]; then
    SIGN=(codesign --force --sign -)
else
    SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
fi
# A signing failure leaves no app behind, so nothing half signed can be zipped.
trap '[[ $? -eq 0 ]] || { rm -rf "$APP"; echo "Stopped: signing failed; removed $APP." >&2; exit 3; }' EXIT
"${SIGN[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
"${SIGN[@]}" "$FRAMEWORK/Versions/B/Updater.app"
"${SIGN[@]}" "$FRAMEWORK"
"${SIGN[@]}" "$CONTENTS/Helpers/$HELPER"
"${SIGN[@]}" "$APP"
if [[ "$IDENTITY" == "-" ]]; then
    echo "Bundled: $APP (ad hoc)"
else
    echo "Bundled: $APP (signed as $IDENTITY)"
fi
