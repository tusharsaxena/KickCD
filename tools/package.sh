#!/usr/bin/env bash
# tools/package.sh — build a redistributable zip of the KickCD addon.
#
# Output: KickCD-<version>.zip in the repo root, containing only what
# WoW needs at runtime (TOC, lua, xml, libs, locales, media, LICENSE).
# Excludes docs/, tools/, .git/, OS junk.
#
# Usage:  ./tools/package.sh           # uses ## Version from KickCD.toc
#         ./tools/package.sh 0.1.1     # override
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-$(grep -E '^## Version:' KickCD.toc | awk '{print $3}')}"
if [[ -z "$VERSION" ]]; then
    echo "Could not read version from KickCD.toc" >&2
    exit 1
fi

ZIP="KickCD-${VERSION}.zip"
rm -f "$ZIP"

# Sanity: TOC, LICENSE, README must exist
for f in KickCD.toc LICENSE README.md; do
    [[ -f "$f" ]] || { echo "Missing $f" >&2; exit 1; }
done

# Build the zip with the addon folder name as the top-level directory.
# WoW expects to extract to Interface/AddOns/KickCD/, so the zip's top
# entry must be "KickCD/...".
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/KickCD"
cp -R \
    KickCD.toc \
    LICENSE \
    README.md \
    libs \
    locales \
    core \
    defaults \
    modules \
    settings \
    media \
    "$STAGE/KickCD/"

# Strip OS junk and editor backups that may have crept in.
find "$STAGE/KickCD" \( -name '.DS_Store' -o -name 'Thumbs.db' \
                       -o -name '*.swp' -o -name '*~' \) -delete

(cd "$STAGE" && zip -qr "$REPO_ROOT/$ZIP" KickCD)
echo "Built $ZIP ($(du -h "$ZIP" | awk '{print $1}'))"
