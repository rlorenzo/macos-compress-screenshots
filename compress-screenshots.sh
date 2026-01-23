#!/bin/bash
#
# compress-screenshots.sh
# Monitors the Desktop for new PNG screenshot files and compresses them automatically
#

set -euo pipefail

# Configuration
WATCH_DIR="${HOME}/Desktop"
LOG_FILE="${HOME}/Library/Logs/compress-screenshots.log"
MAX_LOG_SIZE=1048576  # 1MB

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $*" >> "$LOG_FILE"
    
    # Rotate log if it gets too large
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "[$timestamp] Log rotated" >> "$LOG_FILE"
    fi
}

# Function to check if file is a screenshot
is_screenshot() {
    local file="$1"
    local filename=$(basename "$file")
    
    # macOS screenshots typically match these patterns:
    # - Screen Shot YYYY-MM-DD at HH.MM.SS AM/PM.png
    # - Screenshot YYYY-MM-DD at HH.MM.SS AM/PM.png
    if [[ "$filename" =~ ^(Screen\ Shot|Screenshot)\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ at\ [0-9]{1,2}\.[0-9]{2}\.[0-9]{2}\ (AM|PM)\.png$ ]]; then
        return 0
    fi
    return 1
}

# Function to compress a PNG file
compress_png() {
    local file="$1"
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        return
    fi
    
    # Get original size
    local original_size=$(stat -f%z "$file")
    
    # Use sips (built-in macOS tool) to compress
    # This maintains quality while reducing file size
    if sips -s format png -s formatOptions high "$file" --out "$file" >/dev/null 2>&1; then
        local new_size=$(stat -f%z "$file")
        local saved=$((original_size - new_size))
        local percent=0
        if [ $original_size -gt 0 ]; then
            percent=$((saved * 100 / original_size))
        fi
        
        log "Compressed: $(basename "$file") - Original: ${original_size} bytes, New: ${new_size} bytes, Saved: ${saved} bytes (${percent}%)"
    else
        log "Error: Failed to compress $(basename "$file")"
    fi
}

# Function to process existing screenshots on startup
process_existing() {
    log "Processing existing screenshots in $WATCH_DIR"
    local count=0
    
    while IFS= read -r -d '' file; do
        if is_screenshot "$file"; then
            compress_png "$file"
            ((count++))
        fi
    done < <(find "$WATCH_DIR" -maxdepth 1 -type f -name "*.png" -print0 2>/dev/null)
    
    log "Processed $count existing screenshot(s)"
}

# Function to monitor directory for new screenshots
monitor_directory() {
    log "Starting to monitor $WATCH_DIR for new screenshots"
    
    # Check if fswatch is available
    if ! command -v fswatch >/dev/null 2>&1; then
        log "Error: fswatch is not installed. Please install it with: brew install fswatch"
        exit 1
    fi
    
    # Monitor the Desktop directory for new PNG files
    fswatch -0 -e ".*" -i "\\.png$" --event Created "$WATCH_DIR" | while IFS= read -r -d '' file
    do
        # Wait a moment to ensure file is fully written
        sleep 0.5
        
        if [ -f "$file" ] && is_screenshot "$file"; then
            log "Detected new screenshot: $(basename "$file")"
            compress_png "$file"
        fi
    done
}

# Main execution
main() {
    log "===== compress-screenshots started ====="
    
    # Check if watch directory exists
    if [ ! -d "$WATCH_DIR" ]; then
        log "Error: Watch directory does not exist: $WATCH_DIR"
        exit 1
    fi
    
    # Process existing screenshots
    process_existing
    
    # Start monitoring for new screenshots
    monitor_directory
}

# Run main function
main
