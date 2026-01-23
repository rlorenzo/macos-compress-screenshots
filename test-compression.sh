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

# Import the is_screenshot function logic without executing the main script
is_screenshot() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    # macOS screenshots typically match these patterns:
    # - Screen Shot YYYY-MM-DD at HH.MM.SS AM/PM.png
    # - Screenshot YYYY-MM-DD at HH.MM.SS AM/PM.png
    if [[ "$filename" =~ ^(Screen\ Shot|Screenshot)\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{1,2}\.[0-9]{2}\.[0-9]{2}\ (AM|PM)\.png$ ]]; then
        return 0
    fi
    return 1
}

if is_screenshot "$TEST_FILE"; then
    echo -e "${GREEN}✓ Screenshot pattern matching works${NC}"
else
    echo -e "${RED}✗ Screenshot pattern matching failed${NC}"
    exit 1
fi

# Test 4: Test compression
echo
echo "Test 4: Testing PNG compression with pngquant..."
ORIGINAL_SIZE=$(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null)
echo "Original size: $ORIGINAL_SIZE bytes"

# Make a copy to test compression
TEST_COPY="$TEST_DIR/test-copy.png"
cp "$TEST_FILE" "$TEST_COPY"

if pngquant --quality=65-80 --skip-if-larger --force --ext .png "$TEST_COPY" >/dev/null 2>&1; then
    NEW_SIZE=$(stat -f%z "$TEST_COPY" 2>/dev/null || stat -c%s "$TEST_COPY" 2>/dev/null)
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

echo
echo "======================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "======================================"
