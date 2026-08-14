#!/bin/bash
#
# test-compression.sh
# Test script to validate the screenshot compression functionality
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Testing Screenshot Compression"
echo "======================================"
echo

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo "Test directory: $TEST_DIR"

# Function to cleanup
cleanup() {
    echo
    echo "Cleaning up test files..."
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Load the real implementation rather than keeping a copy of it here. A copied
# function passes its tests happily while the shipped one is broken, which is
# exactly how the locale bug covered by Test 7 reached users. compress-screenshots.sh
# only runs main() when executed directly, so sourcing it just defines the functions.
SCRIPT_UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compress-screenshots.sh"
if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
    echo -e "${RED}✗ compress-screenshots.sh not found next to this script${NC}"
    exit 1
fi

# Keep the service's own configuration inside the test directory
WATCH_DIR="$TEST_DIR"
LOG_FILE="$TEST_DIR/compress-screenshots.log"
# shellcheck source=compress-screenshots.sh
source "$SCRIPT_UNDER_TEST"

# Test 1: Check if pngquant command is available
echo "Test 1: Checking for pngquant command..."
if command -v pngquant >/dev/null 2>&1; then
    echo -e "${GREEN}✓ pngquant is available${NC}"
    pngquant --version
else
    echo -e "${RED}✗ pngquant is not available${NC}"
    echo "Install with: brew install pngquant"
    exit 1
fi

# Test 2: Create a test PNG file
echo
echo "Test 2: Creating test PNG file..."
TEST_FILE="$TEST_DIR/Screen Shot 2024-01-23 at 10.30.45 AM.png"

# Create a simple test PNG with ImageMagick or sips if available
if command -v sips >/dev/null 2>&1; then
    # Create a 200x200 PNG from a system icon
    sips -z 200 200 -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns --out "$TEST_FILE" >/dev/null 2>&1
elif command -v convert >/dev/null 2>&1; then
    # Use ImageMagick if available
    convert -size 200x200 xc:white "$TEST_FILE" 2>/dev/null
else
    echo -e "${YELLOW}⚠ Cannot create test file without sips or ImageMagick${NC}"
    echo "This test requires macOS (sips) or ImageMagick (convert)"
    exit 1
fi

if [ -f "$TEST_FILE" ]; then
    echo -e "${GREEN}✓ Test PNG created${NC}"
    ls -lh "$TEST_FILE"
else
    echo -e "${RED}✗ Failed to create test PNG${NC}"
    exit 1
fi

# Test 3: Test screenshot pattern matching
echo
echo "Test 3: Testing screenshot pattern matching..."

# Narrow no-break space (U+202F) used by macOS before AM/PM
# Using printf with octal codes since bash 3.2 doesn't support \u escapes
NNBSP=$(printf '\342\200\257')

# Test with various screenshot naming formats
# Note: macOS uses narrow no-break space (U+202F) before AM/PM, not regular space
TEST_CASES=(
    "$TEST_FILE"
    "$TEST_DIR/Screenshot 2024-01-23 at 2.11.11 PM.png"
    "$TEST_DIR/Screen Shot 2024-12-25 at 10.30.45 AM.png"
    "$TEST_DIR/Screenshot 2024-01-23 at 2.11.11${NNBSP}PM.png"
)

for test_case in "${TEST_CASES[@]}"; do
    touch "$test_case"  # Create the file if it doesn't exist
    if is_screenshot "$test_case"; then
        echo -e "${GREEN}✓ Pattern matches: $(basename "$test_case")${NC}"
    else
        echo -e "${RED}✗ Pattern does not match: $(basename "$test_case")${NC}"
        exit 1
    fi
done

# Test 4: Test compression with pngquant
echo
echo "Test 4: Testing PNG compression with pngquant..."

# Get original size (handle both macOS and Linux stat)
if stat -f%z "$TEST_FILE" >/dev/null 2>&1; then
    ORIGINAL_SIZE=$(stat -f%z "$TEST_FILE")
else
    ORIGINAL_SIZE=$(stat -c%s "$TEST_FILE")
fi
echo "Original size: $ORIGINAL_SIZE bytes"

# Make a copy to test compression
TEST_COPY="$TEST_DIR/test-copy.png"
cp "$TEST_FILE" "$TEST_COPY"

if pngquant --quality=65-80 --skip-if-larger --force --ext .png "$TEST_COPY" >/dev/null 2>&1; then
    # Get new size (handle both macOS and Linux stat)
    if stat -f%z "$TEST_COPY" >/dev/null 2>&1; then
        NEW_SIZE=$(stat -f%z "$TEST_COPY")
    else
        NEW_SIZE=$(stat -c%s "$TEST_COPY")
    fi
    echo "Compressed size: $NEW_SIZE bytes"
    
    if [ -f "$TEST_COPY" ]; then
        echo -e "${GREEN}✓ Compression successful${NC}"
        
        SAVED=$((ORIGINAL_SIZE - NEW_SIZE))
        if [ "$ORIGINAL_SIZE" -gt 0 ]; then
            PERCENT=$((SAVED * 100 / ORIGINAL_SIZE))
            echo "Saved: $SAVED bytes (${PERCENT}%)"
        fi
    else
        echo -e "${RED}✗ Compressed file not found${NC}"
        exit 1
    fi
else
    # pngquant returns non-zero if file would not benefit from compression
    echo -e "${GREEN}✓ Compression tested (file may already be optimal)${NC}"
fi

# Test 5: Test with non-screenshot file
echo
echo "Test 5: Testing non-screenshot file rejection..."
NON_SCREENSHOT="$TEST_DIR/regular-file.png"
cp "$TEST_FILE" "$NON_SCREENSHOT"

if is_screenshot "$NON_SCREENSHOT"; then
    echo -e "${RED}✗ Non-screenshot should not match pattern${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Non-screenshot correctly rejected${NC}"
fi

# Test 6: Test that invalid characters before AM/PM are rejected
echo
echo "Test 6: Testing rejection of invalid characters before AM/PM..."
INVALID_CASES=(
    "$TEST_DIR/Screenshot 2024-01-23 at 2.11.11XPM.png"
    "$TEST_DIR/Screenshot 2024-01-23 at 2.11.11-PM.png"
    "$TEST_DIR/Screenshot 2024-01-23 at 2.11.11@PM.png"
)

for invalid_case in "${INVALID_CASES[@]}"; do
    touch "$invalid_case"
    if is_screenshot "$invalid_case"; then
        echo -e "${RED}✗ Invalid filename should not match: $(basename "$invalid_case")${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Invalid filename correctly rejected: $(basename "$invalid_case")${NC}"
    fi
done

# Test 7: Pattern matching must not depend on the locale
echo
echo "Test 7: Testing pattern matching in the C locale (launchd environment)..."

# launchd starts services with no locale set, which bash treats as the C locale.
# A bracket expression containing the narrow no-break space silently fails there,
# so every real screenshot is rejected when running as a background service while
# the tests still pass in a UTF-8 terminal. This test runs the real script's
# matcher under C to catch that regression.
LOCALE_PROBE="$TEST_DIR/locale-probe.sh"
cat > "$LOCALE_PROBE" <<'PROBE'
source "$SCRIPT_UNDER_TEST"
NNBSP=$(printf '\342\200\257')
is_screenshot "Screenshot 2024-01-23 at 2.11.11${NNBSP}PM.png" || exit 1
is_screenshot "Screenshot 2024-01-23 at 2.11.11 PM.png" || exit 2
if is_screenshot "Screenshot 2024-01-23 at 2.11.11XPM.png"; then exit 3; fi
exit 0
PROBE

# `env -i` clears the environment the way launchd does, so everything the script
# needs has to be passed back in explicitly
probe_env() {
    env -i \
        SCRIPT_UNDER_TEST="$SCRIPT_UNDER_TEST" \
        HOME="$TEST_DIR" \
        WATCH_DIR="$TEST_DIR" \
        LOG_FILE="$TEST_DIR/locale-probe.log" \
        "$@" /bin/bash "$LOCALE_PROBE"
}

for loc in "en_US.UTF-8" "C"; do
    if probe_env LC_ALL="$loc"; then
        echo -e "${GREEN}✓ Pattern behaves correctly under LC_ALL=$loc${NC}"
    else
        echo -e "${RED}✗ Pattern failed under LC_ALL=$loc${NC}"
        echo "  A multi-byte bracket expression is likely being used again."
        exit 1
    fi
done

# And with no locale variables at all, exactly as launchd runs the service
if probe_env; then
    echo -e "${GREEN}✓ Pattern behaves correctly with no locale set (launchd)${NC}"
else
    echo -e "${RED}✗ Pattern failed with no locale set - the service would reject all screenshots${NC}"
    exit 1
fi

# Test 8: Recognising this tool's own output
echo
echo "Test 8: Testing detection of already-compressed (palette) PNGs..."

# pngquant writes indexed/palette PNGs while macOS screenshots are RGBA, and that
# difference is what stops the service reprocessing its own output forever.
PALETTE_FILE="$TEST_DIR/palette-check.png"
cp "$TEST_FILE" "$PALETTE_FILE"

if is_palette_png "$PALETTE_FILE"; then
    echo -e "${RED}✗ An uncompressed RGBA screenshot must not look already-compressed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Uncompressed screenshot is not treated as palette${NC}"

# A non-PNG must not be misread through the fixed PNG header offsets. Byte 25 is
# deliberately 0x03 here - the value a palette PNG carries - so this only passes
# while the IHDR signature check in front of that offset is doing its job.
NOT_A_PNG="$TEST_DIR/not-a-png.bin"
FILLER=$(printf 'x%.0s' {1..25})
printf '%s\003 trailing bytes' "$FILLER" > "$NOT_A_PNG"
if is_palette_png "$NOT_A_PNG"; then
    echo -e "${RED}✗ A non-PNG file must not be treated as palette${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Non-PNG file is not treated as palette${NC}"

PALETTE_AVAILABLE=0
if pngquant --quality=65-80 --skip-if-larger --force --ext .png "$PALETTE_FILE" >/dev/null 2>&1; then
    if is_palette_png "$PALETTE_FILE"; then
        echo -e "${GREEN}✓ pngquant output is correctly identified as palette${NC}"
        PALETTE_AVAILABLE=1
    else
        echo -e "${RED}✗ pngquant output should be identified as palette${NC}"
        echo "  Without this the service reprocesses every file it compresses."
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ pngquant declined to compress the test image${NC}"
    echo "  Cannot verify palette detection against real output on this machine."
fi

# Test 9: Compression must be idempotent
echo
echo "Test 9: Testing that a compressed screenshot is not compressed again..."

if [ "$PALETTE_AVAILABLE" -eq 0 ]; then
    echo -e "${YELLOW}⚠ Skipped: needs a test image pngquant will compress${NC}"
else
    REPEAT_FILE="$TEST_DIR/Screenshot 2024-02-01 at 9.15.30 AM.png"
    cp "$TEST_FILE" "$REPEAT_FILE"

    compress_png "$REPEAT_FILE"
    FIRST_SUM=$(shasum "$REPEAT_FILE" | awk '{print $1}')
    LOG_LINES_BEFORE=$(wc -l < "$LOG_FILE")

    # The second call stands in for the file system event that our own write
    # raises. It must do nothing at all: no rewrite, and no log line.
    compress_png "$REPEAT_FILE"
    SECOND_SUM=$(shasum "$REPEAT_FILE" | awk '{print $1}')
    LOG_LINES_AFTER=$(wc -l < "$LOG_FILE")

    if [ "$FIRST_SUM" != "$SECOND_SUM" ]; then
        echo -e "${RED}✗ Second compression rewrote the file${NC}"
        echo "  The service would recompress its own output on every event."
        exit 1
    fi
    if [ "$LOG_LINES_BEFORE" -ne "$LOG_LINES_AFTER" ]; then
        echo -e "${RED}✗ Second compression was not skipped silently${NC}"
        echo "  pngquant ran again on a file this tool had already compressed."
        exit 1
    fi
    echo -e "${GREEN}✓ Already-compressed screenshot left untouched${NC}"
fi

# Test 10: Detecting a watch folder that cannot be listed
echo
echo "Test 10: Testing detection of an unreadable watch folder..."

if ! check_watch_dir_readable; then
    echo -e "${RED}✗ The readable test directory was reported as unreadable${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Readable folder accepted${NC}"

if [ "$(id -u)" -eq 0 ]; then
    # root ignores directory permissions, so the negative case cannot be staged
    echo -e "${YELLOW}⚠ Skipped unreadable-folder check: running as root${NC}"
else
    UNREADABLE_DIR="$TEST_DIR/unreadable"
    mkdir -p "$UNREADABLE_DIR"
    chmod 000 "$UNREADABLE_DIR"

    # Capture the result before restoring permissions, so an unreadable directory
    # can never be left behind for the cleanup trap to trip over
    WATCH_DIR="$UNREADABLE_DIR"
    UNREADABLE_DETECTED=0
    check_watch_dir_readable || UNREADABLE_DETECTED=1
    WATCH_DIR="$TEST_DIR"
    chmod 755 "$UNREADABLE_DIR"

    if [ "$UNREADABLE_DETECTED" -eq 1 ]; then
        echo -e "${GREEN}✓ Unreadable folder correctly reported${NC}"
    else
        echo -e "${RED}✗ Unreadable folder was reported as readable${NC}"
        echo "  macOS blocking the folder would look like 'no screenshots yet'."
        exit 1
    fi
fi

# Test 11: Resolving the screenshot folder from the macOS setting
echo
echo "Test 11: Testing screenshot location resolution..."

# This is what a Homebrew install relies on: the formula cannot ask where to
# watch, so the service has to work the folder out for itself at startup.
#
# `defaults` is stubbed rather than run for real - a test must not depend on,
# nor change, the screenshot location configured on the machine running it.
# A shell function takes precedence over the external command of the same name.
STUB_LOCATION=""
STUB_LOCATION_IS_SET=1
defaults() {
    [ "$STUB_LOCATION_IS_SET" -eq 1 ] || return 1
    printf '%s\n' "$STUB_LOCATION"
}

expect_resolved() {
    local description="$1" expected="$2" actual
    actual=$(resolve_screenshot_dir)
    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✓ $description${NC}"
    else
        echo -e "${RED}✗ $description: expected '$expected', got '$actual'${NC}"
        exit 1
    fi
}

STUB_LOCATION="$TEST_DIR/Shots"
expect_resolved "Configured location is used" "$TEST_DIR/Shots"

STUB_LOCATION="$TEST_DIR/Shots/"
expect_resolved "Trailing slash is dropped" "$TEST_DIR/Shots"

# `defaults write ... location "~/Shots"` stores the tilde literally, and a path
# starting with one is not a path fswatch can watch. The tilde is assembled from
# a variable because it has to stay unexpanded here, and a quoted tilde written
# inline is the very thing linters flag as a mistake.
LITERAL_TILDE='~'
STUB_LOCATION="${LITERAL_TILDE}/Shots"
expect_resolved "Leading ~ is expanded" "${HOME}/Shots"

STUB_LOCATION_IS_SET=0
expect_resolved "Unset location falls back to the Desktop" "${HOME}/Desktop"

unset -f defaults

# Test 12: Recognising both kinds of installation
echo
echo "Test 12: Testing install detection in status.sh..."

STATUS_SCRIPT="$(dirname "$SCRIPT_UNDER_TEST")/status.sh"
FAKE_HOME="$TEST_DIR/status-home"
FAKE_LAUNCHAGENTS="$FAKE_HOME/Library/LaunchAgents"
mkdir -p "$FAKE_LAUNCHAGENTS"

BREW_PLIST="$FAKE_LAUNCHAGENTS/homebrew.mxcl.macos-compress-screenshots.plist"
MANUAL_PLIST="$FAKE_LAUNCHAGENTS/com.macos.compress-screenshots.plist"

# A fake HOME shows status.sh only the LaunchAgents this test puts there, so
# whatever is really installed on this machine is left alone. status.sh exits
# non-zero for any service that is not healthy - the normal case here - so its
# output is what is checked, not its exit status.
#
# The report is matched with a case pattern rather than piped to grep because
# sourcing compress-screenshots.sh turned on `pipefail` here: in a pipeline,
# status.sh's non-zero exit would mask grep's answer entirely.
expect_status_report() {
    local description="$1" expected="$2" report
    report=$(HOME="$FAKE_HOME" /bin/bash "$STATUS_SCRIPT" 2>&1 || true)
    case "$report" in
        *"$expected"*)
            echo -e "${GREEN}✓ $description${NC}"
            ;;
        *)
            echo -e "${RED}✗ $description: no '$expected' in the report${NC}"
            exit 1
            ;;
    esac
}

expect_status_report "No LaunchAgent reads as not installed" "Service not installed"

touch "$BREW_PLIST"
expect_status_report "Homebrew installation is recognised" "(via Homebrew)"

rm "$BREW_PLIST"
touch "$MANUAL_PLIST"
expect_status_report "install.sh installation is recognised" "(via install.sh)"

# Both at once is the case worth warning about: they compress the same folder
# twice over, and removing one leaves the other running
touch "$BREW_PLIST"
expect_status_report "Two installations at once are reported" "A second installation is also present"

echo
echo "======================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "======================================"
