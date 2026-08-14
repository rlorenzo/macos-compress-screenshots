# Homebrew packaging

This repository doubles as its own Homebrew tap. `Formula/macos-compress-screenshots.rb`
is the formula; everything below is for maintaining it. Users only need the
install instructions in [README.md](README.md).

## Why a tap and not homebrew-core

homebrew-core has notability requirements (roughly 75 stars, 30 forks or 30
watchers) and is reluctant to take single-purpose shell scripts whose main job
is to run a launchd agent. A tap has no such gatekeeping, and upgrades work
exactly the same way for users.

## How the tap is laid out

Homebrew finds formulae in a `Formula/` directory at the root of a tapped
repository. That is all a tap needs, so this repository serves as one directly:

```bash
brew tap rlorenzo/tap https://github.com/rlorenzo/macos-compress-screenshots
brew install macos-compress-screenshots
```

The explicit URL is what allows a repository not named `homebrew-tap` to be
tapped. If you would rather have the conventional short form
(`brew tap rlorenzo/tap`), create a separate repository named
`rlorenzo/homebrew-tap` containing only `Formula/macos-compress-screenshots.rb`
and keep it in sync with this one. Nothing else changes — the formula file is
identical either way.

## What the formula replaces

| Manual install | Homebrew |
| --- | --- |
| `install.sh` checks for and installs dependencies | `depends_on "fswatch"` / `"pngquant"` |
| `com.macos.compress-screenshots.plist` + `sed` templating | the `service do` block |
| `launchctl load` / `unload` | `brew services start` / `stop` |
| `uninstall.sh` | `brew services stop && brew uninstall` |
| `./status.sh` | `compress-screenshots-status` |

`install.sh` and the plist template stay in the repository. They are the
supported path for anyone who does not use Homebrew, and they remain the only
install path that can *ask* the user anything.

### The one behavioural difference

A formula cannot be interactive, so it has no equivalent of `install.sh`'s
prompt about macOS-protected screenshot folders. Two things cover the gap:

- `compress-screenshots.sh` resolves the screenshot location itself at startup
  (`resolve_screenshot_dir`) instead of having it baked in at install time, so
  the service follows the ⌘⇧5 "Save to" setting across a restart.
- The formula's `caveats` block explains the folder problem and the fix.

An explicit `WATCH_DIR` in the environment still overrides the detected folder,
which is how `install.sh` pins its answer and how the test suite redirects the
service at a temporary directory.

## Cutting a release

1. Tag and push:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. Point the formula at the tag and record its checksum:

   ```bash
   ./scripts/update-formula.sh v1.0.0
   ```

   This downloads the tarball GitHub generates for the tag, hashes it, and
   rewrites the `url` and `sha256` lines. It refuses to write anything if the
   tag was never pushed.

3. Check the result, then commit:

   ```bash
   brew style Formula/macos-compress-screenshots.rb
   git commit -am "chore: update formula to v1.0.0"
   ```

   `brew style` is the only check that runs against a bare file. Everything
   else needs the formula to be in a tap — see below.

## Testing the formula locally

Homebrew refuses to work with a formula outside a tap, so `brew install
./Formula/…rb` and `brew audit --formula ./Formula/…rb` both fail with
"Homebrew requires formulae to be in a tap". Use a throwaway tap instead:

```bash
brew tap-new --no-git rlorenzo/fmtest
cp Formula/macos-compress-screenshots.rb \
   "$(brew --repository)/Library/Taps/rlorenzo/homebrew-fmtest/Formula/"

brew info  rlorenzo/fmtest/macos-compress-screenshots
brew audit --strict --formula rlorenzo/fmtest/macos-compress-screenshots
```

To exercise the install and `test do` blocks as well — this needs the commit
under test to be pushed, since `--HEAD` clones from the `head` URL:

```bash
brew install --HEAD rlorenzo/fmtest/macos-compress-screenshots
brew test rlorenzo/fmtest/macos-compress-screenshots
brew services start rlorenzo/fmtest/macos-compress-screenshots
compress-screenshots-status
```

Clean up afterwards:

```bash
brew services stop macos-compress-screenshots
brew uninstall macos-compress-screenshots
brew untap rlorenzo/fmtest
```

## Things worth knowing

- **Full Disk Access is unchanged.** A `brew services` agent is subject to the
  same TCC restrictions as a hand-installed one, so `~/Desktop` is still
  unreadable to it by default. The formula cannot fix this; it can only explain
  it in `caveats`.
- **Both installations can coexist.** Installing with Homebrew does not remove a
  previous `./install.sh` install, and two services watching one folder
  duplicate the work. `status.sh` detects and warns about this.
- **Service logs live in two places.** launchd's stdout and stderr for the
  service go to `$(brew --prefix)/var/log/macos-compress-screenshots*.log`,
  while the tool's own compression log stays at
  `~/Library/Logs/compress-screenshots.log` for both install methods.
