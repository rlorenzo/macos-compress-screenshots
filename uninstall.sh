#!/bin/bash
#
# uninstall.sh
# Uninstallation script for macos-compress-screenshots
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${HOME}/.macos-compress-screenshots"
LAUNCHAGENT_DIR="${HOME}/Library/LaunchAgents"
PLIST_NAME="com.macos.compress-screenshots.plist"
LOG_DIR="${HOME}/Library/Logs"

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
