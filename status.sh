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
#
# There are two ways to install the service and they use different launchd
# labels, so neither can be assumed: ./install.sh writes its own LaunchAgent,
# while `brew services` generates one from the formula.
MANUAL_LABEL="com.macos.compress-screenshots"
BREW_LABEL="homebrew.mxcl.macos-compress-screenshots"
BREW_FORMULA="macos-compress-screenshots"
LAUNCHAGENT_DIR="${HOME}/Library/LaunchAgents"
LOG_FILE="${HOME}/Library/Logs/compress-screenshots.log"

# Set when the service is loaded but not actually doing its job
UNHEALTHY=0

echo "======================================"
echo "Screenshot Compression Service Status"
echo "======================================"
echo

# Work out which installation is present.
#
# Both can exist at once - installing with Homebrew does not remove an earlier
# manual install - so an installation that is actually loaded is preferred over
# one that is merely on disk, and any leftover is reported rather than ignored.
LABEL=""
ON_DISK_LABEL=""
for candidate in "$BREW_LABEL" "$MANUAL_LABEL"; do
    [ -f "$LAUNCHAGENT_DIR/${candidate}.plist" ] || continue
    ON_DISK_LABEL="${ON_DISK_LABEL:-$candidate}"
    if launchctl list "$candidate" >/dev/null 2>&1; then
        LABEL="$candidate"
        break
    fi
done

# Nothing loaded, so report on whichever installation is merely present - an
# installed but stopped service still has a status worth showing
LABEL="${LABEL:-$ON_DISK_LABEL}"

if [ -z "$LABEL" ]; then
    echo -e "${RED}✗ Service not installed${NC}"
    echo
    echo "To install, either:"
    echo "  brew install $BREW_FORMULA && brew services start $BREW_FORMULA"
    echo "  ./install.sh   (from a clone of the repository)"
    exit 1
fi

LAUNCHAGENT_PATH="$LAUNCHAGENT_DIR/${LABEL}.plist"

# The commands to offer depend on which installation is in use
if [ "$LABEL" = "$BREW_LABEL" ]; then
    INSTALL_KIND="Homebrew"
    OTHER_LABEL="$MANUAL_LABEL"
    START_CMD="brew services start $BREW_FORMULA"
    RESTART_CMD="brew services restart $BREW_FORMULA"
    UNINSTALL_CMD="brew services stop $BREW_FORMULA && brew uninstall $BREW_FORMULA"
else
    INSTALL_KIND="install.sh"
    OTHER_LABEL="$BREW_LABEL"
    START_CMD="launchctl load $LAUNCHAGENT_PATH"
    RESTART_CMD="launchctl unload $LAUNCHAGENT_PATH && launchctl load $LAUNCHAGENT_PATH"
    UNINSTALL_CMD="./uninstall.sh"
fi

echo -e "${GREEN}✓ Service is installed${NC} (via $INSTALL_KIND)"
echo "  Location: $LAUNCHAGENT_PATH"

# Two installations fighting over the same folder is worth knowing about: both
# compress the same screenshots, and stopping only one leaves the other running.
if [ -f "$LAUNCHAGENT_DIR/${OTHER_LABEL}.plist" ]; then
    echo -e "${YELLOW}⚠ A second installation is also present: $OTHER_LABEL${NC}"
    echo "  Remove one of them; two services watching one folder duplicate the work."
fi
echo

# Check if service is loaded
#
# "Loaded" is not "working": the LaunchAgent has KeepAlive set, so a service that
# fails on startup is restarted forever and still appears in launchctl list. To
# tell a healthy service from a restart loop we compare the PID over a short
# interval - a PID that changes means the process is not staying up.
SERVICE_STATE=$(launchctl list "$LABEL" 2>/dev/null || true)

if [ -z "$SERVICE_STATE" ]; then
    echo -e "${RED}✗ Service is not loaded${NC}"
    echo
    echo "To start, run: $START_CMD"
    exit 1
