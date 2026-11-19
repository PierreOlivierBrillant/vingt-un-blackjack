<#
.SYNOPSIS
  Flutter checks, called without arguments by tools/test_all.ps1.
  Delegates to app/tool/test.ps1 (pub get, gen-l10n, analyze, unit/widget/golden tests) in a child
  PowerShell and propagates its exit code.
  -Integration also runs "flutter test integration_test -d <emulator>" when app/integration_test
  exists (skipped with a message otherwise). Only an Android EMULATOR is ever targeted.
.PARAMETER Integration
  Also run the integration tests on a running Android emulator.
.PARAMETER Device
  Flutter device id for -Integration (must be emulator-NNNN). Default: first running emulator.
.PARAMETER SkipGoldens
  Passed to app/tool/test.ps1 (excludes the "golden" tag).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\test_flutter.ps1
  powershell -ExecutionPolicy Bypass -File tools\test_flutter.ps1 -Integration -Device emulator-5554
#>
param(
  [switch]$Integration,
  [string]$Device,
  [switch]$SkipGoldens
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'app'
$appTest = Join-Path $appDir 'tool\test.ps1'
if (-not (Test-Path $appTest)) { Write-Host "app/tool/test.ps1 not found" -ForegroundColor Red; exit 1 }

# Child process: app/tool/test.ps1 throws on failure; a separate process turns that into an exit code
# instead of aborting the caller (tools/test_all.ps1 reads $LASTEXITCODE).
$psExe = (Get-Process -Id $PID).Path
$childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appTest)
if ($SkipGoldens) { $childArgs += '-SkipGoldens' }
& $psExe @childArgs
$code = $LASTEXITCODE
if ($code -ne 0) { exit $code }
if (-not $Integration) { exit 0 }

# ------------------------------------------------------------------------------------------
# Integration tests on the emulator
# ------------------------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $appDir 'integration_test'))) {
  Write-Host 'Integration tests SKIPPED: app/integration_test does not exist yet.' -ForegroundColor Yellow
  exit 0
}
if ($Device) {
  if ($Device -notmatch '^emulator-\d+$') {
    Write-Host "-Device '$Device' is not an emulator (emulator-NNNN); physical devices are never used." -ForegroundColor Red
    exit 1
  }
} else {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $json = (& flutter devices --machine 2>$null | Out-String) } finally { $ErrorActionPreference = $prev }
  $devices = @()
  try {
    $start = $json.IndexOf('[')
    if ($start -ge 0) { $devices = @($json.Substring($start) | ConvertFrom-Json) }
  } catch { $devices = @() }
  $emu = @($devices | Where-Object { $_.emulator -eq $true -and [string]$_.targetPlatform -like 'android*' -and [string]$_.id -match '^emulator-\d+$' })
  if ($emu.Count -eq 0) {
    Write-Host 'No running Android emulator found for the integration tests (flutter devices). Start the AVD first.' -ForegroundColor Red
    exit 1
  }
  $Device = [string]$emu[0].id
}

Write-Host "==> flutter test integration_test -d $Device" -ForegroundColor Cyan
$savedJto = $env:JAVA_TOOL_OPTIONS
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\nonexistent-afunix-dir' # Gradle on Java 21 (see REPRISE.md)
Push-Location $appDir
try {
  & flutter test integration_test -d $Device
  $code = $LASTEXITCODE
} finally {
  Pop-Location
  $env:JAVA_TOOL_OPTIONS = $savedJto
}
exit $code
