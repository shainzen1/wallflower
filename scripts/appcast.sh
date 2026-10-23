#!/usr/bin/env bash
# Writes a Sparkle appcast with one item, the release being built, to stdout. The release notes are
# the version's CHANGELOG section (or [Unreleased] while it has none) as HTML. scripts/release.sh
# calls it; the appcast goes up as a release asset next to the zip, so the feed URL
# .../releases/latest/download/appcast.xml always names the latest release.
#
#   scripts/appcast.sh --version <short version> --build <CFBundleVersion> --minimum-system <macOS>
#                      --url <zip URL> --length <bytes> --signature <EdDSA signature>
#                      [--changelog <CHANGELOG.md>] [--release-page <URL>] [--date <RFC 822 date>]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Wallflower"
VERSION=""
BUILD=""
MINIMUM=""
URL=""
LENGTH=""
SIGNATURE=""
CHANGELOG="$ROOT/CHANGELOG.md"
RELEASE_PAGE=""
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

fail() { printf 'appcast.sh: %s\n' "$1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || fail "$1 needs a value."
    case "$1" in
        --version) VERSION="$2" ;;
        --build) BUILD="$2" ;;
        --minimum-system) MINIMUM="$2" ;;
        --url) URL="$2" ;;
        --length) LENGTH="$2" ;;
        --signature) SIGNATURE="$2" ;;
        --changelog) CHANGELOG="$2" ;;
        --release-page) RELEASE_PAGE="$2" ;;
        --date) DATE="$2" ;;
        *) fail "unknown option $1" ;;
    esac
    shift 2
done

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "--version must look like 1.4."
[[ "$BUILD" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "--build must be a number like 2."
[[ "$MINIMUM" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "--minimum-system must look like 26.0."
[[ "$URL" =~ ^https?://[^[:space:]\"\<\>]+$ ]] || fail "--url must be an http(s) URL."
[[ -z "$RELEASE_PAGE" || "$RELEASE_PAGE" =~ ^https?://[^[:space:]\"\<\>]+$ ]] || fail "--release-page must be an http(s) URL."
[[ "$LENGTH" =~ ^[1-9][0-9]*$ ]] || fail "--length must be the zip's size in bytes."
[[ "$SIGNATURE" =~ ^[A-Za-z0-9+/]{86}==$ ]] || fail "--signature must be sign_update's EdDSA signature (base64 of 64 bytes)."
[[ -f "$CHANGELOG" ]] || fail "no changelog at $CHANGELOG."

# Markdown of the version's section (or [Unreleased]) to HTML: ### headings, - lists (continuation
# lines join the item), paragraphs, **bold**, `code` and [links](url). Text is escaped first.
notes_html() {
    awk -v section="$1" '
        function inline(s,    out, pre, inner, text, href, cut) {
            gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
            while (match(s, /`[^`]+`/)) {
                s = substr(s, 1, RSTART - 1) "<code>" substr(s, RSTART + 1, RLENGTH - 2) "</code>" substr(s, RSTART + RLENGTH)
            }
            while (match(s, /\*\*[^*]+\*\*/)) {
                s = substr(s, 1, RSTART - 1) "<strong>" substr(s, RSTART + 2, RLENGTH - 4) "</strong>" substr(s, RSTART + RLENGTH)
            }
            while (match(s, /\[[^]]+\]\([^) ]+\)/)) {
                pre = substr(s, 1, RSTART - 1); inner = substr(s, RSTART + 1, RLENGTH - 2); out = substr(s, RSTART + RLENGTH)
                cut = index(inner, "](")
                text = substr(inner, 1, cut - 1); href = substr(inner, cut + 2)
                gsub(/"/, "\\&quot;", href)
                s = pre "<a href=\"" href "\">" text "</a>" out
            }
            return s
        }
        function close_block() {
            if (item != "") { print "<li>" inline(item) "</li>"; item = "" }
            if (in_list) { print "</ul>"; in_list = 0 }
            if (para != "") { print "<p>" inline(para) "</p>"; para = "" }
        }
        /^## \[/ {
            if (found) done = 1
            else if (index($0, "## [" section "]") == 1) found = 1
            next
        }
        done || !found { next }
        /^\[[^]]+\]: / { next }
        /^Will be released as / { next }
        /^### / { close_block(); print "<h3>" inline(substr($0, 5)) "</h3>"; next }
        /^- / {
            if (para != "") { print "<p>" inline(para) "</p>"; para = "" }
            if (item != "") print "<li>" inline(item) "</li>"
            if (!in_list) { print "<ul>"; in_list = 1 }
            item = substr($0, 3); next
        }
        /^[[:space:]]*$/ { close_block(); next }
        {
            line = $0; sub(/^[[:space:]]+/, "", line)
            if (item != "") item = item " " line
            else para = (para == "" ? line : para " " line)
        }
        END { close_block() }
    ' "$CHANGELOG"
}

NOTES="$(notes_html "$VERSION")"
if [[ -z "$NOTES" ]]; then
    # In the maintainer's checkout the release is still [Unreleased] (the export renames it).
    NOTES="$(notes_html Unreleased)"
    [[ -n "$NOTES" ]] && echo "appcast.sh: no CHANGELOG section for $VERSION, using [Unreleased]." >&2
fi
[[ -n "$NOTES" ]] || fail "CHANGELOG has no section for $VERSION and no [Unreleased] section with content."
[[ "$NOTES" != *"]]>"* ]] || fail "the release notes contain ]]>, which would end the CDATA block."

# Attribute values: escaped for XML, although the checks above allow none of these characters.
attr() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g'; }

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>$NAME</title>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
XML
if [[ -n "$RELEASE_PAGE" ]]; then
    echo "            <sparkle:fullReleaseNotesLink>$(attr "$RELEASE_PAGE")</sparkle:fullReleaseNotesLink>"
fi
cat <<XML
            <description><![CDATA[
$NOTES
            ]]></description>
            <enclosure url="$(attr "$URL")" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
        </item>
    </channel>
</rss>
XML
