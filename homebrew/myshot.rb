# MyShot CLI Homebrew Formula
# Usage: brew install --build-from-source myshot.rb

class Myshot < Formula
  desc "Screenshot and screen recording tool for macOS with auto-redact"
  homepage "https://myshot.1vision.work"
  url "https://github.com/datntpro/myshot/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"
  
  depends_on :macos
  depends_on xcode: ["14.0", :build]

  def install
    system "swift", "build", "-c", "release", "--product", "myshot-cli"
    bin.install ".build/release/myshot-cli" => "myshot"
  end

  def caveats
    <<~EOS
      MyShot CLI has been installed!
      
      Usage:
        myshot --help
        myshot capture --fullscreen
        myshot ocr ~/path/to/image.png
      
      For full features including GUI annotation, install MyShot.app:
        https://myshot.1vision.work/download
    EOS
  end

  test do
    assert_match "MyShot CLI", shell_output("#{bin}/myshot --version")
  end
end
