# Read-only environment check for React Native development on Windows. Installs nothing.
# Same output format as doctor.sh: "ok|warn|missing  <name>  <detail>" lines, then
#   summary missing=<comma list> warn=<comma list>
#
# Usage: doctor.ps1 [--android] [--ios]
#   --android   also check JDK 17, Android SDK, emulator, AVDs and hardware acceleration
#   --ios       reports that the iOS Simulator needs macOS

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\env.ps1"

$checkAndroid = $args -contains '--android'
$checkIos = $args -contains '--ios'
$missing = New-Object System.Collections.ArrayList
$warns = New-Object System.Collections.ArrayList

function Row([string]$status, [string]$name, [string]$detail) {
  '{0,-8} {1,-16} {2}' -f $status, $name, $detail | Write-Output
  if ($status -eq 'missing') { [void]$missing.Add($name) }
  if ($status -eq 'warn') { [void]$warns.Add($name) }
}
function Find-Exe([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

# --- system ---
$os = Get-CimInstance Win32_OperatingSystem
Row 'ok' 'os' "windows $(Get-CpuArch) ($($os.Caption) $($os.Version))"
Row 'ok' 'shell' "PowerShell $($PSVersionTable.PSVersion)"

$git = Find-Exe 'git'
if ($git) { Row 'ok' 'git' (Invoke-Native $git @('--version')) }
else { Row 'missing' 'git' 'not installed - Claude Code on Windows needs Git for Windows: winget install --id Git.Git -e' }

# --- node ---
$node = Find-Exe 'node'
if ($node) {
  $v = Invoke-Native $node @('-v')
  if (Test-NodeVersion $v) { Row 'ok' 'node' "$v ($node)" }
  else { Row 'warn' 'node' "$v is not supported - need ^22.13, ^24.3 or an even major >= 26 (LTS)" }
} else {
  Row 'missing' 'node' 'not installed'
}

foreach ($pm in @('npm', 'pnpm', 'yarn', 'bun')) {
  $exe = Find-Exe $pm
  if (-not $exe) { '{0,-8} {1,-16} {2}' -f '-', $pm, 'not installed (optional)' | Write-Output; continue }
  $pv = Invoke-Native $exe @('--version')
  if ($pm -eq 'pnpm' -and $pv -match '^11\.') {
    Row 'warn' 'pnpm' "$pv - installs can hang after 'Done'; update: npm install -g pnpm@latest"
  } else {
    Row 'ok' $pm $pv
  }
}

# --- android ---
if ($checkAndroid) {
  $java = $null
  if ($env:JAVA_HOME) { $java = Join-Path $env:JAVA_HOME 'bin\java.exe' }
  if ($java -and (Test-Path $java)) {
    $jv = Invoke-Native $java @('-version')
    if ($jv -match 'version "17') { Row 'ok' 'jdk' "17 ($env:JAVA_HOME)" }
    else { Row 'warn' 'jdk' "$(($jv -split "`n")[0]) at $env:JAVA_HOME - React Native recommends JDK 17" }
  } else {
    Row 'missing' 'jdk' 'JDK 17 not found (JAVA_HOME unset)'
  }

  $sdk = $env:ANDROID_HOME
  if (-not $sdk) { $sdk = $DefaultAndroidHome }
  if (Test-Path $sdk) {
    Row 'ok' 'android-sdk' $sdk
    if (Test-Path "$sdk\cmdline-tools\latest\bin\sdkmanager.bat") { Row 'ok' 'sdkmanager' 'cmdline-tools\latest' }
    else { Row 'missing' 'sdkmanager' 'cmdline-tools\latest not installed' }
    $adb = "$sdk\platform-tools\adb.exe"
    if (Test-Path $adb) { Row 'ok' 'adb' ((Invoke-Native $adb @('version') -split "`n")[0]) }
    else { Row 'missing' 'adb' 'platform-tools not installed' }
    $emu = "$sdk\emulator\emulator.exe"
    if (Test-Path $emu) {
      Row 'ok' 'emulator' 'installed'
      $avds = (Invoke-Native $emu @('-list-avds') -split "`n") | Where-Object { $_ -and $_ -notmatch '^INFO' }
      if ($avds) { Row 'ok' 'avd' ($avds -join ' ') } else { Row 'missing' 'avd' 'no virtual device created' }
      # Hardware acceleration: without WHPX (or the Android Emulator hypervisor driver) the emulator won't start.
      $accel = Invoke-Native $emu @('-accel-check')
      if ($accel -match 'is installed and usable') { Row 'ok' 'acceleration' (($accel -split "`n") | Where-Object { $_ -match 'usable' } | Select-Object -First 1) }
      else { Row 'missing' 'acceleration' 'Windows Hypervisor Platform not usable - see install-android.ps1 for the admin step' }
    } else {
      Row 'missing' 'emulator' 'emulator not installed'
    }
    if ((Test-Path "$sdk\platforms") -and (Get-ChildItem "$sdk\platforms" -Directory | Where-Object { $_.Name -like 'android-*' })) {
      Row 'ok' 'platforms' ((Get-ChildItem "$sdk\platforms" -Directory).Name -join ' ')
    } else {
      Row 'missing' 'platforms' 'no Android platform installed'
    }
  } else {
    Row 'missing' 'android-sdk' "ANDROID_HOME not set and $sdk does not exist"
  }
}

if ($checkIos) {
  Row 'missing' 'ios-simulator' 'the iOS Simulator only runs on macOS - on Windows use Expo Go on an iPhone, the Android emulator or web'
}

''
"summary missing=$($missing -join ',') warn=$($warns -join ',')"
