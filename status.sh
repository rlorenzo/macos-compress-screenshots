#!/bin/bash
#
# status.sh
# Check the status of the screenshot compression service
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PLIST_NAME="com.macos.compress-screenshots.plist"
LAUNCHAGENT_PATH="${HOME}/Library/LaunchAgents/$PLIST_NAME"
LOG_FILE="${HOME}/Library/Logs/compress-screenshots.log"

echo "======================================"
echo "Screenshot Compression Service Status"
echo "======================================"
echo

# Check if LaunchAgent is installed
if [ ! -f "$LAUNCHAGENT_PATH" ]; then
    echo -e "${RED}✗ Service not installed${NC}"
    echo
    echo "To install, run: ./install.sh"
    exit 1
fi

echo -e "${GREEN}✓ Service is installed${NC}"
echo "  Location: $LAUNCHAGENT_PATH"
echo

# Check if service is loaded
if launchctl list | grep -q com.macos.compress-screenshots; then
    echo -e "${GREEN}✓ Service is running${NC}"
    
    # Get PID
    PID=$(launchctl list | grep com.macos.compress-screenshots | awk '{print $1}')
    if [ "$PID" != "-" ]; then
        echo "  PID: $PID"
    fi
else
    echo -e "${RED}✗ Service is not running${NC}"
    echo
    echo "To start, run: launchctl load $LAUNCHAGENT_PATH"
    exit 1
fi

echo

# Check for fswatch
if command -v fswatch >/dev/null 2>&1; then
    echo -e "${GREEN}✓ fswatch is installed${NC}"
    echo "  Version: $(fswatch --version 2>&1 | head -1)"
else
    echo -e "${YELLOW}⚠ fswatch is not installed${NC}"
    echo "  Install with: brew install fswatch"
fi

echo

# Check for pngquant
if command -v pngquant >/dev/null 2>&1; then
    echo -e "${GREEN}✓ pngquant is installed${NC}"
    echo "  Version: $(pngquant --version 2>&1 | head -1)"
else
    echo -e "${YELLOW}⚠ pngquant is not installed${NC}"
    echo "  Install with: brew install pngquant"
fi

echo

# Check log file
if [ -f "$LOG_FILE" ]; then
    echo -e "${BLUE}Recent Activity:${NC}"
    echo "  Log file: $LOG_FILE"
    echo "  Size: $(du -h "$LOG_FILE" | awk '{print $1}')"
    echo
    echo "Last 5 compression events:"
    ( grep -E "Compressed:|started|Processing" "$LOG_FILE" || true ) | tail -5 | while IFS= read -r line; do
        echo "  $line"
    done
else
    echo -e "${YELLOW}⚠ No log file found${NC}"
    echo "  The service may not have processed any screenshots yet."
fi

echo
echo "======================================"
echo "Commands:"
echo "  View live log: tail -f $LOG_FILE"
echo "  Restart:       launchctl unload $LAUNCHAGENT_PATH && launchctl load $LAUNCHAGENT_PATH"
echo "  Uninstall:     ./uninstall.sh"
echo "======================================"
