# Installs ccdt, the terminal client of CC Desk Tunnel, for the current user, in Windows PowerShell or PowerShell 7:
#
#   irm https://raw.githubusercontent.com/itisvincent/cc-tunnel-releases/main/deploy/install-ccdt.ps1 | iex
#
# It downloads the Windows package of the newest release, checks it against the release's SHA256SUMS and puts it in
# place with the install script the package carries, which adds ccdt to the user's PATH; this window can use it at
# once. No administrator rights are needed. $env:CCDT_VERSION = '0.3.9' takes that release instead, the one of the
# service; $env:CCDT_DOWNLOAD_ONLY = '1' only unpacks the checked package into the current folder.
& {
  $ErrorActionPreference = 'Stop'
  # Windows PowerShell draws a progress bar for every block it downloads, which makes a large file slow.
  $ProgressPreference = 'SilentlyContinue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $repository = 'itisvincent/cc-tunnel-releases'
  $version = $env:CCDT_VERSION
  if (-not $version) {
    $version = (Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest").tag_name
  }
  $version = $version -replace '^v', ''
  $name = "ccdt-$version-windows-x64.zip"
  $base = "https://github.com/$repository/releases/download/v$version"
  $folder = Join-Path ([IO.Path]::GetTempPath()) "ccdt-install-$(Get-Random)"
  New-Item -ItemType Directory $folder | Out-Null
  try {
    Write-Host "Downloading ccdt $version..."
    $archive = Join-Path $folder $name
    $sums = Join-Path $folder 'SHA256SUMS'
    try {
      Invoke-WebRequest "$base/$name" -OutFile $archive -UseBasicParsing
      Invoke-WebRequest "$base/SHA256SUMS" -OutFile $sums -UseBasicParsing
    } catch {
      throw "Failed to download ccdt ${version}: $($_.Exception.Message). Check the version and network; set a system proxy if needed."
    }
    $expected = Get-Content $sums | ForEach-Object {
      $fields = $_.Trim() -split '\s+'
      if ($fields[1] -eq $name -or $fields[1] -eq "*$name") { $fields[0] }
    } | Select-Object -First 1
    if (-not $expected) { throw "$name not found in SHA256SUMS for $version." }
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $expected) {
      throw "Checksum mismatch for $name; not installed."
    }
    # The system's own tar, which reads .zip; another one may come first on the PATH.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if ($env:CCDT_DOWNLOAD_ONLY) {
      & $tar -xf $archive -C (Get-Location).Path
      if ($LASTEXITCODE) { throw 'Extraction failed.' }
      Write-Host "Verified and extracted to $(Join-Path (Get-Location).Path 'ccdt') (not installed)."
      return
    }
    & $tar -xf $archive -C $folder
    if ($LASTEXITCODE) { throw 'Extraction failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $folder 'ccdt\install.ps1')
    if ($LASTEXITCODE) { throw 'Install script failed.' }
    # The install script added ccdt to the user's PATH, which windows opened from now on read; this one is told too.
    $target = Join-Path $env:LOCALAPPDATA 'Programs\ccdt'
    if (-not (($env:Path -split ';') -contains $target)) { $env:Path = "$env:Path;$target" }
    Write-Host 'You can now run ccdt directly in this window.'
  } finally {
    Remove-Item -Recurse -Force $folder -ErrorAction SilentlyContinue
  }
}