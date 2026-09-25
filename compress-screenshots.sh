#!/bin/bash
#
# compress-screenshots.sh
# Monitors a folder for new PNG screenshot files and compresses them automatically
#

set -euo pipefail

# Configuration
# WATCH_DIR and LOG_FILE may be overridden from the environment (e.g. via the
# LaunchAgent's EnvironmentVariables) so screenshots can be watched outside a
# macOS-protected folder without editing this file, and so the test suite can
# redirect the log. See README.md ("Folder access on macOS").

# Work out where macOS is currently configured to save screenshots.
#
# Resolving this at startup rather than baking it in at install time is what
# lets the Homebrew formula work: a formula cannot ask the user anything, so it
# has no opportunity to write the folder into the service definition. Reading
# the setting here means the service follows the ⌘⇧5 "Save to" location on its
# own, and a restart is all it takes to pick up a change.
#
# install.sh still pins WATCH_DIR in the LaunchAgent it writes, and that value
# wins over this - it has already asked the user where to watch, so its answer
# is more specific than the setting. It reads the same setting the same way to
# decide what to ask about, so the two resolutions have to stay in step.
resolve_screenshot_dir() {
    local dir
    dir=$(defaults read com.apple.screencapture location 2>/dev/null || true)
    if [ -z "$dir" ]; then
        # No override set, so macOS is using its default
        dir="${HOME}/Desktop"
    fi
    dir="${dir/#\~/$HOME}"   # expand a leading ~
    printf '%s' "${dir%/}"   # drop any trailing slash
}

WATCH_DIR="${WATCH_DIR:-$(resolve_screenshot_dir)}"
LOG_FILE="${LOG_FILE:-${HOME}/Library/Logs/compress-screenshots.log}"
MAX_LOG_SIZE=1048576  # 1MB

# How long to pause before exiting on a fatal configuration error. The LaunchAgent
# has KeepAlive set, so it restarts this script forever; without a pause a
# misconfiguration floods the log with the same error every ~10 seconds.
FATAL_RETRY_DELAY="${FATAL_RETRY_DELAY:-300}"

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

# Function to report an unrecoverable configuration error and stop
#
# Pauses before exiting so the LaunchAgent's KeepAlive restart loop cannot spin
# on the same error several times a minute.
fatal() {
    log "$@"
    log "Pausing ${FATAL_RETRY_DELAY}s before exit to avoid a rapid restart loop."
    sleep "$FATAL_RETRY_DELAY"
    exit 1
}

# Function to verify the watch directory can actually be listed
#
# macOS protects ~/Desktop, ~/Documents and ~/Downloads with TCC. A LaunchAgent
# running /bin/bash gets no access to them by default, and the failure is quiet:
# the directory can still be stat'd, so [ -d ] succeeds, but listing it fails
# with "Operation not permitted". Without this check that is indistinguishable
# from "there are no screenshots yet".
check_watch_dir_readable() {
    local error_output
    if error_output=$(ls -- "$WATCH_DIR" 2>&1 >/dev/null); then
        return 0
    fi

    log "Error: Cannot read $WATCH_DIR"
    log "  ${error_output}"
    log "  macOS is blocking this service's access to that folder."
    log "  Recommended fix: save screenshots to a folder macOS does not protect:"
    log "    mkdir -p ~/Screenshots"
    log "    defaults write com.apple.screencapture location ~/Screenshots"
    log "    killall SystemUIServer"
    log "    ...then point WATCH_DIR at the same folder and restart the service."
    log "  (Full Disk Access for /bin/bash is not offered as an alternative: TCC"
    log "  grants are per-executable, so it would open every bash script on this"
    log "  machine, not just this one.)"
    log "  See README.md (\"Folder access on macOS\") for details."
    return 1
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
    # - Space before AM/PM: Can be regular space (0x20) or narrow no-break space (U+202F)
    #   macOS uses U+202F (narrow no-break space) between time and AM/PM
    # - AM/PM indicator
    # - Extension: .png
    #
    # Examples:
    # - Screen Shot 2024-01-23 at 10.30.45 AM.png (older macOS versions)
    # - Screenshot 2024-01-23 at 2.11.11 PM.png (macOS Catalina and later)
    #
    # Note: Match only regular space (0x20) or narrow no-break space (U+202F)
    # that macOS uses between the time and the AM/PM indicator
    #
    # The two spaces are matched with an alternation group, NOT a bracket
    # expression. A bracket expression containing a multi-byte character only
    # works under a UTF-8 locale: in the C locale it is read as three separate
    # bytes and never matches. launchd starts services with no locale set, so a
    # bracket expression here silently rejects every real screenshot when the
    # tool runs as a background service. The alternation form is locale-independent.
    local space_char
    space_char="$(printf '\342\200\257')"  # U+202F narrow no-break space
    local pattern="^(Screen Shot|Screenshot) [0-9]{4}-[0-9]{2}-[0-9]{2} at [0-9]{1,2}\.[0-9]{2}\.[0-9]{2}( |${space_char})(AM|PM)\.png$"
    
    if [[ "$filename" =~ $pattern ]]; then
        return 0
    fi
    return 1
}

