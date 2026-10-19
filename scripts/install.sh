#!/bin/bash
# One-line installer for CleanR.
# Usage: curl -fsSL https://raw.githubusercontent.com/coldrazer/CleanR/main/scripts/install.sh | bash

set -euo pipefail

REPO="coldrazer/CleanR"
APP_NAME="CleanR.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

cyan() { printf "\033[36m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# Check macOS version
OS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OS_VERSION" -lt 14 ]; then
    red "CleanR requires macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

cyan "Fetching latest release info..."
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
DMG_URL=$(echo "$LATEST" | grep -oE '"browser_download_url":\s*"[^"]+\.dmg"' | head -1 | cut -d'"' -f4)
VERSION=$(echo "$LATEST" | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | cut -d'"' -f4)

if [ -z "$DMG_URL" ]; then
    red "Could not find a DMG in the latest release. Aborting."
    exit 1
fi

cyan "Downloading CleanR $VERSION..."
TMP=$(mktemp -d)
DMG_PATH="$TMP/cleanr.dmg"
# Mount at a known path: `-quiet` prints nothing to parse, and the volume
# name ("CleanR") contains a space.
MOUNT="$TMP/mount"
cleanup() {
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT
curl -fsSL "$DMG_URL" -o "$DMG_PATH"

cyan "Mounting DMG..."
mkdir -p "$MOUNT"
if ! hdiutil attach -nobrowse -noautoopen -quiet -mountpoint "$MOUNT" "$DMG_PATH"; then
    red "Failed to mount the DMG."
    exit 1
fi

APP_SRC="$MOUNT/$APP_NAME"
if [ ! -d "$APP_SRC" ]; then
    red "The DMG does not contain $APP_NAME."
    exit 1
fi

# Verify before installing. A file fetched with curl carries no quarantine
# attribute, so Launch Services would never run its Gatekeeper check on first
# open — this script is the only place that assessment happens.
cyan "Verifying code signature..."
if ! codesign --verify --deep --strict --verbose=2 "$APP_SRC" 2>/dev/null; then
    red "The app's code signature is invalid. Refusing to install."
    exit 1
fi

cyan "Checking notarization..."
if ! spctl --assess --type execute --verbose=2 "$APP_SRC" 2>/dev/null; then
    red "macOS Gatekeeper rejects this build (not notarized, or not signed with "
    red "a Developer ID). Refusing to install."
    exit 1
fi
# A missing staple is recoverable — the ticket can still be fetched online —
# so it is reported rather than treated as a rejection.
if ! xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    cyan "Note: the DMG is not stapled with its notarization ticket."
fi

# Checked before anything is deleted: without this, a read-only /Applications
# (or one owned by root) removed the existing app and then failed to copy the
# new one, leaving the user with neither.
if [ ! -w "$INSTALL_DIR" ]; then
    red "$INSTALL_DIR is not writable by $(id -un). Re-run with sudo, or set INSTALL_DIR:"
    red "  INSTALL_DIR=\"\$HOME/Applications\" curl -fsSL … | bash"
    exit 1
fi

cyan "Installing to $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi
cp -R "$APP_SRC" "$INSTALL_DIR/"

cyan "Cleaning up..."
cleanup
trap - EXIT

green ""
green "✓ CleanR $VERSION installed to $INSTALL_DIR/$APP_NAME"
green ""
echo "Launch with: open \"$INSTALL_DIR/$APP_NAME\""
echo ""
echo "For Mail, Safari, and Privacy scans, grant Full Disk Access:"
echo "  System Settings → Privacy & Security → Full Disk Access"
