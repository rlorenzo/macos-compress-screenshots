class MacosCompressScreenshots < Formula
  desc "Automatically compress macOS screenshots as they are saved"
  homepage "https://github.com/rlorenzo/macos-compress-screenshots"
  url "https://github.com/rlorenzo/macos-compress-screenshots/archive/refs/tags/v1.0.0.tar.gz"
  # url and sha256 are rewritten by scripts/update-formula.sh at release time.
  # This placeholder stands until the first tag is pushed; before then the
  # formula is only installable with `brew install --HEAD`.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/rlorenzo/macos-compress-screenshots.git", branch: "main"

  # fswatch and pngquant are hard requirements rather than optional extras:
  # fswatch watches the screenshot folder and pngquant compresses what appears
  # there, so the service cannot do anything at all without them.
  depends_on "fswatch"
  depends_on :macos
  depends_on "pngquant"

  def install
    bin.install "compress-screenshots.sh" => "compress-screenshots"
    bin.install "status.sh" => "compress-screenshots-status"
    doc.install "README.md", "EXAMPLES.md"
  end

  # Replaces the hand-written LaunchAgent plist and install.sh's launchctl calls.
  # Homebrew generates the plist from this block, so the paths never have to be
  # substituted into a template.
  #
  # No WATCH_DIR is set here: compress-screenshots reads the macOS screenshot
  # location itself at startup, which is what lets a formula - which cannot ask
  # the user anything at install time - still watch the right folder.
  service do
    run opt_bin/"compress-screenshots"
    run_type :immediate
    keep_alive true
    log_path var/"log/macos-compress-screenshots.log"
    error_log_path var/"log/macos-compress-screenshots.error.log"
    environment_variables PATH: std_service_path_env
  end

  def caveats
    <<~EOS
      Start the service with:
        brew services start macos-compress-screenshots

      macOS blocks background services from reading ~/Desktop, ~/Documents and
      ~/Downloads, and screenshots are saved to ~/Desktop by default. Until that
      changes, the service runs but never compresses anything.

      The simplest fix is to save screenshots somewhere macOS does not protect:
        mkdir -p ~/Screenshots
        defaults write com.apple.screencapture location ~/Screenshots
        killall SystemUIServer
        brew services restart macos-compress-screenshots

      The service follows that setting, so nothing else needs reconfiguring.
      To keep screenshots on the Desktop instead, grant Full Disk Access to
      /bin/bash - see "Folder access on macOS" in:
        #{doc}/README.md

      Check on the service with:
        compress-screenshots-status

      Compression activity is logged to:
        ~/Library/Logs/compress-screenshots.log
    EOS
  end

  test do
    # The script only runs main() when executed directly, so sourcing it exposes
    # the real matcher rather than a copy of it.
    probe = testpath/"probe.sh"
    probe.write <<~SH
      source "#{bin}/compress-screenshots"
      is_screenshot "Screenshot 2024-01-23 at 2.11.11 PM.png" || exit 1
      if is_screenshot "vacation-photo.png"; then exit 2; fi
      exit 0
    SH

    with_env(WATCH_DIR: testpath.to_s, LOG_FILE: (testpath/"probe.log").to_s) do
      system "/bin/bash", probe
    end

    # And an end-to-end check that the service reports a misconfigured folder
    # instead of failing silently. FATAL_RETRY_DELAY is normally a long pause
    # that keeps launchd's KeepAlive from spinning on the same error.
    with_env(
      WATCH_DIR:         (testpath/"does-not-exist").to_s,
      LOG_FILE:          (testpath/"run.log").to_s,
      FATAL_RETRY_DELAY: "0",
    ) do
      shell_output("#{bin}/compress-screenshots", 1)
    end
    assert_match "Watch directory does not exist", (testpath/"run.log").read
  end
end
