# macOS Screenshot Compression Tool - Quick Start Example

## What This Tool Does

When you take a screenshot on macOS (using ⌘⇧3, ⌘⇧4, or ⌘⇧5), the system saves PNG files to your Desktop. These files are often larger than they need to be.

This tool automatically:
1. Monitors your Desktop for new screenshot files
2. Compresses them to reduce file size
3. Maintains the same image quality
4. Logs the compression results

## Example Screenshot Names

The tool automatically detects and compresses files with these naming patterns:
- `Screenshot 2024-01-23 at 2.11.11 PM.png` (macOS Catalina and later - single-digit hour)
- `Screenshot 2024-01-23 at 2.15.30 PM.png` (macOS Catalina and later - single-digit hour)
- `Screen Shot 2024-01-23 at 10.30.45 AM.png` (macOS Mojave and earlier - double-digit hour)

**Why both patterns?** macOS changed the screenshot naming from "Screen Shot" (two words) to "Screenshot" (one word) starting with macOS Catalina (10.15). This tool supports both for backward compatibility with older screenshots.

Note: The hour can be 1 or 2 digits (e.g., `2` or `10`), while minutes and seconds are always 2 digits.

Regular PNG files (like `photo.png` or `diagram.png`) are **not** compressed.

## Typical Compression Results

| Screenshot Type | Original Size | Compressed Size | Savings |
|----------------|---------------|-----------------|---------|
| Text-heavy (code, docs) | 500 KB | 100 KB | 80% |
| Mixed content | 800 KB | 240 KB | 70% |
| Photos/images | 1.2 MB | 360 KB | 70% |

*Note: pngquant provides significantly better compression than the previous sips-based approach*

## Installation Example

```bash
# 1. Clone the repository
git clone https://github.com/rlorenzo/macos-compress-screenshots.git
cd macos-compress-screenshots

# 2. Install dependencies if you don't have them
brew install fswatch pngquant

# 3. Run the installer
./install.sh

# Output:
# ======================================
# macOS Screenshot Compression Tool
# ======================================
#
# Creating installation directory...
# Installing compress-screenshots.sh...
# Installing LaunchAgent...
# Starting service...
# ✓ Installation complete!
#
# The screenshot compression service is now running in the background.
```

## Using the Tool

After installation, the tool runs automatically in the background. Just take screenshots as usual!

### Check the Status

```bash
./status.sh

# Output:
# ======================================
# Screenshot Compression Service Status
# ======================================
#
# ✓ Service is installed
#   Location: /Users/yourname/Library/LaunchAgents/com.macos.compress-screenshots.plist
#
# ✓ Service is running
#   PID: 12345
#
# ✓ fswatch is installed
#   Version: fswatch 1.17.1
#
# ✓ pngquant is installed
#   Version: 2.18.0 (March 2023)
#
# Recent Activity:
#   Log file: /Users/yourname/Library/Logs/compress-screenshots.log
#   Size: 4.2K
#
# Last 5 compression events:
#   [2024-01-23 10:30:46] Compressed: Screen Shot 2024-01-23 at 10.30.45 AM.png - Original: 524288 bytes, New: 104857 bytes, Saved: 419431 bytes (80%)
```

### View Live Compression Activity

```bash
tail -f ~/Library/Logs/compress-screenshots.log

# Output shows each compression in real-time:
# [2024-01-23 10:30:46] Detected new screenshot: Screen Shot 2024-01-23 at 10.30.45 AM.png
# [2024-01-23 10:30:46] Compressed: Screen Shot 2024-01-23 at 10.30.45 AM.png - Original: 524288 bytes, New: 104857 bytes, Saved: 419431 bytes (80%)
```

## Uninstallation Example

```bash
./uninstall.sh

# Output:
# ======================================
# Uninstall macOS Screenshot Compression Tool
# ======================================
#
# Stopping service...
# Removing LaunchAgent...
# Removing installation directory...
#
# Do you want to remove log files as well? (y/n) y
# Log files removed
#
# ✓ Uninstallation complete!
```

## Troubleshooting Example

If screenshots aren't being compressed:

```bash
# 1. Check if the service is running
./status.sh

# 2. Check for errors in the log
cat ~/Library/Logs/compress-screenshots.error.log

# 3. Restart the service
launchctl unload ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
launchctl load ~/Library/LaunchAgents/com.macos.compress-screenshots.plist

# 4. Take a test screenshot and watch the log
tail -f ~/Library/Logs/compress-screenshots.log
# (Then press ⌘⇧4 and take a screenshot)
```

## How It Works

```
┌─────────────────┐
│ Take Screenshot │ (⌘⇧3, ⌘⇧4, ⌘⇧5)
└────────┬────────┘
         │
         v
┌─────────────────┐
│ PNG saved to    │
│ Desktop         │
└────────┬────────┘
         │
         v
┌─────────────────┐
│ fswatch detects │
│ new file        │
└────────┬────────┘
         │
         v
┌─────────────────┐
│ Check if file   │
│ matches pattern │
└────────┬────────┘
         │
         v
┌─────────────────┐
│ Compress with   │
│ pngquant        │
└────────┬────────┘
         │
         v
┌─────────────────┐
│ Log results     │
│ (size saved)    │
└─────────────────┘
```
