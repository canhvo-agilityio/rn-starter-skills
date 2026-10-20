# Shared helpers for the Windows scripts. Dot-source it: . "$PSScriptRoot\common.ps1"
# Written for Windows PowerShell 5.1 (the default on a clean Windows) — no PowerShell 7-only syntax.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar on 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RnHome = Join-Path $env:LOCALAPPDATA 'rn-starter'
$DefaultAndroidHome = Join-Path $env:LOCALAPPDATA 'Android\Sdk'   # same place Android Studio uses

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "warn: $msg" -ForegroundColor Yellow }
function Stop-WithError([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# The developer has to do something (admin rights, a reboot, a sign-in). Exit 2, like setup-ios.sh.
function Stop-NeedsDeveloper([string]$msg) {
  Write-Host ''
  Write-Host 'ACTION REQUIRED - the developer needs to do this, then rerun this script:' -ForegroundColor Yellow
  Write-Host ''
  Write-Host $msg
  Write-Host ''
  exit 2
}

function Get-CpuArch {
  $a = $env:PROCESSOR_ARCHITEW6432
  if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
  if ($a -eq 'ARM64') { return 'arm64' }
  return 'x64'
}

# Run a native program and return its combined stdout+stderr as one string. With
# $ErrorActionPreference = 'Stop', PowerShell 5.1 turns any stderr line of a native program
# (e.g. `java -version`) into a terminating error, so relax it for the call.
# $LASTEXITCODE still holds the program's exit code afterwards.
function Invoke-Native([string]$exe, [string[]]$argList = @()) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $exe @argList 2>&1 | ForEach-Object { "$_" }
  } finally {
    $ErrorActionPreference = $prev
  }
  return (($out | Where-Object { $_ -ne $null }) -join "`n").Trim()
}

function Save-Download([string]$url, [string]$dest) {
  Write-Step "Downloading $url"
  $tmp = "$dest.part"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  Move-Item -Force $tmp $dest
}

# Extract a zip whose content sits in one top-level folder, so $dest gets that folder's content.
function Expand-ZipFlat([string]$zip, [string]$dest) {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $items = @(Get-ChildItem $tmp)
  $src = $tmp
  if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src = $items[0].FullName }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Move-Item $src $dest
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}

# Persist for future terminals (user scope, no admin) and apply to this process.
function Set-UserEnv([string]$name, [string]$value) {
  [Environment]::SetEnvironmentVariable($name, $value, 'User')
  Set-Item -Path "Env:$name" -Value $value
  Write-Step "Set user environment variable $name"
}

function Add-UserPath([string]$dir) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $userPath) { $userPath = '' }
  $parts = $userPath.Split(';') | Where-Object { $_ -ne '' }
  if ($parts -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', (@($dir) + $parts) -join ';', 'User')
    Write-Step "Added to user PATH: $dir"
  }
  if (($env:Path.Split(';')) -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}

# "v24.22.0" -> $true when React Native 0.88 / Expo SDK 58 accept it: ^22.13 || ^24.3 || even major >= 26
function Test-NodeVersion([string]$v) {
  if ($v -notmatch '^v?(\d+)\.(\d+)') { return $false }
  $major = [int]$Matches[1]; $minor = [int]$Matches[2]
  if ($major -eq 22 -and $minor -ge 13) { return $true }
  if ($major -eq 24 -and $minor -ge 3) { return $true }
  if ($major -ge 26 -and ($major % 2) -eq 0) { return $true }
  return $false
}
