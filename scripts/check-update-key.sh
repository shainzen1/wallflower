#!/usr/bin/env bash
# Stops a release whose Info.plist has no real Sparkle public key. The repo carries a placeholder in
# SUPublicEDKey; an app shipped with it starts no updater, so it could never update itself again.
#
#   scripts/check-update-key.sh [Info.plist]    (default: Packaging/Info.plist)
#
# Exits 0 and prints the key when it is an Ed25519 public key (base64 of 32 bytes), 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${1:-$ROOT/Packaging/Info.plist}"
# Also in AppUpdater.publicKeyPlaceholder.
PLACEHOLDER="PASTE_THE_PUBLIC_KEY_FROM_generate_keys"

KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
if [[ -z "$KEY" || "$KEY" == "$PLACEHOLDER" ]]; then
    echo "Stopped: SUPublicEDKey in $PLIST is not set (still the placeholder). Run Sparkle's generate_keys once, paste the public key it prints into SUPublicEDKey and commit it. The maintainer's publishing notes have the steps." >&2
    exit 1
fi
# 32 bytes in base64: 43 characters and one '=' of padding.
if [[ ! "$KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Stopped: SUPublicEDKey in $PLIST is not an Ed25519 public key (base64 of 32 bytes). Paste the public key generate_keys prints, never the private key." >&2
    exit 1
fi
echo "$KEY"
