#!/usr/bin/env bash
# Sets the version in Packaging/Info.plist for the next release: CFBundleShortVersionString to the
# given version and CFBundleVersion one higher (or to --build). Sparkle compares CFBundleVersion, so
# it must grow with every release. Edits the two lines in place (PlistBuddy would reorder the file).
# Versions have two parts from 1.4 on (1.4, 1.5, ... 1.10); three parts are still accepted.
#
#   scripts/bump-version.sh <version> [--build <number>]    for example: scripts/bump-version.sh 1.4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Packaging/Info.plist"
VERSION=""
BUILD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build) BUILD="${2:?--build needs a number}"; shift 2 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) VERSION="$1"; shift ;;
    esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Stopped: give the version like 1.4." >&2; exit 1; }
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ "$CURRENT" =~ ^[0-9]+$ ]] || { echo "Stopped: CFBundleVersion ($CURRENT) is not a whole number; pass --build." >&2; exit 1; }
BUILD="${BUILD:-$((CURRENT + 1))}"
[[ "$BUILD" =~ ^[0-9]+$ && "$BUILD" -gt "$CURRENT" ]] || { echo "Stopped: the build must be a whole number above $CURRENT." >&2; exit 1; }

# The <string> line right after each key gets the new value.
awk -v version="$VERSION" -v build="$BUILD" '
    set != "" { sub(/<string>[^<]*<\/string>/, "<string>" set "</string>"); set = "" }
    /<key>CFBundleShortVersionString<\/key>/ { set = version }
    /<key>CFBundleVersion<\/key>/ { set = build }
    { print }
' "$PLIST" > "$PLIST.tmp" && mv "$PLIST.tmp" "$PLIST"
plutil -lint -s "$PLIST"
echo "Packaging/Info.plist: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST"))"
