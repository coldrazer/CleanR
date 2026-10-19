#!/bin/bash
# One-time setup: creates the homebrew-cleanr tap repository and pushes the
# current Casks/cleanr.rb into it.
#
# Sync after that is driven from the main repo — the release workflow's
# "Update Homebrew cask in tap repo" step commits the new cask on every stable
# release, so this script does not install a watcher workflow here.
#
# Requires: gh CLI authenticated, and the cask at Casks/cleanr.rb.
# Usage: bash scripts/setup-homebrew-tap.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
CASK_SOURCE="${REPO_ROOT}/Casks/cleanr.rb"

if [ ! -f "$CASK_SOURCE" ]; then
    echo "Missing ${CASK_SOURCE} — nothing to publish."
    exit 1
fi

GH_USER=$(gh api user --jq .login)

# The tap must point at the project's real owner, which is not necessarily the
# person running this script: hard-coding the authenticated login produced
# "brew tap <personal-user>/cleanr" instructions for a project published under
# an org. Prefer the origin remote, fall back to the logged-in user.
REMOTE_URL=$(cd "$REPO_ROOT" && git remote get-url origin 2>/dev/null || true)
OWNER=""
if [ -n "$REMOTE_URL" ]; then
    # Accept all three forms GitHub hands out — https://host/o/r(.git),
    # git@host:o/r(.git) and ssh://git@host[:port]/o/r(.git) — by normalizing
    # to a slash-separated path and taking the second-to-last segment.
    path="${REMOTE_URL%.git}"
    path="${path#*://}"
    path="${path#*@}"
    path="${path//:/\/}"
    OWNER=$(basename "$(dirname "$path")")
fi
# A login or owner that isn't a bare GitHub account name means the parse went
# wrong somewhere; better to use the authenticated account than to bake a
# broken tap URL into the README.
if ! [[ "$OWNER" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38}[A-Za-z0-9])?$ ]]; then
    OWNER="$GH_USER"
    echo "Could not read an owner from the git remote; using the authenticated account (${OWNER})."
fi

TAP_REPO="homebrew-cleanr"

echo "=== Setting up Homebrew tap for ${OWNER}/${TAP_REPO} ==="

# Check if already exists
if gh repo view "${OWNER}/${TAP_REPO}" &>/dev/null; then
    echo "Tap repo ${OWNER}/${TAP_REPO} already exists."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "${TMP}/Casks"
cp "$CASK_SOURCE" "${TMP}/Casks/cleanr.rb"

cat > "${TMP}/README.md" <<EOF
# homebrew-cleanr

Homebrew tap for [CleanR](https://github.com/${OWNER}/CleanR), the proprietary Mac cleaner created and licensed by Apex Studio LLC.

## Install

\`\`\`bash
brew tap ${OWNER}/cleanr && brew install --cask cleanr
\`\`\`

This tap is automatically updated when new versions of CleanR are released.
EOF

cd "$TMP"
git init -b main >/dev/null
git add .
git commit -m "Initial tap with CleanR cask" >/dev/null

gh repo create "${TAP_REPO}" --public --source . --description "Homebrew tap for CleanR" --push

echo ""
echo "✅ Tap created at https://github.com/${OWNER}/${TAP_REPO}"
echo ""
echo "Users can now install with:"
echo "  brew tap ${OWNER}/cleanr && brew install --cask cleanr"
echo ""
echo "Next: the release workflow keeps the cask in sync via auto-commits."
