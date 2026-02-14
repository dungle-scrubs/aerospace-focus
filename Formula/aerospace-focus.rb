class AerospaceFocus < Formula
  desc "Focus indicator bar for AeroSpace window manager"
  homepage "https://github.com/dungle-scrubs/aerospace-focus"
  url "https://github.com/dungle-scrubs/aerospace-focus/archive/refs/tags/v0.1.4.tar.gz"
  sha256 "f9778c94e8e145a4fc5f2a38ca0f449180a0e5e6854ad84a725ad26f8cf79c0e"
  license "MIT"

  head "https://github.com/dungle-scrubs/aerospace-focus.git", branch: "main"

  depends_on :macos
  depends_on xcode: ["14.3", :build]

  def install
    system "swift", "build", "-c", "release"
    bin.install ".build/release/aerospace-focus"
  end

  service do
    run [opt_bin/"aerospace-focus", "daemon"]
    keep_alive true
    log_path var/"log/aerospace-focus.log"
    error_log_path var/"log/aerospace-focus.err"
  end

  def caveats
    <<~EOS
      To integrate with AeroSpace, add to ~/.config/aerospace/aerospace.toml:

        after-startup-command = [
            'exec-and-forget aerospace-focus daemon'
        ]

        on-focus-changed = ['exec-and-forget aerospace-focus update']

      Then reload: aerospace reload-config

      You may need to grant Accessibility permissions:
        System Settings → Privacy & Security → Accessibility

      Logs: #{var}/log/aerospace-focus.log
    EOS
  end

  test do
    output = shell_output("#{bin}/aerospace-focus --help 2>&1", 0)
    assert_match "focus indicator bar", output.downcase
    
    version_output = shell_output("#{bin}/aerospace-focus --version 2>&1", 0)
    assert_match version.to_s, version_output
  end
end
