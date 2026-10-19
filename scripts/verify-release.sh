#!/bin/bash
# Post-release verification: confirm what users actually get agrees with
# what this repo thinks it shipped.
#
#   scripts/verify-release.sh [TAG]     # default: v$(cat VERSION)
#
# Checks (hard failures):
#   1. The GitHub release exists and carries CleanR-<version>.dmg.
#   2. The release tag matches the VERSION file (stable releases only).
#   3. The update endpoint the app calls (/releases/latest) resolves.
# Checks (warnings — needs tap read access, may be unavailable in CI):
#   4. The Homebrew tap cask names the same version.
#
# Requires: gh (authenticated), curl. Exits non-zero on any hard failure.

set -uo pipefail
cd "$(dirname "$0")/.."

REPO="${GH_REPO:-coldrazer/CleanR}"
FILE_VERSION=$(tr -d '[:space:]' < VERSION)
TAG="${1:-v$FILE_VERSION}"
VERSION="${TAG#v}"
fail=0

echo "Verifying $TAG in $REPO (VERSION file: $FILE_VERSION)"

# 1 + 2. Release exists with the DMG asset, tag matches VERSION.
if [[ "$VERSION" != *-* && "$VERSION" != "$FILE_VERSION" ]]; then
    echo "::error::Tag $TAG does not match VERSION file ($FILE_VERSION)"
    fail=1
fi

ASSETS=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null) || {
    echo "::error::Release $TAG not found in $REPO"
    exit 1
}
if ! grep -qx "CleanR-${VERSION}.dmg" <<< "$ASSETS"; then
    echo "::error::Release $TAG is missing CleanR-${VERSION}.dmg (assets: $(echo $ASSETS))"
    fail=1
else
    echo "  ✓ release asset CleanR-${VERSION}.dmg"
fi

# 3. The latest-release endpoint installed copies poll.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    "https://api.github.com/repos/${REPO}/releases/latest")
if [ "$CODE" != "200" ]; then
    echo "::error::releases/latest returned HTTP $CODE — installed copies will not see updates"
    fail=1
else
    echo "  ✓ releases/latest endpoint"
fi

# 4. Homebrew tap cask version (best effort: tap read needs access).
TAP="${REPO%%/*}/homebrew-cleanr"
CASK=$(gh api "repos/${TAP}/contents/Casks/cleanr.rb" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) || CASK=""
if [ -z "$CASK" ]; then
    echo "  ! could not read tap ${TAP} (needs access) — skipped cask check"
elif grep -q "version \"${VERSION}\"" <<< "$CASK"; then
    echo "  ✓ Homebrew cask version ${VERSION}"
else
    echo "::warning::Homebrew cask in ${TAP} is not at ${VERSION} yet"
fi

if [ "$fail" != "0" ]; then
    echo "Release verification FAILED"
    exit 1
fi
echo "Release verification passed for $TAG"
