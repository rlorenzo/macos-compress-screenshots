# macOS Screenshot Compression Tool

Automatically compresses PNG screenshots saved to your Desktop by the macOS screenshot tool, reducing file size while maintaining quality.

## Features

- 🚀 **Automatic**: Monitors your Desktop and compresses screenshots as they're created
- 🎯 **Smart Detection**: Only processes files matching macOS screenshot naming patterns
- 💾 **Space Saving**: Reduces file sizes using built-in macOS compression
- 📊 **Logging**: Tracks all compression operations with detailed statistics
- 🔄 **Background Service**: Runs automatically in the background via LaunchAgent
- ⚙️ **Easy Setup**: Simple installation and uninstallation scripts

> 💡 **New to this tool?** Check out [EXAMPLES.md](EXAMPLES.md) for a quick start guide with usage examples!

## Prerequisites

- macOS (any recent version)
- [fswatch](https://github.com/emcrisostomo/fswatch) - File system monitoring tool

### Installing fswatch

```bash
# Using Homebrew
brew install fswatch
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
2. When a new screenshot is detected (matching patterns like "Screen Shot YYYY-MM-DD at HH.MM.SS AM/PM.png"), it:
   - Uses the built-in `sips` command to compress the PNG
   - Maintains image quality while reducing file size
   - Logs the operation with compression statistics

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

The tool uses macOS's built-in `sips` (Scriptable Image Processing System) command to compress PNG files. This approach:
- Maintains high image quality
- Reduces file size through optimized compression
- Works without requiring any third-party tools (besides fswatch for monitoring)
- Is safe and reliable

Typical compression results:
- Screenshots with lots of text: 30-50% size reduction
- Screenshots with images: 10-30% size reduction
- Already optimized images: minimal to no reduction

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
   - "Screen Shot YYYY-MM-DD at HH.MM.SS AM/PM.png"
   - "Screenshot YYYY-MM-DD at HH.MM.SS AM/PM.png"

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
