#!/usr/bin/env bash
# Renders the app icon with the app's own face renderer (`--render-icon`, App/IconRenderer.swift)
# and builds Packaging/AppIcon.icns and docs/assets/icon.png (1024 px) from it. Commit both.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"

cd "$ROOT"
swift build --product Wallflower
BIN="$(swift build --product Wallflower --show-bin-path)/Wallflower"
"$BIN" --render-icon "$ICONSET"

iconutil -c icns "$ICONSET" -o "$ROOT/Packaging/AppIcon.icns"
mkdir -p "$ROOT/docs/assets"
cp "$ICONSET/icon_512x512@2x.png" "$ROOT/docs/assets/icon.png"
echo "Icon: $ROOT/Packaging/AppIcon.icns and $ROOT/docs/assets/icon.png"
