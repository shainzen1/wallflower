#!/usr/bin/env bash
# Builds the release: build/release/Wallflower-<version>.zip with Wallflower.app inside, universal
# (arm64 and x86_64) when the toolchain can build it, arm64 only otherwise, ad-hoc signed, and
# build/release/appcast.xml, the Sparkle feed for in-app updates (one item: this release, signed
# with the EdDSA key, release notes from the CHANGELOG). Prints the zip's sha256.
# Local only: never publishes or uploads anything. Upload the zip and appcast.xml to the release.
#
#   scripts/release.sh [--ed-key-file <path>] [--download-base <url>]
#
# Options:
#   --ed-key-file <path>   sign with the private EdDSA key in this file instead of the one Sparkle's
#                          generate_keys stored in the login Keychain (for tests)
#   --download-base <url>  where the zip will be downloaded from (default: the GitHub release
#                          https://github.com/<owner>/<repo>/releases/download/v<version>, taken
#                          from SUFeedURL)
#
# Stops before building when SUPublicEDKey in Packaging/Info.plist is still the placeholder, and
# after signing when the signature does not verify with that public key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
PLIST="$ROOT/Packaging/Info.plist"
KEY_FILE=""
DOWNLOAD_BASE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ed-key-file) KEY_FILE="${2:?--ed-key-file needs a path}"; shift 2 ;;
        --download-base) DOWNLOAD_BASE="${2:?--download-base needs a URL}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -z "$KEY_FILE" || -f "$KEY_FILE" ]] || { echo "Stopped: no key file at $KEY_FILE." >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MINIMUM="$(plist LSMinimumSystemVersion)"
FEED="$(plist SUFeedURL)"
APP="$ROOT/build/$NAME.app"
OUT="$ROOT/build/release"
ZIP="$OUT/$NAME-$VERSION.zip"
APPCAST="$OUT/appcast.xml"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

cd "$ROOT"
echo "Release $NAME $VERSION (build $BUILD)"

PUBLIC_KEY="$("$ROOT/scripts/check-update-key.sh" "$PLIST")"
# The feed is .../releases/latest/download/appcast.xml on the GitHub repository.
REPO_URL="${FEED%/releases/latest/download/appcast.xml}"
RELEASE_PAGE=""
if [[ "$REPO_URL" != "$FEED" && "$REPO_URL" == https://github.com/* ]]; then
    RELEASE_PAGE="$REPO_URL/releases"
    DOWNLOAD_BASE="${DOWNLOAD_BASE:-$REPO_URL/releases/download/v$VERSION}"
fi
[[ -n "$DOWNLOAD_BASE" ]] || { echo "Stopped: SUFeedURL ($FEED) is not a GitHub latest-release URL; pass --download-base." >&2; exit 1; }

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
rm -f "$ZIP" "$APPCAST"
# --norsrc drops resource forks and extended attributes (no local provenance, no ._ files).
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

# Sign the zip for Sparkle: the private key from the Keychain (generate_keys) or --ed-key-file.
[[ -x "$SIGN_UPDATE" ]] || { echo "Stopped: Sparkle's sign_update not found at $SIGN_UPDATE (run swift package resolve)." >&2; exit 1; }
SIGN_ARGS=(-p)
[[ -n "$KEY_FILE" ]] && SIGN_ARGS+=(--ed-key-file "$KEY_FILE")
SIGNATURE="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" "$ZIP")"
if ! swift "$ROOT/scripts/verify-update-signature.swift" "$PUBLIC_KEY" "$SIGNATURE" "$ZIP"; then
    rm -f "$ZIP"
    echo "Stopped: the signature does not verify with SUPublicEDKey. The private key used is not the one whose public key is in Info.plist; installed apps would refuse this update." >&2
    exit 1
fi
LENGTH="$(stat -f %z "$ZIP")"

APPCAST_ARGS=(
    --version "$VERSION" --build "$BUILD" --minimum-system "$MINIMUM"
    --url "${DOWNLOAD_BASE%/}/$NAME-$VERSION.zip" --length "$LENGTH" --signature "$SIGNATURE"
    --changelog "$ROOT/CHANGELOG.md"
)
[[ -n "$RELEASE_PAGE" ]] && APPCAST_ARGS+=(--release-page "$RELEASE_PAGE")
"$ROOT/scripts/appcast.sh" "${APPCAST_ARGS[@]}" > "$APPCAST"
xmllint --noout "$APPCAST"

echo "Architectures: $ARCHS"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
echo "Appcast: $APPCAST (upload it with the zip: the feed is $FEED)"