fi

read_pid() {
    launchctl list "$LABEL" 2>/dev/null \
        | awk -F'= ' '/"PID"/ {gsub(/[^0-9]/, "", $2); print $2}'
}

LAST_EXIT=$(echo "$SERVICE_STATE" \
    | awk -F'= ' '/"LastExitStatus"/ {gsub(/[^0-9-]/, "", $2); print $2}')
PID=$(read_pid)

if [ -z "$PID" ]; then
    echo -e "${RED}✗ Service is loaded but not running${NC}"
    if [ -n "$LAST_EXIT" ] && [ "$LAST_EXIT" != "0" ]; then
        echo "  Last exit status: $LAST_EXIT"
    fi
    echo "  Check the log for the cause: $LOG_FILE"
    exit 1
fi

echo "  Checking service stability..."
sleep 3
PID_AFTER=$(read_pid)

if [ -z "$PID_AFTER" ] || [ "$PID" != "$PID_AFTER" ]; then
    echo -e "${RED}✗ Service is restarting repeatedly (crash loop)${NC}"
    echo "  The process is not staying up; KeepAlive keeps relaunching it."
    if [ -n "$LAST_EXIT" ] && [ "$LAST_EXIT" != "0" ]; then
        echo "  Last exit status: $LAST_EXIT"
    fi
    echo
    echo "  Most recent errors from the log:"
    ( grep -E "Error:|Warning:" "$LOG_FILE" 2>/dev/null || true ) | tail -5 | while IFS= read -r line; do
        echo "    $line"
    done
    UNHEALTHY=1
else
    echo -e "${GREEN}✓ Service is running${NC}"
    echo "  PID: $PID"
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

# Look for errors the service reported about itself.
#
# The PID check above cannot see these. On a fatal error the service pauses
# before exiting (FATAL_RETRY_DELAY) to avoid a KeepAlive restart storm, so for
# several minutes it holds a stable PID and looks perfectly healthy from outside.
# The log is the only place the real state shows up.
#
# Only the most recent run is inspected: once the problem is fixed and the service
# restarts, the old error lines remain in the log and would warn forever.
#
# The rotated log is read first. Rotation happens mid-run, so it can carry away
# the current run's startup marker and its errors, leaving an active log that
# holds nothing but "Log rotated" - and a broken service then looks healthy here
# for as long as its retry pause lasts. Reading both and taking everything after
# the last marker finds the run wherever rotation happened to split it.
if [ -f "$LOG_FILE" ]; then
    LAST_RUN=$(cat "${LOG_FILE}.old" "$LOG_FILE" 2>/dev/null \
        | awk '/===== compress-screenshots started =====/ {buf = ""} {buf = buf $0 ORS} END {printf "%s", buf}')
    LAST_RUN_ERRORS=$(echo "$LAST_RUN" | grep "Error:" || true)

    if [ -n "$LAST_RUN_ERRORS" ]; then
        echo -e "${RED}✗ The service reported an error on its most recent run${NC}"
        echo "$LAST_RUN_ERRORS" | while IFS= read -r line; do
            echo "  $line"
        done

        # The folder-access error is by far the most common, and the fix is not
        # obvious from the message alone
        if echo "$LAST_RUN_ERRORS" | grep -q "Cannot read"; then
            echo
            echo "  ~/Desktop, ~/Documents and ~/Downloads are protected by macOS."
            echo "  See README.md (\"Folder access on macOS\") for the fix."
        fi
        echo
        UNHEALTHY=1
    fi
fi

echo "======================================"
echo "Commands:"
echo "  View live log: tail -f $LOG_FILE"
echo "  Restart:       $RESTART_CMD"
echo "  Uninstall:     $UNINSTALL_CMD"
echo "======================================"

# Exit non-zero when the service is loaded but not actually working, so this
# script is usable as a health check
if [ "$UNHEALTHY" -ne 0 ]; then
    exit 1
fi
