class AerospaceFocus < Formula
  desc "Focus indicator bar for AeroSpace window manager"
  homepage "https://github.com/dungle-scrubs/aerospace-focus"
  url "https://github.com/dungle-scrubs/aerospace-focus/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "92d321a1c21b705da545904b285d7f034bbb8c083f83602349f4880b41ac1754"
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
