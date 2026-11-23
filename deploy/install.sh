#!/usr/bin/env bash
# Installs or upgrades the CC Desk Tunnel service on this machine. It can be run on its own,
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/itisvincent/cc-tunnel-releases/main/deploy/install.sh)"
# in which case it fetches the newest release from GitHub (CC_DESK_TUNNEL_VERSION=X.Y.Z picks another), or from an
# unpacked server archive, which it then uses. The service runs the prebuilt image of that version where there is
# one, and builds it here where there is not (see manage.sh).
# It checks for what it needs and says how to install what is missing; it installs no system software and leaves
# the firewall, nginx and SSH alone. Its one addition to the host is the command `cc-desk-tunnel`.
set -euo pipefail

REPO="${CC_DESK_TUNNEL_REPO:-itisvincent/cc-tunnel-releases}"
TARGET="${CC_DESK_TUNNEL_DIR:-/opt/cc-desk-tunnel}"
TEMP=''
trap '[[ -z "$TEMP" ]] || rm -rf -- "$TEMP"' EXIT
fail() { echo "Error: $*" >&2; exit 1; }
confirm() {
  local answer
  read -r -p "$1 [Y/n]: " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}
version_of() { sed -n 's/^ *"version": "\([0-9.]*\)",\{0,1\}$/\1/p' "$1/apps/desktop/package.json" 2>/dev/null | head -n 1; }

