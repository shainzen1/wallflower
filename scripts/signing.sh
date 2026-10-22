#!/usr/bin/env bash
# How a release is signed, for scripts/release.sh (sourced; defines functions only).
#
#   WALLFLOWER_SIGN_IDENTITY   the codesign identity, "Developer ID Application: Name (TEAMID)" or its
#                              SHA-1; "-" signs ad hoc even when a Developer ID is in the Keychain.
#                              Unset: the one "Developer ID Application" identity that
#                              `security find-identity -v -p codesigning` lists, or ad hoc without one
#   WALLFLOWER_NOTARY_PROFILE  the notarytool Keychain profile (default wallflower-notary), stored once
#                              with `xcrun notarytool store-credentials`
#
# With a Developer ID the release is signed with the hardened runtime, notarized and stapled; ad hoc,
# macOS warns on the first launch ("Apple could not verify ... is free of malware").

NOTARY_PROFILE="${WALLFLOWER_NOTARY_PROFILE:-wallflower-notary}"

# Prints the Developer ID identity to sign with, or nothing for ad hoc. Fails (with the list on stderr)
# when the Keychain has several and WALLFLOWER_SIGN_IDENTITY does not pick one.
release_identity() {
    local found
    if [[ -n "${WALLFLOWER_SIGN_IDENTITY:-}" ]]; then
        if [[ "$WALLFLOWER_SIGN_IDENTITY" != "-" ]]; then echo "$WALLFLOWER_SIGN_IDENTITY"; fi
        return 0
    fi
    # Valid identities only (-v): an expired or revoked certificate is not listed.
    found="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n -E 's/^ *[0-9]+\) [0-9A-F]{40} "(Developer ID Application: [^"]+)".*/\1/p' | sort -u)" || true
    [[ -n "$found" ]] || return 0
    if [[ "$found" == *$'\n'* ]]; then
        echo "Several Developer ID Application identities in the Keychain; set WALLFLOWER_SIGN_IDENTITY to one of:" >&2
        printf '%s\n' "$found" | sed 's/^/  /' >&2
        return 1
    fi
    echo "$found"
}

# One line for the summaries. <identity, empty for ad hoc>
signing_summary() {
    if [[ -n "$1" ]]; then
        echo "Developer ID ($1), notarized and stapled"
    else
        echo "ad hoc, NOT NOTARIZED (Gatekeeper will warn on the first launch)"
    fi
}
