# StaffOS Homebrew formula — source of truth for the tap
# (github.com/rajgurung/homebrew-tap → Formula/staffos.rb).
#
# Don't hand-edit url/sha256: bump VERSION in cli/staffos, then run `bin/release`,
# which tags, cuts the GitHub release, and pushes the rendered formula to the tap.
#
# Install: brew install rajgurung/tap/staffos
class Staffos < Formula
  desc "Capture Claude Code sessions into StaffOS Run Passports"
  homepage "https://github.com/rajgurung/staffOS"
  url "https://github.com/rajgurung/staffOS/archive/refs/tags/cli-v0.1.2.tar.gz"
  sha256 "8440328a0f26398e71d1f67ba8194db4d683e8b3d4c61f99ce3acf0387f85187"
  license "MIT"

  depends_on "ruby"

  def install
    # Pin the shebang to Homebrew's Ruby so the CLI runs even on machines with
    # no system Ruby (Apple is phasing it out). The script is stdlib-only.
    inreplace "cli/staffos", %r{\A#!/usr/bin/env ruby}, "#!#{Formula["ruby"].opt_bin}/ruby"
    bin.install "cli/staffos" => "staffos"
  end

  test do
    assert_match "staffos #{version}", shell_output("#{bin}/staffos version")
  end
end
