class AerospaceFocus < Formula
  desc "Focus indicator bar for AeroSpace window manager"
  homepage "https://github.com/dungle-scrubs/aerospace-focus"
  url "https://github.com/dungle-scrubs/aerospace-focus/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "f287be0e60dd0f3429100581f3d2da76756ba89b621a569586c4ea1e0398c791"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/aerospace-focus"
  end

  service do
    run [opt_bin/"aerospace-focus", "daemon"]
    keep_alive true
    log_path var/"log/aerospace-focus.log"
    error_log_path var/"log/aerospace-focus.err"
  end

  test do
    output = shell_output("#{bin}/aerospace-focus --help 2>&1", 0)
    assert_match "focus indicator bar", output.downcase
  end
end
