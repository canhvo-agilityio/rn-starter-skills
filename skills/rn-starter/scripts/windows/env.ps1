# Dot-source to put tools installed by rn-starter on PATH in the current PowerShell session:
#   . <skill-dir>\scripts\windows\env.ps1
# Running apps (including Claude) don't see user PATH changes until restarted; this bridges that.
# Safe to run repeatedly; skips anything not installed.

$__rn = Join-Path $env:LOCALAPPDATA 'rn-starter'

function __RnPrependPath([string]$dir) {
  if ((Test-Path $dir) -and (($env:Path.Split(';')) -notcontains $dir)) { $env:Path = "$dir;$env:Path" }
}

# Pick up user-level values set by the install scripts (or by the dev) after this process started.
foreach ($name in @('JAVA_HOME', 'ANDROID_HOME')) {
  if (-not (Get-Item "Env:$name" -ErrorAction SilentlyContinue)) {
    $v = [Environment]::GetEnvironmentVariable($name, 'User')
    if ($v) { Set-Item "Env:$name" $v }
  }
}

__RnPrependPath (Join-Path $__rn 'node')

if (-not $env:JAVA_HOME -and (Test-Path (Join-Path $__rn 'jdk-17\bin\java.exe'))) { $env:JAVA_HOME = Join-Path $__rn 'jdk-17' }
if ($env:JAVA_HOME) { __RnPrependPath (Join-Path $env:JAVA_HOME 'bin') }

if (-not $env:ANDROID_HOME) {
  $__sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
  if (Test-Path $__sdk) { $env:ANDROID_HOME = $__sdk }
}
if ($env:ANDROID_HOME) {
  foreach ($__p in @('platform-tools', 'emulator', 'cmdline-tools\latest\bin')) { __RnPrependPath (Join-Path $env:ANDROID_HOME $__p) }
}

Remove-Variable __rn, __sdk, __p -ErrorAction SilentlyContinue
