#!/bin/bash
# Completely remove CleanR and its support files.
# Usage: curl -fsSL https://raw.githubusercontent.com/coldrazer/CleanR/main/scripts/uninstall.sh | bash
#
# Homebrew users can instead run:  brew uninstall --zap --cask cleanr
# (the --zap flag removes the same support files via the cask's zap stanza).

set -euo pipefail

APP_NAME="CleanR.app"
INSTALL_DIR="/Applications"

cyan() { printf "\033[36m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# Guard: HOME must be set so the explicit paths below never expand to "/...".
if [ -z "${HOME:-}" ]; then
  red "HOME is not set; aborting to avoid removing unintended paths."
  exit 1
fi

# Exact, explicit paths only (no globs, no wildcards) so this can never delete
# more than CleanR's own files.
SUPPORT_PATHS=(
  "$HOME/Library/Application Support/CleanR"
  "$HOME/Library/Caches/com.cleanr.app"
  "$HOME/Library/HTTPStorages/com.cleanr.app"
  "$HOME/Library/Logs/CleanR"
  "$HOME/Library/Preferences/com.cleanr.app.plist"
  "$HOME/Library/Preferences/com.cleanr.shared.plist"
  "$HOME/Library/Saved Application State/com.cleanr.app.savedState"
)

cyan "Quitting CleanR if it is running..."
osascript -e 'tell application "CleanR" to quit' >/dev/null 2>&1 || true
# The menu-bar helper is a separate process.
pkill -f "CleanRMenu" >/dev/null 2>&1 || true

# Prefer Homebrew's own uninstall when the cask is installed, so brew's receipt
# stays consistent. --zap removes the support files too, so we're done after it.
if command -v brew >/dev/null 2>&1 && brew list --cask cleanr >/dev/null 2>&1; then
  cyan "Removing the Homebrew cask (with --zap to clear support files)..."
  brew uninstall --zap --cask cleanr
  green "✓ CleanR and its support files were removed via Homebrew."
  exit 0
fi

cyan "Removing $INSTALL_DIR/$APP_NAME..."
rm -rf "$INSTALL_DIR/$APP_NAME"

cyan "Removing support files..."
for path in "${SUPPORT_PATHS[@]}"; do
  if [ -e "$path" ]; then
    rm -rf "$path"
    echo "  removed $path"
  fi
done

# Clear any cached preferences held by cfprefsd so they don't get rewritten.
defaults delete com.cleanr.app >/dev/null 2>&1 || true
defaults delete com.cleanr.shared >/dev/null 2>&1 || true

green ""
green "✓ CleanR has been uninstalled."
echo ""
echo "If CleanR still appears under System Settings → General → Login Items,"
echo "remove the leftover entry there; macOS clears it once the app is gone."
