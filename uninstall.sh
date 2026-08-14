#!/bin/bash
#
# uninstall.sh
# Uninstallation script for macos-compress-screenshots
#

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${HOME}/.macos-compress-screenshots"
LAUNCHAGENT_DIR="${HOME}/Library/LaunchAgents"
PLIST_NAME="com.macos.compress-screenshots.plist"
LOG_DIR="${HOME}/Library/Logs"

# The Homebrew installation this script deliberately does not touch, named here
# so the check at the end matches what status.sh reports
BREW_LABEL="homebrew.mxcl.macos-compress-screenshots"
BREW_FORMULA="macos-compress-screenshots"

echo "======================================"
echo "Uninstall macOS Screenshot Compression Tool"
echo "======================================"
echo

# Stop the service if it's running
if launchctl list | grep -q com.macos.compress-screenshots; then
    echo "Stopping service..."
    launchctl unload "$LAUNCHAGENT_DIR/$PLIST_NAME" 2>/dev/null || true
fi

# Remove LaunchAgent plist
if [ -f "$LAUNCHAGENT_DIR/$PLIST_NAME" ]; then
    echo "Removing LaunchAgent..."
    rm "$LAUNCHAGENT_DIR/$PLIST_NAME"
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
fi

# Ask about log files
echo
read -p "Do you want to remove log files as well? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "${LOG_DIR}/compress-screenshots.log"
    rm -f "${LOG_DIR}/compress-screenshots.log.old"
    rm -f "${LOG_DIR}/compress-screenshots.error.log"
    rm -f "${LOG_DIR}/compress-screenshots.out.log"
    echo "Log files removed"
fi

echo
echo -e "${GREEN}✓ Uninstallation complete!${NC}"
echo

# This script only knows about the installation install.sh creates. A Homebrew
# installation uses a different LaunchAgent, so it survives untouched here and
# would keep compressing screenshots after an apparently complete uninstall.
if [ -f "${LAUNCHAGENT_DIR}/${BREW_LABEL}.plist" ]; then
    echo -e "${YELLOW}Note: a Homebrew installation is also present and was left alone.${NC}"
    echo "To remove that one as well:"
    echo "  brew services stop $BREW_FORMULA"
    echo "  brew uninstall $BREW_FORMULA"
    echo
fi
