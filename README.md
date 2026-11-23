# cc-tunnel Releases

Public release artifacts and installers for `cc-tunnel` (a private fork of [sun168567/cc-desk-tunnel](https://github.com/sun168567/cc-desk-tunnel) with native multi-PC loopback MCP tunneling and non-destructive skills sync).

## Quick Install

### 1. Server (Linux VPS with Docker)

```sh
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/itisvincent/cc-tunnel-releases/main/deploy/install.sh)"
```

- Pulls `ghcr.io/itisvincent/cc-tunnel:<version>` (or builds locally from the verified `cc-desk-tunnel-server-<version>.tar.gz` bundle if the image is not pulled).

### 2. Terminal Client `ccdt` (Windows PowerShell)

```powershell
irm https://raw.githubusercontent.com/itisvincent/cc-tunnel-releases/main/deploy/install-ccdt.ps1 | iex
```

Then sign in and configure your PC alias:

```powershell
ccdt login
ccdt config device.alias work        # or: home
ccdt config skills.exclude pc-only-skill
ccdt mcp
ccdt online
```