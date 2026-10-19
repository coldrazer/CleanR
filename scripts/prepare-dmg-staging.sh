#!/bin/bash
# Prepare the DMG staging folder for packaging (issue #149).
#
# Usage: ./scripts/prepare-dmg-staging.sh <staging-dir>
#
# The release DMG is built from a staging directory that holds CleanR.app.
# Build-only artifacts (codesign entitlements, notarize zip leftovers) must
# not ship, and a symlink to /Applications enables the standard
# drag-and-drop install UX.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <staging-dir>" >&2
    exit 2
fi

STAGING="$1"

if [[ ! -d "$STAGING" ]]; then
    echo "error: staging dir does not exist: $STAGING" >&2
    exit 1
fi

# codesign input only — never part of the shipped image
rm -f "${STAGING}/entitlements.plist"
# leftover from the pre-DMG app notarization zip step
rm -f "${STAGING}"/*-notarize.zip

# Classic macOS installer affordance: drag the app onto Applications.
# Replace any leftover path so ln never nests a link inside a directory.
rm -rf "${STAGING}/Applications"
ln -s /Applications "${STAGING}/Applications"
