# Boot an Android emulator (if none is running) and wait until Android has finished booting.
#
# Usage: start-emulator.ps1 [avd-name]   (default: rn_pixel, else the first AVD found)
# Emulator output goes to %LOCALAPPDATA%\rn-starter\emulator.log

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\env.ps1"

$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $DefaultAndroidHome }
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not (Test-Path $emulator)) { Stop-WithError 'Android emulator not installed. Run install-android.ps1 first.' }

$devices = (Invoke-Native $adb @('devices')) -split "`n" | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice" }
if ($devices) {
  Write-Step 'A device/emulator is already connected:'
  $devices
  exit 0
}

$avds = (Invoke-Native $emulator @('-list-avds')) -split "`n" | Where-Object { $_ -and $_ -notmatch '^INFO' }
$avd = $null
if ($args.Count -gt 0) { $avd = $args[0] }
elseif ($avds -contains 'rn_pixel') { $avd = 'rn_pixel' }
elseif ($avds) { $avd = @($avds)[0] }
if (-not $avd) { Stop-WithError 'No AVD found. Run install-android.ps1 to create one.' }

New-Item -ItemType Directory -Force -Path $RnHome | Out-Null
$log = Join-Path $RnHome 'emulator.log'
Write-Step "Starting emulator '$avd' (log: $log)"
Start-Process -FilePath $emulator -ArgumentList @('-avd', $avd, '-no-boot-anim', '-no-snapshot-save') `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Minimized | Out-Null

$null = Invoke-Native $adb @('wait-for-device')
$deadline = (Get-Date).AddSeconds(300)
while ((Invoke-Native $adb @('shell', 'getprop', 'sys.boot_completed')) -ne '1') {
  if ((Get-Date) -gt $deadline) {
    if (Test-Path $log) { Get-Content $log -Tail 20 }
    Stop-WithError 'Emulator did not finish booting within 300s.'
  }
  Start-Sleep -Seconds 3
}

# A fresh AVD often shows "<system app> isn't responding" on first boot, covering the app.
Start-Sleep -Seconds 5
$null = Invoke-Native $adb @('shell', 'am', 'broadcast', '-a', 'android.intent.action.CLOSE_SYSTEM_DIALOGS')
Write-Step "Emulator '$avd' is ready"
