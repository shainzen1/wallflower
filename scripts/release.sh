#!/usr/bin/env bash
# Builds the release into build/release: Wallflower-<version>.zip with Wallflower.app inside, universal
# (arm64 and x86_64) when the toolchain can build it, arm64 only otherwise; appcast.xml, the Sparkle
# feed for in-app updates (one item: this release, signed with the EdDSA key, release notes from the
# CHANGELOG); and Wallflower.dmg, the disk image people install from (scripts/make-dmg.sh). Prints
# the zip's sha256. Never publishes or uploads anything. Upload all three to the release.
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
# Signing (scripts/signing.sh): with a Developer ID identity (WALLFLOWER_SIGN_IDENTITY, or the one
# in the Keychain) and a notarytool profile (WALLFLOWER_NOTARY_PROFILE, default wallflower-notary),
# the app is signed with the hardened runtime, notarized and stapled before it goes into the zip and
# the disk image, and the disk image is signed, notarized and stapled too. Without an identity
# everything is signed ad hoc and the run says NOT NOTARIZED. WALLFLOWER_SIGN_IDENTITY=- forces ad hoc.
#
# Stops before building when SUPublicEDKey in Packaging/Info.plist is still the placeholder, or a
# Developer ID is found but its identity or notary profile is not usable; after signing when the
# EdDSA signature does not verify with that public key. A failed run leaves no release files behind.
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
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
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
# No version in the name: .../releases/latest/download/Wallflower.dmg always is the newest.
DMG="$OUT/$NAME.dmg"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
WORK="$(mktemp -d)"

# Nothing from a failed run stays behind to be uploaded by mistake.
cleanup() {
    local status=$?
    rm -rf "$WORK"
    if [[ $status -ne 0 ]]; then rm -f "$ZIP" "$APPCAST" "$DMG"; fi
}
trap cleanup EXIT

# Submits a zip or disk image to Apple's notary service, waits, and stops unless it is Accepted.
notarize() {
    local result status id
    echo "Notarizing $(basename "$1") (this takes a few minutes)"
    result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" \
        || { echo "Stopped: notarytool could not submit $1." >&2; exit 1; }
    status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        echo "Stopped: notarization of $(basename "$1") ended as ${status:-unknown}, not Accepted (the log is above)." >&2
        exit 1
    fi
}

cd "$ROOT"
echo "Release $NAME $VERSION (build $BUILD)"

PUBLIC_KEY="$("$ROOT/scripts/check-update-key.sh" "$PLIST")"
# shellcheck source=signing.sh
source "$ROOT/scripts/signing.sh"
NOT_NOTARIZED="NOT NOTARIZED: Gatekeeper will warn on the first launch (signed ad hoc; a Developer ID and a notarytool profile turn notarization on)."
IDENTITY="$(release_identity)" || { echo "Stopped: no unambiguous signing identity." >&2; exit 1; }
if [[ -n "$IDENTITY" ]]; then
    # Both before the long build: the identity must be one codesign can use, the profile must exist.
    security find-identity -v -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null \
        || { echo "Stopped: \"$IDENTITY\" is not a valid signing identity in the Keychain (security find-identity -v -p codesigning). Set WALLFLOWER_SIGN_IDENTITY=- to build ad hoc." >&2; exit 1; }
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || { echo "Stopped: no working notarytool profile \"$NOTARY_PROFILE\" (xcrun notarytool store-credentials $NOTARY_PROFILE ...). Set WALLFLOWER_SIGN_IDENTITY=- to build ad hoc." >&2; exit 1; }
    echo "Signing: Developer ID ($IDENTITY), notary profile $NOTARY_PROFILE"
else
    echo "Signing: ad hoc"
    echo "$NOT_NOTARIZED"
fi
# The feed is .../releases/latest/download/appcast.xml on the GitHub repository.
REPO_URL="${FEED%/releases/latest/download/appcast.xml}"
RELEASE_PAGE=""
if [[ "$REPO_URL" != "$FEED" && "$REPO_URL" == https://github.com/* ]]; then
    RELEASE_PAGE="$REPO_URL/releases"
    DOWNLOAD_BASE="${DOWNLOAD_BASE:-$REPO_URL/releases/download/v$VERSION}"
fi
[[ -n "$DOWNLOAD_BASE" ]] || { echo "Stopped: SUFeedURL ($FEED) is not a GitHub latest-release URL; pass --download-base." >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$ZIP" "$APPCAST" "$DMG"

# bundle.sh builds in release mode, assembles the app and signs it (ad hoc, or with the identity).
export WALLFLOWER_SIGN_IDENTITY="${IDENTITY:--}"
BUNDLED=0
"$ROOT/scripts/bundle.sh" --arch arm64 --arch x86_64 || BUNDLED=$?
if [[ $BUNDLED -eq 0 ]]; then
    ARCHS="universal (arm64, x86_64)"
elif [[ $BUNDLED -eq 3 ]]; then
    # Signing failed (bundle.sh removed the app): not a toolchain problem, so no arm64 retry.
    echo "Stopped: the app could not be signed." >&2
    exit 1
else
    echo "The universal build failed with this toolchain; building for arm64 only." >&2
    "$ROOT/scripts/bundle.sh" --arch arm64
    ARCHS="arm64 only (no universal build with this toolchain)"
fi
lipo -info "$APP/Contents/MacOS/$NAME"
codesign --verify --deep --strict "$APP"

if [[ -n "$IDENTITY" ]]; then
    # Notarize the app itself and staple its ticket, so the zip and the disk image both carry an app
    # that opens offline. The submission is a throwaway zip of the signed app.
    ditto -c -k --keepParent --norsrc "$APP" "$WORK/$NAME.zip"
    notarize "$WORK/$NAME.zip"
    xcrun stapler staple -q "$APP"
    xcrun stapler validate -q "$APP"
    spctl -a -vv -t execute "$APP"
fi

# --norsrc drops resource forks and extended attributes (no local provenance, no ._ files).
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

# Sign the zip for Sparkle: the private key from the Keychain (generate_keys) or --ed-key-file.
[[ -x "$SIGN_UPDATE" ]] || { echo "Stopped: Sparkle's sign_update not found at $SIGN_UPDATE (run swift package resolve)." >&2; exit 1; }
SIGN_ARGS=(-p)
[[ -n "$KEY_FILE" ]] && SIGN_ARGS+=(--ed-key-file "$KEY_FILE")
SIGNATURE="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" "$ZIP")"
if ! swift "$ROOT/scripts/verify-update-signature.swift" "$PUBLIC_KEY" "$SIGNATURE" "$ZIP"; then
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

# The disk image holds the same (stapled) app. Signed and notarized on its own, then stapled, so
# Gatekeeper accepts the image itself when it is opened.
"$ROOT/scripts/make-dmg.sh" "$APP" "$DMG"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    notarize "$DMG"
    xcrun stapler staple -q "$DMG"
    xcrun stapler validate -q "$DMG"
    # -t open with the primary signature is the assessment for a disk image (-t install is for pkgs).
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi

echo "Architectures: $ARCHS"
echo "Zip: $ZIP"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
echo "Disk image: $DMG ($(stat -f %z "$DMG") bytes)"
echo "Appcast: $APPCAST (upload it with the zip and the disk image: the feed is $FEED)"
if [[ -z "$IDENTITY" ]]; then echo "$NOT_NOTARIZED"; fi
echo "Signing: $(signing_summary "$IDENTITY")"
