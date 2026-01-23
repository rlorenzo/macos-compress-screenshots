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

# Test 1: Check if sips command is available
echo "Test 1: Checking for sips command..."
if command -v sips >/dev/null 2>&1; then
    echo -e "${GREEN}✓ sips is available${NC}"
else
    echo -e "${RED}✗ sips is not available${NC}"
    exit 1
fi

# Test 2: Create a test PNG file
echo
echo "Test 2: Creating test PNG file..."
# Create a simple PNG using sips (generate from a single pixel)
TEST_FILE="$TEST_DIR/Screen Shot 2024-01-23 at 10.30.45 AM.png"
# Create a 100x100 white PNG
sips -z 100 100 -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns --out "$TEST_FILE" >/dev/null 2>&1

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
source compress-screenshots.sh

if is_screenshot "$TEST_FILE"; then
    echo -e "${GREEN}✓ Screenshot pattern matching works${NC}"
else
    echo -e "${RED}✗ Screenshot pattern matching failed${NC}"
    exit 1
fi

# Test 4: Test compression
echo
echo "Test 4: Testing PNG compression..."
ORIGINAL_SIZE=$(stat -f%z "$TEST_FILE")
echo "Original size: $ORIGINAL_SIZE bytes"

if sips -s format png -s formatOptions high "$TEST_FILE" --out "$TEST_FILE" >/dev/null 2>&1; then
    NEW_SIZE=$(stat -f%z "$TEST_FILE")
    echo "Compressed size: $NEW_SIZE bytes"
    
    if [ -f "$TEST_FILE" ]; then
        echo -e "${GREEN}✓ Compression successful${NC}"
        
        SAVED=$((ORIGINAL_SIZE - NEW_SIZE))
        if [ $ORIGINAL_SIZE -gt 0 ]; then
            PERCENT=$((SAVED * 100 / ORIGINAL_SIZE))
            echo "Saved: $SAVED bytes (${PERCENT}%)"
        fi
    else
        echo -e "${RED}✗ Compressed file not found${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Compression failed${NC}"
    exit 1
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
