# macOS Screenshot Compression Tool

Automatically compresses PNG screenshots saved to your Desktop by the macOS screenshot tool, reducing file size while maintaining quality.

## Features

- 🚀 **Automatic**: Monitors your Desktop and compresses screenshots as they're created
- 🎯 **Smart Detection**: Only processes files matching macOS screenshot naming patterns
- 💾 **Space Saving**: Reduces file sizes using pngquant compression
- 📊 **Logging**: Tracks all compression operations with detailed statistics
- 🔄 **Background Service**: Runs automatically in the background via LaunchAgent
- ⚙️ **Easy Setup**: Install with Homebrew, or with a self-contained install script

> 💡 **New to this tool?** Check out [EXAMPLES.md](EXAMPLES.md) for a quick start guide with usage examples!

## Prerequisites

- macOS (any recent version)
- Folder access for the background service — see [Folder access on macOS](#folder-access-on-macos). The default screenshot location (`~/Desktop`) is protected by macOS and needs one of the two fixes described there.
- [fswatch](https://github.com/emcrisostomo/fswatch) - File system monitoring tool
- [pngquant](https://pngquant.org/) - High-quality PNG compression tool

### Installing Dependencies

Both are installed for you — by Homebrew if you install the formula, or by
`install.sh` if you agree when it offers. To install them yourself:

```bash
brew install fswatch pngquant
```

## Installation

Two options. Homebrew is less work; `install.sh` is the only one that can walk
you through the [folder access](#folder-access-on-macos) problem interactively.

### With Homebrew

```bash
brew tap rlorenzo/tap https://github.com/rlorenzo/macos-compress-screenshots
brew install macos-compress-screenshots
brew services start macos-compress-screenshots
```

Homebrew installs `fswatch` and `pngquant` for you and runs the service through
its own LaunchAgent. The service reads your current screenshot location at
startup, so it watches the right folder without being told — but if that folder
is one macOS protects, it still cannot read it. See
[Folder access on macOS](#folder-access-on-macos), which the formula also
summarises after installing.

Two commands cover day-to-day use:

```bash
compress-screenshots-status                       # health check
brew services restart macos-compress-screenshots  # after changing settings
```

Maintaining the formula is documented separately in [HOMEBREW.md](HOMEBREW.md).

### With install.sh

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
- Check for `fswatch` and `pngquant`, and offer to install any that are missing
- Detect where macOS currently saves screenshots and watch that folder
- Offer to move the screenshot location if it is one macOS blocks access to
- Copy the compression script to `~/.macos-compress-screenshots/`
- Install a LaunchAgent to run the service automatically
- Start the service immediately
- Configure it to start automatically on login

Both dependencies are required. If they are missing and you decline to install
them, installation stops rather than leaving behind a service that cannot run.

If your screenshots are saved somewhere macOS protects (`~/Desktop` by default),
the installer explains the problem and offers a choice:

```
Screenshots are currently saved to: /Users/you/Desktop

macOS protects that folder, and this service cannot read it.

  1) Save screenshots to /Users/you/Screenshots instead (recommended, no extra permissions)
  2) Keep /Users/you/Desktop and grant Full Disk Access to /bin/bash yourself
  3) Cancel

Choice [1]:
```

Option 1 changes your screenshot location for you; nothing is changed without
you choosing it. When run non-interactively the installer never changes the
setting, and tells you what to do instead. If your screenshots already go
somewhere unprotected, no prompt appears at all and that folder is simply used.

## Folder access on macOS

**This is the most common reason the service appears to run but never compresses
anything.** macOS protects three folders with TCC (Transparency, Consent and
Control):

- `~/Desktop`
- `~/Documents`
- `~/Downloads`

A LaunchAgent runs as `/bin/bash` and has no access to them by default. The
failure is silent by nature: the folder can still be checked for existence, but
listing it fails with `Operation not permitted`, which looks exactly like "there
are no screenshots yet". The service logs a clear error when this happens, and
`./status.sh` reports it.

Since macOS saves screenshots to the Desktop by default, a stock setup hits this.
There are two ways to resolve it.

### Option 1: save screenshots outside a protected folder (recommended)

No special permissions are needed, because only the three folders above are
protected. Point macOS at a folder such as `~/Screenshots`:

```bash
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
killall SystemUIServer
```

Then restart the service so it picks up the new location:

```bash
# Homebrew
brew services restart macos-compress-screenshots

# install.sh
launchctl unload ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
launchctl load ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
```

The service reads the screenshot location at startup, so a restart is all it
takes. A Homebrew install needs nothing further. An `install.sh` install also
pins `WATCH_DIR` in its LaunchAgent, and that pinned value wins — so either
re-run `./install.sh`, or update `WATCH_DIR` by hand (see
[Configuration](#configuration)).

`~/Pictures` and any folder you create at the top level of your home directory
work equally well.

#### Changing the screenshot location back

To return macOS to its default (the Desktop), remove the setting:

```bash
defaults delete com.apple.screencapture location
killall SystemUIServer
```

Or point it at any folder explicitly:

```bash
defaults write com.apple.screencapture location ~/Desktop
killall SystemUIServer
```

To check where screenshots are currently saved:

```bash
defaults read com.apple.screencapture location
```

If that reports `does not exist`, no override is set and macOS is using the
Desktop. Remember that reverting to the Desktop reintroduces the access problem
above, so use Option 2 if you go back.

The same settings are available without the terminal: press **⌘⇧5**, then choose
**Options → Save to**. That menu lists Desktop, Documents, Clipboard and
**Other Location…** for anything else.

### Option 2: grant Full Disk Access

To keep screenshots on the Desktop, grant Full Disk Access to `/bin/bash`:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click **+**, press **⌘⇧G**, and enter `/bin/bash`
3. Restart the service with the commands above

This applies to both install methods: a `brew services` agent is subject to
exactly the same restrictions as a hand-installed one.

Be aware of the tradeoff: this grants full disk access to *every* bash script you
run, not just this one. Option 1 is preferable for that reason.

## How It Works

1. The service monitors your screenshot folder (`~/Desktop` unless you have changed it) for new PNG files
2. When a new screenshot is detected (matching patterns like "Screenshot YYYY-MM-DD at H.MM.SS PM.png" for modern macOS, or "Screen Shot YYYY-MM-DD at H.MM.SS PM.png" for older versions), it:
   - Uses `pngquant` to compress the PNG with high-quality lossy compression
   - Maintains excellent visual quality while significantly reducing file size
   - Skips files that are already optimized or wouldn't benefit from compression
   - Skips files it has already compressed, so its own output is not reprocessed
   - Logs the operation with compression statistics

**Note:** macOS changed screenshot naming from "Screen Shot" (two words) in Mojave and earlier to "Screenshot" (one word) starting with Catalina. This tool supports both formats for backward compatibility.

## Usage

Once installed, the service runs automatically in the background. Just take screenshots as normal (⌘⇧3, ⌘⇧4, ⌘⇧5), and they'll be compressed automatically!

### Checking Service Status

```bash
compress-screenshots-status   # Homebrew
./status.sh                   # install.sh
```

Both are the same script, and it recognises either installation. This will show:
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

### Stopping and Starting the Service

With Homebrew:

```bash
brew services stop macos-compress-screenshots
brew services start macos-compress-screenshots
```

With `install.sh`:

```bash
launchctl unload ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
launchctl load ~/Library/LaunchAgents/com.macos.compress-screenshots.plist
```

## Uninstallation

With Homebrew:

```bash
brew services stop macos-compress-screenshots
brew uninstall macos-compress-screenshots
```

With `install.sh`:

```bash
./uninstall.sh
```

This will:
- Stop the background service
- Remove all installed files
- Optionally remove log files

Each removes only its own installation. If you have used both, remove both —
`./status.sh` warns when two are present, since they compete over the same
folder.

## Configuration

The main script (`compress-screenshots.sh`) can be customized by editing these variables:

```bash
WATCH_DIR="${WATCH_DIR:-$(resolve_screenshot_dir)}"  # Directory to monitor
LOG_FILE="${LOG_FILE:-${HOME}/Library/Logs/compress-screenshots.log}"  # Log file location
MAX_LOG_SIZE=1048576  # Maximum log file size (1MB) before rotation
FATAL_RETRY_DELAY="${FATAL_RETRY_DELAY:-300}"  # Pause before exiting on a fatal error, to avoid a restart loop
```

`WATCH_DIR`, `LOG_FILE` and `FATAL_RETRY_DELAY` take their value from the
environment when one is set, so they can be changed from the LaunchAgent's
`EnvironmentVariables` without editing the script.

With no `WATCH_DIR` set, the service asks macOS where screenshots are currently
saved (`defaults read com.apple.screencapture location`, falling back to
`~/Desktop`) each time it starts. A Homebrew install relies on this and needs no
configuration.

### Changing the watched folder

Change where macOS saves screenshots and restart the service. That is the whole
procedure for a Homebrew install:

```bash
defaults write com.apple.screencapture location ~/Screenshots
killall SystemUIServer
brew services restart macos-compress-screenshots
```

`install.sh` additionally pins `WATCH_DIR` in the LaunchAgent it writes, and a
pinned value takes precedence over the detected one — so with that install
method, re-run `./install.sh` afterwards.

To point that installation somewhere else by hand instead, edit the
`EnvironmentVariables` dict in
`~/Library/LaunchAgents/com.macos.compress-screenshots.plist`:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    <key>WATCH_DIR</key>
    <string>/Users/YOUR_USERNAME/Screenshots</string>
</dict>
```

Use a full path — `~` is not expanded here.

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
# install.sh
cat ~/Library/Logs/compress-screenshots.error.log

# Homebrew
cat "$(brew --prefix)/var/log/macos-compress-screenshots.error.log"
```

The tool's own compression log is at `~/Library/Logs/compress-screenshots.log`
either way.

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

1. Run the status check:
```bash
compress-screenshots-status   # or ./status.sh from a clone
```

   This reports whether the service is genuinely healthy, and exits non-zero if
   not. Note that `launchctl list | grep compress-screenshots` is *not* a
   reliable check on its own: because the LaunchAgent uses `KeepAlive`, a service
   that fails on startup is relaunched continuously and still appears there.
   `status.sh` distinguishes a running service from a restart loop.

2. If it reports that macOS is blocking access to the watched folder, see
   [Folder access on macOS](#folder-access-on-macos). This is the most common
   cause, and it affects the default Desktop setup.

3. Check the log file for errors:
```bash
tail -n 50 ~/Library/Logs/compress-screenshots.log
```

4. Ensure your screenshots match the expected naming pattern:
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
