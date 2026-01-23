# macOS Screenshot Compression Tool

Automatically compresses PNG screenshots saved to your Desktop by the macOS screenshot tool, reducing file size while maintaining quality.

## Features

- 🚀 **Automatic**: Monitors your Desktop and compresses screenshots as they're created
- 🎯 **Smart Detection**: Only processes files matching macOS screenshot naming patterns
- 💾 **Space Saving**: Reduces file sizes using pngquant compression
- 📊 **Logging**: Tracks all compression operations with detailed statistics
- 🔄 **Background Service**: Runs automatically in the background via LaunchAgent
- ⚙️ **Easy Setup**: Simple installation and uninstallation scripts

> 💡 **New to this tool?** Check out [EXAMPLES.md](EXAMPLES.md) for a quick start guide with usage examples!

## Prerequisites

- macOS (any recent version)
- [fswatch](https://github.com/emcrisostomo/fswatch) - File system monitoring tool
- [pngquant](https://pngquant.org/) - High-quality PNG compression tool

### Installing Dependencies

```bash
# Using Homebrew
brew install fswatch pngquant
```

## Installation

1. Clone or download this repository:
```bash
git clone https://github.com/rlorenzo/macos-compress-screenshots.git
cd macos-compress-screenshots
```

2. Run the installation script:
```bash
./install.sh
```

The installation script will:
- Copy the compression script to `~/.macos-compress-screenshots/`
- Install a LaunchAgent to run the service automatically
- Start the service immediately
- Configure it to start automatically on login

## How It Works

1. The service monitors your Desktop folder for new PNG files
2. When a new screenshot is detected (matching patterns like "Screenshot YYYY-MM-DD at H.MM.SS PM.png" for modern macOS, or "Screen Shot YYYY-MM-DD at H.MM.SS PM.png" for older versions), it:
   - Uses `pngquant` to compress the PNG with high-quality lossy compression
   - Maintains excellent visual quality while significantly reducing file size
   - Skips files that are already optimized or wouldn't benefit from compression
   - Logs the operation with compression statistics

**Note:** macOS changed screenshot naming from "Screen Shot" (two words) in Mojave and earlier to "Screenshot" (one word) starting with Catalina. This tool supports both formats for backward compatibility.

## Usage

Once installed, the service runs automatically in the background. Just take screenshots as normal (⌘⇧3, ⌘⇧4, ⌘⇧5), and they'll be compressed automatically!

### Checking Service Status

```bash
./status.sh
```

This will show:
- Whether the service is installed and running
- Process ID (PID)
- fswatch installation status
- Recent compression activity
- Useful commands

### Viewing Logs

Check compression activity and statistics:
```bash
tail -f ~/Library/Logs/compress-screenshots.log
```

### Stopping the Service

```bash
launchctl unload ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
```

### Starting the Service

```bash
launchctl load ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
```

## Uninstallation

To completely remove the service:

```bash
./uninstall.sh
```

This will:
- Stop the background service
- Remove all installed files
- Optionally remove log files

## Configuration

The main script (`compress-screenshots.sh`) can be customized by editing these variables:

```bash
WATCH_DIR="${HOME}/Desktop"  # Directory to monitor
LOG_FILE="${HOME}/Library/Logs/compress-screenshots.log"  # Log file location
MAX_LOG_SIZE=1048576  # Maximum log file size (1MB) before rotation
```

After making changes, restart the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
launchctl load ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
```

## Compression Details

The tool uses [pngquant](https://pngquant.org/), a high-quality PNG compression tool that:
- Applies lossy compression while maintaining excellent visual quality
- Uses smart quantization to reduce the color palette
- Can achieve 50-80% file size reduction with minimal perceptible quality loss
- Skips files that are already well-optimized or where compression would increase size
- Is specifically optimized for screenshots and digital artwork

The compression uses these settings:
- Quality range: 65-80 (balances size reduction with visual quality)
- Skip if larger: Prevents saving if compression would increase file size
- Overwrites original file to save disk space

Typical compression results:
- Screenshots with lots of text: 50-80% size reduction
- Screenshots with images: 40-70% size reduction
- Already optimized images: Skipped (no changes)

## Troubleshooting

### Service not starting

Check the error log:
```bash
cat ~/Library/Logs/compress-screenshots.error.log
```

### fswatch not found

Make sure fswatch is installed and in your PATH:
```bash
which fswatch
# If not found, install it:
brew install fswatch
```

### pngquant not found

Make sure pngquant is installed and in your PATH:
```bash
which pngquant
# If not found, install it:
brew install pngquant
```

### Screenshots not being compressed

1. Verify the service is running:
```bash
launchctl list | grep compress-screenshots
```

2. Check the log file for errors:
```bash
tail -n 50 ~/Library/Logs/compress-screenshots.log
```

3. Ensure your screenshots match the expected naming pattern:
   - Modern macOS (Catalina 10.15+): `Screenshot YYYY-MM-DD at H.MM.SS PM.png`
   - Older macOS (Mojave 10.14 and earlier): `Screen Shot YYYY-MM-DD at H.MM.SS PM.png`
   - Hour can be 1 or 2 digits (e.g., `2` or `10`)
   - Examples: 
     - `Screenshot 2024-01-23 at 2.11.11 PM.png` (modern macOS)
     - `Screen Shot 2024-12-25 at 10.30.45 AM.png` (older macOS)

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
