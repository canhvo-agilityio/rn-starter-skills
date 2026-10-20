# Install Node.js LTS for the current user on Windows. No admin rights, no installer:
# the official zip goes to %LOCALAPPDATA%\rn-starter\node and onto the user PATH. Idempotent.
#
# Usage: install-node.ps1

. "$PSScriptRoot\common.ps1"

$nodeDir = Join-Path $RnHome 'node'
$ours = Join-Path $nodeDir 'node.exe'

# Already fine? (ours, or a system Node that meets the version requirement)
$existing = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
  $v = Invoke-Native $existing.Source @('-v')
  if (Test-NodeVersion $v) {
    Write-Step "Node $v already installed at $($existing.Source)"
    exit 0
  }
  Write-Warn "Found Node $v at $($existing.Source), which React Native 0.88 / Expo SDK 58 don't support. Installing a supported LTS for this user."
}

$arch = Get-CpuArch
$index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
$lts = $index | Where-Object { $_.lts -and (Test-NodeVersion $_.version) -and ($_.files -contains "win-$arch-zip") } | Select-Object -First 1
if (-not $lts) { Stop-WithError "Could not find a supported Node LTS zip for win-$arch on nodejs.org." }

$ver = $lts.version
$name = "node-$ver-win-$arch"
$zip = Join-Path ([IO.Path]::GetTempPath()) "$name.zip"
Save-Download "https://nodejs.org/dist/$ver/$name.zip" $zip
Write-Step "Installing Node $ver into $nodeDir"
Expand-ZipFlat $zip $nodeDir
Remove-Item -Force $zip

# With the zip distribution, npm's global prefix is the Node folder itself, so global tools
# (pnpm, yarn) land on the same PATH entry.
Add-UserPath $nodeDir

$v = Invoke-Native $ours @('-v')
$npmV = Invoke-Native (Join-Path $nodeDir 'npm.cmd') @('-v')
Write-Step "node $v, npm $npmV"

# A system-wide Node from an MSI sits in the *system* PATH, which Windows puts before the user PATH.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($existing -and $machinePath -and ($machinePath.Split(';') -contains (Split-Path $existing.Source))) {
  Write-Warn "The older system-wide Node at $(Split-Path $existing.Source) still comes first in new terminals. Uninstall it (Settings > Apps > Node.js) so this one is used everywhere."
}

Write-Step 'Restart open terminals (and the Claude app) to pick up the new PATH outside this session.'
