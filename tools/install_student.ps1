<#
.SYNOPSIS
  Student machine: downloads the Vingt-Un APK from the teacher's classroom server
  (tools/start_classroom.ps1, http://<TeacherIp>:8088) and installs it with "adb install -r"
  on the LOCAL ANDROID EMULATOR only (it starts this machine's AVD first if none is running, then
  opens the app). Physical devices are never targeted: the serial must be
  emulator-NNNN and the device must report itself as an emulator (ro.kernel.qemu / ro.boot.qemu).
.PARAMETER TeacherIp
  IPv4 address (or host name) of the teacher machine, as shown by tools/start_classroom.ps1.
.PARAMETER Serial
  Emulator serial to use (must match emulator-NNNN). Default: the first running emulator.
.PARAMETER Port
  Port of the download page (default 8088).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\install_student.ps1 -TeacherIp 10.10.96.42
#>
param(
  [Parameter(Mandatory = $true)][string]$TeacherIp,
  [string]$Serial,
  [int]$Port = 8088
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is very slow with the progress bar on PS 5.1
$ApkName = 'vingt-un.apk'

if ($TeacherIp -notmatch '^[A-Za-z0-9.\-]+$') { throw "-TeacherIp '$TeacherIp' is not a valid address." }
if ($Serial -and $Serial -notmatch '^emulator-\d+$') {
  throw "-Serial '$Serial' is not an emulator serial (emulator-NNNN). Installing on a physical device is not allowed."
}

# ------------------------------------------------------------------------------------------
# adb: PATH, then ANDROID_HOME, then ANDROID_SDK_ROOT
# ------------------------------------------------------------------------------------------
$adb = $null
$cmd = Get-Command adb -ErrorAction SilentlyContinue
if ($cmd) { $adb = $cmd.Source }
if (-not $adb) {
  foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, 'C:\Android\Sdk', (Join-Path ([string]$env:LOCALAPPDATA) 'Android\Sdk'))) {
    if ($sdk) {
      $candidate = Join-Path $sdk 'platform-tools\adb.exe'
      if (Test-Path $candidate) { $adb = $candidate; break }
    }
  }
}
if (-not $adb) { throw 'adb not found (PATH, %ANDROID_HOME%\platform-tools, %ANDROID_SDK_ROOT%\platform-tools). Install the Android SDK platform-tools.' }

