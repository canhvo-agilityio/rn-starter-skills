# Install what's needed to run React Native on an Android emulator on Windows, without Android
# Studio and without admin rights: JDK 17 (Temurin), Android command-line tools, platform-tools,
# emulator, an Android platform + system image, and one AVD. Idempotent.
#
# Usage: install-android.ps1 --accept-licenses [--api 35] [--avd rn_pixel]
#   --accept-licenses  required: the developer has read and accepted the Android SDK License
#                      Agreement (https://developer.android.com/studio/terms)
#
# Exit codes: 0 ready · 1 error · 2 waiting on the developer (hardware acceleration needs an admin step)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\env.ps1"

$api = '35'; $avd = 'rn_pixel'; $accepted = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--accept-licenses' { $accepted = $true }
    '--api' { $i++; $api = $args[$i] }
    '--avd' { $i++; $avd = $args[$i] }
    default { Stop-WithError "unknown option: $($args[$i])" }
  }
}
if (-not $accepted) { Stop-WithError 'The Android SDK license must be accepted by the developer first. Ask them, then rerun with --accept-licenses.' }

$arch = Get-CpuArch
New-Item -ItemType Directory -Force -Path $RnHome | Out-Null

# ---------------------------------------------------------------- JDK 17
function Test-Jdk17 {
  if (-not $env:JAVA_HOME) { return $false }
  $java = Join-Path $env:JAVA_HOME 'bin\java.exe'
  if (-not (Test-Path $java)) { return $false }
  return ((Invoke-Native $java @('-version')) -match 'version "17')
}

if (Test-Jdk17) {
  Write-Step "JDK 17 already available at $env:JAVA_HOME"
} else {
  $jdkArch = 'x64'; if ($arch -eq 'arm64') { $jdkArch = 'aarch64' }
  $jdkDir = Join-Path $RnHome 'jdk-17'
  $zip = Join-Path ([IO.Path]::GetTempPath()) 'jdk17.zip'
  Save-Download "https://api.adoptium.net/v3/binary/latest/17/ga/windows/$jdkArch/jdk/hotspot/normal/eclipse" $zip
  Expand-ZipFlat $zip $jdkDir
  Remove-Item -Force $zip
  $env:JAVA_HOME = $jdkDir
  if (-not (Test-Jdk17)) { Stop-WithError "JDK 17 install failed (JAVA_HOME=$jdkDir)" }
}
Set-UserEnv 'JAVA_HOME' $env:JAVA_HOME
Add-UserPath (Join-Path $env:JAVA_HOME 'bin')

# ---------------------------------------------------------------- command-line tools
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $DefaultAndroidHome }
$sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdmanager = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'

if (Test-Path $sdkmanager) {
  Write-Step 'Android command-line tools already installed'
} else {
  $xml = (Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/repository2-3.xml' -UseBasicParsing).Content
  $zipName = [regex]::Matches($xml, 'commandlinetools-win-(\d+)_latest\.zip') |
    Sort-Object { [long]$_.Groups[1].Value } | Select-Object -Last 1
  if (-not $zipName) { Stop-WithError "Could not find the command-line tools download in Google's manifest." }
  $zip = Join-Path ([IO.Path]::GetTempPath()) $zipName.Value
  Save-Download "https://dl.google.com/android/repository/$($zipName.Value)" $zip
  Expand-ZipFlat $zip (Join-Path $sdk 'cmdline-tools\latest')   # the zip's top folder is "cmdline-tools"
  Remove-Item -Force $zip
}
Set-UserEnv 'ANDROID_HOME' $sdk
# avdmanager (Java) and the emulator must agree on where AVDs live.
if (-not $env:ANDROID_USER_HOME) { $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE '.android' }

# ---------------------------------------------------------------- SDK packages
$abi = 'x86_64'; if ($arch -eq 'arm64') { $abi = 'arm64-v8a' }
$image = "system-images;android-$api;google_apis;$abi"

Write-Step 'Recording license acceptance'
$yes = ("y`r`n" * 40)
$null = $yes | & $sdkmanager "--sdk_root=$sdk" --licenses 2>&1
if (-not (Test-Path (Join-Path $sdk 'licenses\android-sdk-license'))) {
  Stop-WithError 'sdkmanager did not record the license (check JAVA_HOME / network and rerun).'
}

Write-Step 'Installing SDK packages (this is the big download)'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $sdkmanager "--sdk_root=$sdk" --install 'platform-tools' 'emulator' "platforms;android-$api" $image 2>&1 |
  Where-Object { "$_" -notmatch '^\[=*\s*\]' } | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($code -ne 0) { Stop-WithError "sdkmanager --install failed (exit $code)" }

foreach ($p in @('platform-tools', 'emulator', 'cmdline-tools\latest\bin')) { Add-UserPath (Join-Path $sdk $p) }

# ---------------------------------------------------------------- AVD
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$avds = Invoke-Native $emulator @('-list-avds')
if (($avds -split "`n") -contains $avd) {
  Write-Step "AVD '$avd' already exists"
} else {
  $devices = Invoke-Native $avdmanager @('list', 'device', '-c')
  $device = 'pixel'; if (($devices -split "`n") -contains 'pixel_7') { $device = 'pixel_7' }
  Write-Step "Creating AVD '$avd' ($image)"
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $null = 'no' | & $avdmanager create avd -n $avd -k $image -d $device 2>&1
  $ErrorActionPreference = $prev
}

# ---------------------------------------------------------------- hardware acceleration
$accel = Invoke-Native $emulator @('-accel-check')
if ($accel -notmatch 'is installed and usable') {
  Write-Host $accel
  Stop-NeedsDeveloper @"
The Android emulator needs hardware acceleration (Windows Hypervisor Platform), which only an
administrator can turn on:

  1. Open PowerShell as Administrator (Start > type PowerShell > Run as administrator) and run:
       Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart
  2. Restart Windows.
  3. If it still fails, enable virtualization (Intel VT-x / AMD SVM) in the BIOS/UEFI settings.

Everything else is installed. After the restart, rerun this script — it only re-checks.
"@
}

Write-Step "Android toolchain ready. JAVA_HOME=$env:JAVA_HOME ANDROID_HOME=$sdk AVD=$avd"
Write-Step 'Restart open terminals (and the Claude app) to pick up the new environment outside this session.'