main() {
  # Without arguments the installer asks its questions, gets the image, starts and prints a summary.
  (($#)) || set -- setup
  [[ "$1" = init || "$1" = setup ]] || fail "Arguments accept only setup (default) or init ...; use deploy/manage.sh for other operations."
  [[ "$(id -u)" = 0 ]] || fail "Root privileges required; re-run with sudo."
  [[ "$(uname -s)" = Linux && "$(uname -m)" =~ ^(x86_64|aarch64)$ ]] || fail "Only x86_64 (amd64) and aarch64 (arm64) Linux are supported."
  # Piped from curl, the script itself is on standard input; the questions need the terminal. Without one (a
  # script answering for itself), standard input stays as it is.
  if [[ ! -t 0 ]] && (exec < /dev/tty) 2>/dev/null; then exec < /dev/tty; fi
  local id=''
  [[ ! -r /etc/os-release ]] || id="$(. /etc/os-release && echo "${ID:-}")"
  [[ "$id" = ubuntu ]] || echo "Note: only tested on Ubuntu; other distributions may proceed (see the deploy guide if issues arise)."

  # What is missing is reported together with how to install it; nothing is installed from here.
  local missing=() packages=() tool
  for tool in curl tar openssl sha256sum; do
    command -v "$tool" >/dev/null || { missing+=("$tool"); packages+=("$([[ "$tool" = sha256sum ]] && echo coreutils || echo "$tool")"); }
  done
  command -v docker >/dev/null || { missing+=("Docker Engine"); packages+=(docker.io); }
  docker compose version >/dev/null 2>&1 || { missing+=("Docker Compose v2"); packages+=(docker-compose-v2); }
  if ((${#missing[@]})); then
    echo "Missing required components: ${missing[*]}" >&2
    if [[ "$id" = ubuntu ]]; then
      echo "Install them first and then re-run this script:" >&2
      echo "  sudo apt-get update && sudo apt-get install -y ${packages[*]}" >&2
    else
      echo "Install them for your distribution and re-run this script. Docker install docs: https://docs.docker.com/engine/install/" >&2
    fi
    exit 1
  fi
  docker info >/dev/null 2>&1 || {
    echo "Docker is installed but not running. Start it first and re-run this script:" >&2
    echo "  sudo systemctl enable --now docker" >&2
    exit 1
  }

  # Run from an unpacked server archive or a checkout, that copy is used as it is.
  local self="${BASH_SOURCE[0]:-}" root=''
  if [[ -n "$self" && -f "$(dirname -- "$self")/manage.sh" ]]; then
    root="$(cd -- "$(dirname -- "$self")/.." && pwd)"
  else
    local temp name installed latest releases="https://github.com/$REPO/releases/latest/download"
    temp="$(mktemp -d)"
    TEMP="$temp"
    if [[ -n "${CC_DESK_TUNNEL_VERSION:-}" ]]; then
      [[ "$CC_DESK_TUNNEL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "CC_DESK_TUNNEL_VERSION must be X.Y.Z."
      releases="https://github.com/$REPO/releases/download/v$CC_DESK_TUNNEL_VERSION"
    fi
    echo "Checking latest release (github.com/${REPO})..."
    curl -fsSL --connect-timeout 20 --max-time 60 -o "$temp/SHA256SUMS" "$releases/SHA256SUMS" \
      || fail "Failed to fetch release metadata. Check internet access to github.com and whether the version exists."
    name="$(awk '$2 ~ /^cc-desk-tunnel-server-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz$/ { print $2 }' "$temp/SHA256SUMS" | head -n 1)"
    [[ -n "$name" ]] || fail "No server package found in release SHA256SUMS."
    latest="${name#cc-desk-tunnel-server-}"; latest="${latest%.tar.gz}"

    if [[ -f "$TARGET/deploy/manage.sh" && -f "${PROXY_DEPLOY_CONFIG:-$TARGET/.local/docker.env}" ]]; then
      installed="$(version_of "$TARGET")"
      echo "Existing deployment detected: ${TARGET} (version ${installed:-unknown}), latest ${latest}."
      confirm "Upgrade to $latest and replace the container? Data, account, and config will be kept" || exit 0
      set -- upgrade
    elif [[ -e "$TARGET" && ! -f "$TARGET/deploy/manage.sh" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
      fail "$TARGET already exists and is not a CC Desk Tunnel directory. Pick another directory: CC_DESK_TUNNEL_DIR=/other/path"
    else
      cat <<NOTICE

About to install CC Desk Tunnel $latest to ${TARGET}. Before continuing, confirm:
  · You control and trust this server: while connected, it can run arbitrary commands as your local OS user.
  · The service token printed at completion grants full access to this server and connected clients; never share it.
  · Your firewall only needs to expose the single TCP port listed at the end of installation.
  · This project is largely AI-authored without a formal security audit; see https://github.com/$REPO

NOTICE
      confirm "Continue with installation?" || exit 0
    fi

    echo "Downloading $name..."
    curl -fL --connect-timeout 20 --max-time 600 --progress-bar -o "$temp/$name" \
      "https://github.com/$REPO/releases/download/v$latest/$name" || fail "Download failed."
    (cd "$temp" && grep "  $name\$" SHA256SUMS | sha256sum -c - >/dev/null) || fail "Checksum verification failed; aborted."
    if [[ "$1" = upgrade ]]; then
      # A manage.sh older than this archive unpacks it and hands over to the new one, which need not fetch it again.
      CC_DESK_TUNNEL_UNPACKED=1 bash "$TARGET/deploy/manage.sh" upgrade --from "$temp/$name"
      exit
    fi
    if tar -tzf "$temp/$name" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null; then fail "Archive contains unsafe paths."; fi
    mkdir -p "$TARGET"
    tar -xzf "$temp/$name" -C "$TARGET" --no-same-owner
    root="$TARGET"
  fi

  bash "$root/deploy/manage.sh" "$@"
  if [[ "$1" = setup ]]; then
    echo "Client downloads: https://github.com/$REPO/releases/latest"
  else
    echo "Next: edit provider settings if needed, then run: sudo cc-desk-tunnel up"
    echo "Management: sudo cc-desk-tunnel status | logs | upgrade | help"
  fi
  echo "This script did not modify firewall, nginx, or SSH settings, nor install system packages."
}
main "$@"