function Invoke-Adb([string[]]$adbArgs) {
  # adb writes to stderr; with EAP=Stop, PowerShell 5.1 would turn that into a terminating error.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = & $adb @adbArgs 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}

# ------------------------------------------------------------------------------------------
# Pick the emulator
# ------------------------------------------------------------------------------------------
function Get-RunningEmulators {
  $list = Invoke-Adb @('devices')
  if ($list.Code -ne 0) { throw "adb devices failed: $($list.Text)" }
  $found = @()
  foreach ($line in ($list.Text -split "`n")) {
    if ($line -match '^(emulator-\d+)\s+device\s*$') { $found += $Matches[1] }
  }
  return ,$found
}

function Wait-Boot([string]$serial, [int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    if ((Invoke-Adb @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed')).Text.Trim() -eq '1') { return $true }
    Start-Sleep -Seconds 3
  }
  return $false
}

# No emulator yet: start this machine's Android Virtual Device (a phone one if there is one).
function Start-LocalAvd {
  $sdkRoot = Split-Path -Parent (Split-Path -Parent $adb)
  $emuExe = Join-Path $sdkRoot 'emulator\emulator.exe'
  if (-not (Test-Path $emuExe)) { return $null }
  if (-not $env:ANDROID_AVD_HOME -and (Test-Path 'C:\Android\avd')) { $env:ANDROID_AVD_HOME = 'C:\Android\avd' }
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $avds = @(& $emuExe -list-avds 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^[A-Za-z0-9._-]+$' }) } finally { $ErrorActionPreference = $prev }
  if ($avds.Count -eq 0) { return $null }
  $avd = @($avds | Where-Object { $_ -match 'phone' })[0]
  if (-not $avd) { $avd = $avds[0] }
  Write-Host "No emulator running: starting the AVD '$avd' (the first boot can take 1-2 minutes)..."
  Start-Process -FilePath $emuExe -ArgumentList @('-avd', $avd) | Out-Null
  $deadline = (Get-Date).AddSeconds(240)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    $running = Get-RunningEmulators
    if ($running.Count -gt 0 -and (Wait-Boot $running[0] 4)) { return $running[0] }
  }
  return $null
}

$emulators = Get-RunningEmulators
if ($Serial) {
  if ($emulators -notcontains $Serial) { throw "Emulator $Serial is not running/ready (adb devices). Running emulators: $($emulators -join ', ')" }
  $target = $Serial
} else {
  if ($emulators.Count -eq 0) {
    $started = Start-LocalAvd
    if (-not $started) {
      throw 'No running Android emulator found, and none could be started automatically. Start one from Android Studio > Device Manager and retry. Physical devices are never used.'
    }
    $emulators = @($started)
  }
  $target = $emulators[0]
  if ($emulators.Count -gt 1) { Write-Host "Several emulators running ($($emulators -join ', ')); using $target (choose with -Serial)." }
}
$qemu = (Invoke-Adb @('-s', $target, 'shell', 'getprop', 'ro.kernel.qemu')).Text.Trim()
$bootQemu = (Invoke-Adb @('-s', $target, 'shell', 'getprop', 'ro.boot.qemu')).Text.Trim()
if ($qemu -ne '1' -and $bootQemu -ne '1') {
  throw "$target does not report itself as an emulator (ro.kernel.qemu/ro.boot.qemu != 1); refusing to install."
}
Write-Host "Target emulator: $target"
if (-not (Wait-Boot $target 180)) { throw "$target did not finish booting (sys.boot_completed)." }

# ------------------------------------------------------------------------------------------
# Download
# ------------------------------------------------------------------------------------------
$base = "http://${TeacherIp}:$Port"
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('vingt-un-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$apk = Join-Path $tmpDir $ApkName
try {
  Write-Host "Downloading $base/$ApkName ..."
  try {
    Invoke-WebRequest -Uri "$base/$ApkName" -OutFile $apk -UseBasicParsing -TimeoutSec 300
  } catch {
    throw "Download failed from $base/$ApkName ($($_.Exception.Message)). Check the teacher IP, that tools/start_classroom.ps1 is running, and open $base in a browser."
  }
  $bytes = New-Object byte[] 2
  $fs = [IO.File]::OpenRead($apk)
  try { $n = $fs.Read($bytes, 0, 2) } finally { $fs.Close() }
  if ($n -ne 2 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) { throw 'The downloaded file is not an APK (zip signature missing).' }
  $expected = $null
  try {
    $shaText = (Invoke-WebRequest -Uri "$base/$ApkName.sha256" -UseBasicParsing -TimeoutSec 15).Content
    if ($shaText -is [byte[]]) { $shaText = [Text.Encoding]::ASCII.GetString($shaText) }
    $expected = ([string]$shaText).Trim().Split(' ')[0].ToLowerInvariant()
  } catch {
    Write-Warning 'No checksum published by the teacher server; skipping verification.'
  }
  if ($expected) {
    $actual = (Get-FileHash -Algorithm SHA256 $apk).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw "Checksum mismatch (expected $expected, got $actual)." }
    Write-Host "SHA-256 OK ($actual)"
  }

  # ----------------------------------------------------------------------------------------
  # Install
  # ----------------------------------------------------------------------------------------
  Write-Host "adb -s $target install -r $ApkName"
  $res = Invoke-Adb @('-s', $target, 'install', '-r', $apk)
  Write-Host $res.Text
  if ($res.Code -ne 0 -or $res.Text -notmatch 'Success') { throw "adb install failed (exit $($res.Code))." }
  # Open the app right away.
  $null = Invoke-Adb @('-s', $target, 'shell', 'monkey', '-p', 'dev.ninetynine.vingtun', '-c', 'android.intent.category.LAUNCHER', '1')
  Write-Host ''
  Write-Host "Installed and opened: 'Vingt-Un' in the emulator. Server address: $TeacherIp (screen 'Serveur' if needed)." -ForegroundColor Green
} finally {
  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
