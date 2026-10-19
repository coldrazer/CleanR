#!/bin/bash
# Verify that the VERSION file and MCConstants.appVersion stay in lockstep.
# Run as a CI guard; loud failure beats a silent "v1.2.1" subtitle on the
# v1.3.0 release.
set -euo pipefail

VERSION_FILE_VALUE=$(tr -d '[:space:]' < VERSION)
SWIFT_CONSTANT_VALUE=$(
    grep -E 'public static let appVersion\s*=\s*"' \
        Sources/CleanRKit/Constants.swift \
    | sed -E 's/.*"([^"]+)".*/\1/'
)

if [[ -z "$VERSION_FILE_VALUE" ]]; then
    echo "::error::VERSION file is empty"
    exit 1
fi
if [[ -z "$SWIFT_CONSTANT_VALUE" ]]; then
    echo "::error::Couldn't extract MCConstants.appVersion from Constants.swift"
    exit 1
fi

if [[ "$VERSION_FILE_VALUE" != "$SWIFT_CONSTANT_VALUE" ]]; then
    cat <<MSG
::error::VERSION ($VERSION_FILE_VALUE) and MCConstants.appVersion ($SWIFT_CONSTANT_VALUE) drift.

Both must be bumped together. The release pipeline reads VERSION to
name the DMG and tag the GitHub release; the app's title bar reads
MCConstants.appVersion. If they don't match, users see a different
version in the title bar than what brew installed — exactly the kind
of "did I actually upgrade?" confusion the constant exists to solve.

Fix:
  - Edit VERSION (current: $VERSION_FILE_VALUE)
  - Edit Sources/CleanRKit/Constants.swift's appVersion (current: $SWIFT_CONSTANT_VALUE)
  - Make them equal.
MSG
    exit 1
fi

echo "Version sync OK: $VERSION_FILE_VALUE"
