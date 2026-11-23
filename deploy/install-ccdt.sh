#!/bin/sh
# Installs ccdt, the terminal client of CC Desk Tunnel, for the current user on macOS or Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/itisvincent/cc-tunnel-releases/main/deploy/install-ccdt.sh | sh
#
# It downloads the package of the newest release for this system, checks it against the release's SHA256SUMS and puts
# it in place with the install script the package carries. No root is needed. CCDT_VERSION=0.3.9 takes that release
# instead, the one of the service; CCDT_DOWNLOAD_ONLY=1 only unpacks the checked package into the current directory.
set -eu
repository=itisvincent/cc-tunnel-releases
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) system=mac-arm64 ;;
  Darwin-x86_64) system=mac-x64 ;;
  Linux-x86_64 | Linux-amd64) system=linux-x64 ;;
  Linux-aarch64 | Linux-arm64) system=linux-arm64 ;;
  *)
    echo "No ccdt package for platform $(uname -s) $(uname -m). On Windows, run install-ccdt.ps1 in PowerShell." >&2
    exit 1
    ;;
esac
version=${CCDT_VERSION:-}
if [ -z "$version" ]; then
  version=$(curl -fsSL "https://api.github.com/repos/$repository/releases/latest" |
    sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  if [ -z "$version" ]; then
    echo "Could not determine the latest release version; set CCDT_VERSION (e.g. CCDT_VERSION=0.3.9)." >&2
    exit 1
  fi
fi
version=${version#v}
name="ccdt-$version-$system.tar.gz"
base="https://github.com/$repository/releases/download/v$version"
folder=$(mktemp -d)
trap 'rm -rf "$folder"' EXIT
echo "Downloading ccdt $version..."
curl -fsSL -o "$folder/$name" "$base/$name"
curl -fsSL -o "$folder/SHA256SUMS" "$base/SHA256SUMS"
expected=$(awk -v name="$name" '$2 == name || $2 == "*" name { print $1; exit }' "$folder/SHA256SUMS")
if [ -z "$expected" ]; then
  echo "$name not found in SHA256SUMS for $version." >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$folder/$name" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$folder/$name" | cut -d ' ' -f 1)
fi
if [ "$actual" != "$expected" ]; then
  echo "Checksum mismatch for $name; not installed." >&2
  exit 1
fi
if [ -n "${CCDT_DOWNLOAD_ONLY:-}" ]; then
  tar -xzf "$folder/$name" -C .
  echo "Verified and extracted to $(pwd)/ccdt (not installed)."
  exit 0
fi
tar -xzf "$folder/$name" -C "$folder"
sh "$folder/ccdt/install.sh"
