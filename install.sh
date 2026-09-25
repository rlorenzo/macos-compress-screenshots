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

# Check for required dependencies.
# Both are hard requirements: without them the service starts, fails immediately,
# and is restarted forever by the LaunchAgent's KeepAlive. So missing dependencies
# are either installed here or the installation stops.
MISSING_DEPS=()
command -v fswatch >/dev/null 2>&1 || MISSING_DEPS+=("fswatch")
command -v pngquant >/dev/null 2>&1 || MISSING_DEPS+=("pngquant")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    echo "fswatch watches the screenshot folder; pngquant compresses what appears there."
    echo "The service cannot run without them."
    echo

    if ! command -v brew >/dev/null 2>&1; then
        echo -e "${RED}Error: Homebrew is not installed, so they cannot be installed automatically.${NC}"
        echo "Install Homebrew from https://brew.sh, then run:"
        echo "  brew install ${MISSING_DEPS[*]}"
        exit 1
    fi

    # `read` returns non-zero at end of input, and under `set -e` that would abort
    # the script silently instead of printing the explanation below
    REPLY=""
    read -p "Install them now with Homebrew? (y/n) " -n 1 -r || true
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborting: install the dependencies, then re-run ./install.sh${NC}"
        exit 1
    fi

    echo
    echo "Running: brew install ${MISSING_DEPS[*]}"
    if ! brew install "${MISSING_DEPS[@]}"; then
        echo -e "${RED}Error: brew install failed. Resolve the problem, then re-run ./install.sh${NC}"
        exit 1
    fi

    # A successful install still has to land somewhere on PATH for the service to use it
    for dep in "${MISSING_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "${RED}Error: $dep is still not on PATH after installation.${NC}"
            exit 1
        fi
    done

    echo
    echo -e "${GREEN}✓ Dependencies installed${NC}"
    echo
fi

# Work out where macOS actually saves screenshots, and make sure the service
# watches that folder rather than assuming the Desktop.
#
# This matters twice over: watching the wrong folder makes the service silently
# useless, and macOS protects ~/Desktop, ~/Documents and ~/Downloads with TCC so
# a LaunchAgent cannot read them at all. See README.md ("Folder access on macOS").
#
# This deliberately repeats compress-screenshots.sh's resolve_screenshot_dir
# rather than sourcing it: that script runs work at load time and sets its own
# shell options, neither of which belongs in an installer. Six lines of overlap
# is the cheaper price - but the two must agree, so change them together.
SCREENSHOT_DIR=$(defaults read com.apple.screencapture location 2>/dev/null || true)
if [ -z "$SCREENSHOT_DIR" ]; then
    # No override set, so macOS is using its default
    SCREENSHOT_DIR="${HOME}/Desktop"
fi
SCREENSHOT_DIR="${SCREENSHOT_DIR/#\~/$HOME}"   # expand a leading ~
SCREENSHOT_DIR="${SCREENSHOT_DIR%/}"           # drop any trailing slash

# Folders macOS restricts access to, including anything nested inside them
is_protected_dir() {
    case "$1" in
        "${HOME}/Desktop"|"${HOME}/Desktop/"*) return 0 ;;
        "${HOME}/Documents"|"${HOME}/Documents/"*) return 0 ;;
        "${HOME}/Downloads"|"${HOME}/Downloads/"*) return 0 ;;
    esac
    return 1
}

WATCH_DIR="$SCREENSHOT_DIR"
SUGGESTED_DIR="${HOME}/Screenshots"

echo "Screenshots are currently saved to: $SCREENSHOT_DIR"

if is_protected_dir "$SCREENSHOT_DIR"; then
    echo
    echo -e "${YELLOW}macOS protects that folder, and this service cannot read it.${NC}"
    echo "Background services have no access to ~/Desktop, ~/Documents or ~/Downloads"
    echo "unless they are granted Full Disk Access."
    echo

    if [ ! -t 0 ]; then
        # Not interactive: never change a user's settings without them saying so
        echo -e "${YELLOW}Running non-interactively - leaving the screenshot location unchanged.${NC}"
        echo "The service will not compress anything until you move the screenshot"
        echo "location. See README.md (\"Folder access on macOS\")."
        echo
    else
        # Full Disk Access is granted per-executable, not per-script, so granting it
        # to /bin/bash would hand every bash script on the machine unrestricted
        # access to Mail, Messages, Safari history, and other users' data - a cost
        # this installer is not willing to ask for on the tool's behalf.
        echo "  1) Save screenshots to $SUGGESTED_DIR instead (recommended, no extra permissions)"
        echo "  2) Cancel"
        echo
        # As above: guard `read` so end of input falls back to the default
        # instead of aborting under `set -e`
        CHOICE=""
        read -p "Choice [1]: " -r CHOICE || true
        CHOICE="${CHOICE:-1}"
        echo

        case "$CHOICE" in
            1)
                mkdir -p "$SUGGESTED_DIR"
                defaults write com.apple.screencapture location "$SUGGESTED_DIR"
                killall SystemUIServer 2>/dev/null || true
                WATCH_DIR="$SUGGESTED_DIR"
                echo -e "${GREEN}✓ Screenshots will now be saved to $SUGGESTED_DIR${NC}"
                echo "  To undo this later: defaults delete com.apple.screencapture location && killall SystemUIServer"
                echo
                ;;
            *)
                echo "Installation cancelled."
                exit 1
                ;;
        esac
    fi
fi

# The service can only watch a folder that exists
if [ ! -d "$WATCH_DIR" ]; then
    echo -e "${RED}Error: The screenshot folder does not exist: $WATCH_DIR${NC}"
    echo "Create it, or change your screenshot location, then re-run ./install.sh"
    exit 1
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
cp compress-screenshots.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/compress-screenshots.sh"

# Create LaunchAgent plist
echo "Installing LaunchAgent..."
if [ ! -f "com.macos.compress-screenshots.plist" ]; then
    echo -e "${RED}Error: Template plist file 'com.macos.compress-screenshots.plist' not found.${NC}"
    echo "Please run this script from the directory containing com.macos.compress-screenshots.plist."
    exit 1
fi
# A path reaches the plist through sed's replacement text and then through XML,
# and each of those treats some characters specially. `&` is the worst case: sed
# expands it to the text it just matched and XML reads it as the start of an
# entity, so a folder named "Screens & Recordings" would otherwise yield the path
# "/Users/you/Screens WATCH_DIR_PATH Recordings" inside a plist launchctl refuses
# to load.
plist_value() {
    local value="$1"
    # XML first, so the ampersands it introduces get escaped for sed below
    value=${value//&/&amp;}
    value=${value//</&lt;}
    value=${value//>/&gt;}
    # Then the characters sed consumes in a replacement: backslash, `&`, and the
    # `|` used as the s/// delimiter
    value=${value//\\/\\\\}
    value=${value//&/\\&}
    value=${value//|/\\|}
    printf '%s' "$value"
}

sed -e "s|INSTALL_PATH|$(plist_value "$INSTALL_DIR")|g" \
    -e "s|LOG_PATH|$(plist_value "$LOG_DIR")|g" \
    -e "s|WATCH_DIR_PATH|$(plist_value "$WATCH_DIR")|g" \
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
echo "Watching: $WATCH_DIR"
echo
echo "Logs can be found at:"
echo "  ${HOME}/Library/Logs/compress-screenshots.log"
echo
echo "To uninstall, run:"
echo "  ./uninstall.sh"
echo