# Function to check whether a PNG is already in pngquant's palette form
#
# Compressing a file rewrites it, and that write is itself a file system event,
# so the compressed result comes straight back round to be processed again.
# pngquant always writes indexed/palette PNGs (colour type 3) while macOS
# screenshots are RGBA (colour type 6), so the colour type tells our own output
# apart from a genuinely new screenshot.
#
# The colour type lives in the PNG header at a fixed offset:
#   8-byte signature, 4-byte chunk length, 4-byte "IHDR", width(4), height(4),
#   bit depth(1), colour type(1)  ->  byte 25 (zero-indexed)
is_palette_png() {
    local file="$1"

    # Confirm this really is a PNG header before trusting a fixed offset into it
    local ihdr
    ihdr=$(dd if="$file" bs=1 skip=12 count=4 2>/dev/null || true)
    if [ "$ihdr" != "IHDR" ]; then
        return 1
    fi

    local color_type
    color_type=$(od -An -tu1 -j 25 -N 1 "$file" 2>/dev/null | tr -d ' ')
    [ "$color_type" = "3" ]
}

# Function to compress a PNG file
compress_png() {
    local file="$1"
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        return
    fi

    # Already compressed by this tool - nothing to do. This is also what stops
    # the compression write from being picked up as a new event and processed
    # again, so it must stay ahead of every other check. Staying silent keeps
    # the log free of a line for every file on every pass.
    if is_palette_png "$file"; then
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

    # Report rather than discard whatever find has to say. main() has already
    # confirmed the folder can be listed, so an error here should be rare - but
    # discarding this stream is exactly what once made an unreadable folder look
    # identical to an empty one, and a rare error reported beats a rare error lost.
    local find_errors
    find_errors=$(mktemp)

    while IFS= read -r -d '' file; do
        if is_screenshot "$file"; then
            compress_png "$file"
            count=$((count + 1))
        fi
    done < <(find "$WATCH_DIR" -maxdepth 1 -type f -name "*.png" -print0 2>"$find_errors")

    if [ -s "$find_errors" ]; then
        while IFS= read -r error_line; do
            log "Warning: find: $error_line"
        done < "$find_errors"
    fi
    rm -f "$find_errors"

    log "Processed $count existing screenshot(s)"
}

# Function to monitor directory for new screenshots
monitor_directory() {
    log "Starting to monitor $WATCH_DIR for new screenshots"
    
    # Check if required tools are available
    if ! command -v fswatch >/dev/null 2>&1; then
        fatal "Error: fswatch is not installed. Please install it with: brew install fswatch"
    fi

    if ! command -v pngquant >/dev/null 2>&1; then
        fatal "Error: pngquant is not installed. Please install it with: brew install pngquant"
    fi
    
    # Monitor the watched directory for new PNG files
    # fswatch flags:
    #   -0: Use NUL character as line separator for safe file path handling
    #   -e ".*": Exclude all files by default
    #   -i "\\.png$": Include only files ending with .png
    #   --event Created --event Renamed: Monitor both creation and rename events
    #     (macOS screenshots use atomic writes: temp file -> rename, which triggers Renamed not Created)
    #
    # No fswatch flag disables recursion here: this platform's default monitor,
    # fsevents_monitor, recurses into subdirectories unconditionally regardless of
    # -r (verified against fswatch 1.22.0), and the non-recursive kqueue_monitor
    # alternative (-m kqueue_monitor) does not reliably deliver Created/Renamed
    # events for files at all. So process_existing's -maxdepth 1 pass and this
    # loop are kept in agreement with an explicit depth check below instead:
    # anything not a direct child of WATCH_DIR is ignored, so moving or renaming
    # a file into a subfolder (e.g. an archive folder under WATCH_DIR) does not
    # trigger a lossy in-place recompression.
    fswatch -0 -e ".*" -i "\\.png$" --event Created --event Renamed "$WATCH_DIR" | while IFS= read -r -d '' file
    do
        # Wait a moment to ensure file is fully written
        sleep 0.5

        if [ "$(dirname "$file")" != "$WATCH_DIR" ]; then
            continue
        fi

        # compress_png ignores anything already in palette form, which is what
        # keeps the event raised by our own compression write from looping
        if [ -f "$file" ] && is_screenshot "$file"; then
            compress_png "$file"
        fi
    done
}

# Main execution
main() {
    log "===== compress-screenshots started ====="
    
    # Check if watch directory exists
    if [ ! -d "$WATCH_DIR" ]; then
        fatal "Error: Watch directory does not exist: $WATCH_DIR"
    fi

    # Resolve WATCH_DIR to its canonical path (e.g. /var/... -> /private/var/...
    # on macOS). fswatch reports canonical paths for events, so the monitor
    # loop's dirname check below would otherwise mismatch and skip everything,
    # including direct children, whenever WATCH_DIR itself sits behind a symlink.
    WATCH_DIR="$(cd "$WATCH_DIR" && pwd -P)"

    # Existing is not the same as accessible on macOS - verify we can list it
    if ! check_watch_dir_readable; then
        fatal "Error: Watch directory is not accessible: $WATCH_DIR"
    fi

    # Process existing screenshots
    process_existing
    
    # Start monitoring for new screenshots
    monitor_directory
}

# Run main function, unless this file was sourced. Sourcing lets
# test-compression.sh exercise the real functions above instead of keeping its
# own copy of them, which is the only way a test can catch a regression here.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main
fi
