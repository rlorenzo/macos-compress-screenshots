#!/bin/bash
#
# install.sh
# Installation script for macos-compress-screenshots
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
echo "macOS Screenshot Compression Tool"
echo "======================================"
echo

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script only works on macOS${NC}"
    exit 1
fi

# Check if fswatch is installed
if ! command -v fswatch >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: fswatch is not installed${NC}"
    echo "fswatch is required to monitor for new screenshots."
    echo
    echo "To install fswatch, run:"
    echo "  brew install fswatch"
    echo
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if pngquant is installed
if ! command -v pngquant >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: pngquant is not installed${NC}"
    echo "pngquant is required to compress screenshots."
    echo
    echo "To install pngquant, run:"
    echo "  brew install pngquant"
    echo
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCHAGENT_DIR"

# Copy script to installation directory
echo "Installing compress-screenshots.sh..."
if [ ! -f "compress-screenshots.sh" ]; then
    echo -e "${RED}Error: compress-screenshots.sh not found in the current directory: $(pwd)${NC}"
    echo "Please run install.sh from the directory that contains compress-screenshots.sh."
    exit 1
fi
if [ ! -f "compress-screenshots.sh" ]; then
    echo -e "${RED}Error: compress-screenshots.sh not found in the current directory: $(pwd)${NC}"
    echo "Please run install.sh from the directory that contains compress-screenshots.sh."
    exit 1
fi
cp compress-screenshots.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/compress-screenshots.sh"

# Create LaunchAgent plist
echo "Installing LaunchAgent..."
if [ ! -f "com.macos.compress-screenshots.plist" ]; then
    echo -e "${RED}Error: Template plist file 'com.macos.compress-screenshots.plist' not found.${NC}"
    echo "Please run this script from the directory containing com.macos.compress-screenshots.plist."
    exit 1
fi
if [ ! -f "com.macos.compress-screenshots.plist" ]; then
    echo -e "${RED}Error: Template plist file 'com.macos.compress-screenshots.plist' not found.${NC}"
    echo "Please run this script from the directory containing com.macos.compress-screenshots.plist."
    exit 1
fi
sed -e "s|INSTALL_PATH|${INSTALL_DIR}|g" \
    -e "s|LOG_PATH|${LOG_DIR}|g" \
    com.macos.compress-screenshots.plist > "$LAUNCHAGENT_DIR/$PLIST_NAME"

# Stop existing service if running
if launchctl list | grep -q com.macos.compress-screenshots; then
    echo "Stopping existing service..."
    launchctl unload "$LAUNCHAGENT_DIR/$PLIST_NAME" 2>/dev/null || true
fi

# Load the LaunchAgent
echo "Starting service..."
launchctl load "$LAUNCHAGENT_DIR/$PLIST_NAME"

echo
echo -e "${GREEN}✓ Installation complete!${NC}"
echo
echo "The screenshot compression service is now running in the background."
echo "It will automatically start when you log in."
echo
echo "Logs can be found at:"
echo "  ${HOME}/Library/Logs/compress-screenshots.log"
echo
echo "To uninstall, run:"
echo "  ./uninstall.sh"
echo
