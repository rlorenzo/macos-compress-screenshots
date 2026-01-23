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
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $*" >> "$LOG_FILE"
    
    # Rotate log if it gets too large
    local log_size
    if [ -f "$LOG_FILE" ]; then
        log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            echo "[$timestamp] Log rotated" >> "$LOG_FILE"
        fi
    fi
}

# Function to check if file is a screenshot
is_screenshot() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    # macOS screenshots match these patterns:
    # - "Screen Shot" (two words): Used in macOS Mojave (10.14) and earlier
    # - "Screenshot" (one word): Used in macOS Catalina (10.15) and later
    # Both patterns are supported for backward compatibility with older screenshots
    #
    # Pattern format: [Prefix] YYYY-MM-DD at H.MM.SS AM/PM.png
    # - Prefix: "Screen Shot" or "Screenshot"
    # - Date: YYYY-MM-DD format
    # - Time: H.MM.SS format (hour can be 1 or 2 digits, minutes and seconds are always 2 digits)
    # - AM/PM indicator
    # - Extension: .png
    #
    # Examples:
    # - Screen Shot 2024-01-23 at 10.30.45 AM.png (older macOS versions)
    # - Screenshot 2024-01-23 at 2.11.11 PM.png (macOS Catalina and later)
    local pattern='^(Screen Shot|Screenshot) [0-9]{4}-[0-9]{2}-[0-9]{2} at [0-9]{1,2}\.[0-9]{2}\.[0-9]{2} (AM|PM)\.png$'
    
    if [[ "$filename" =~ $pattern ]]; then
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
    
    # Get original size with error handling
    local original_size
    if ! original_size=$(stat -f%z "$file" 2>/dev/null); then
        log "Error: Unable to get file size for $(basename "$file")"
        return
    fi
    
    # Use pngquant for high-quality lossy compression
    # --quality 65-80: Sets an acceptable quality range (min 65, max 80); pngquant tries to use the highest quality within this range while achieving good compression
    # --skip-if-larger: Don't save if the result is larger than the original
    # --force: Overwrite existing file
    # --ext .png: Use .png extension (instead of default -fs8.png)
    if pngquant --quality=65-80 --skip-if-larger --force --ext .png "$file" >/dev/null 2>&1; then
        local new_size
        if ! new_size=$(stat -f%z "$file" 2>/dev/null); then
            log "Compressed: $(basename "$file") - Original: ${original_size} bytes (new size unavailable)"
            return
        fi
        local saved=$((original_size - new_size))
        local percent=0
        if [ "$original_size" -gt 0 ]; then
            percent=$((saved * 100 / original_size))
        fi
        
        log "Compressed: $(basename "$file") - Original: ${original_size} bytes, New: ${new_size} bytes, Saved: ${saved} bytes (${percent}%)"
    else
        # pngquant returns non-zero if file was skipped (already optimal or would be larger)
        log "Skipped: $(basename "$file") - Already optimized or would not benefit from compression"
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
    
    # Check if required tools are available
    if ! command -v fswatch >/dev/null 2>&1; then
        log "Error: fswatch is not installed. Please install it with: brew install fswatch"
        exit 1
    fi
    
    if ! command -v pngquant >/dev/null 2>&1; then
        log "Error: pngquant is not installed. Please install it with: brew install pngquant"
        exit 1
    fi
    
    # Monitor the Desktop directory for new PNG files
    # fswatch flags:
    #   -0: Use NUL character as line separator for safe file path handling
    #   -e ".*": Exclude all files by default
    #   -i "\\.png$": Include only files ending with .png
    #   --event Created: Only monitor file creation events
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
