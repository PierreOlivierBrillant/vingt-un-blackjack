<#
.SYNOPSIS
  Seeds the running emulators with fake data: ~60 bot profiles (stats, leaderboard, weekly points),
  bot friendships, and the 8 permanent simulated tables with a short hand history.
  Skips when already seeded unless -Force.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/seed.ps1
#>
param(
  [switch]$Force,
  [string]$EmulatorHost = '127.0.0.1'
)
. "$PSScriptRoot\_backend_env.ps1"
Use-EmulatorEnv $EmulatorHost
if (-not (Test-PortBusy 8080)) { throw 'Firestore emulator not reachable on :8080 - start tools/run_emulators.ps1 first.' }
Initialize-Functions
$nodeArgs = @((Join-Path $FunctionsDir 'lib\sim\seed.js'))
if ($Force) { $nodeArgs += '--force' }
Invoke-Checked 'seed' { node @nodeArgs }
