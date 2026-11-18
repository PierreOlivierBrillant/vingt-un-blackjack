<#
.SYNOPSIS
  Builds the functions and starts the Firebase emulators (Auth 9099, Firestore 8080, Functions 5001
  on 0.0.0.0; Emulator UI 4000 and hub on 127.0.0.1) for project demo-blackjack.
  Data persists between runs in firebase/.emulator-data (--import / --export-on-exit).
.PARAMETER Fresh
  Start from an empty database (does not import; the previous data is still overwritten on exit).
.PARAMETER DataDir
  Persistence directory (default firebase/.emulator-data).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/run_emulators.ps1
#>
param(
  [switch]$Fresh,
  [string]$DataDir
)
. "$PSScriptRoot\_backend_env.ps1"
if (-not $DataDir) { $DataDir = Join-Path $FirebaseDir '.emulator-data' }

foreach ($p in 9099, 8080, 5001, 4000) {
  if (Test-PortBusy $p) { throw "Port $p is already in use (emulators already running?)." }
}
Initialize-Functions

$fbArgs = @('emulators:start', '--project', $ProjectId, '--export-on-exit', $DataDir)
if (-not $Fresh -and (Test-Path (Join-Path $DataDir 'firebase-export-metadata.json'))) {
  $fbArgs += @('--import', $DataDir)
  Write-Host "Importing emulator data from $DataDir"
}
Write-Host 'Emulators: Auth :9099, Firestore :8080, Functions :5001 (all interfaces); UI http://127.0.0.1:4000'
Write-Host 'Stop with Ctrl+C (data is exported on exit).'
Push-Location $FirebaseDir
try { firebase @fbArgs } finally { Pop-Location }
