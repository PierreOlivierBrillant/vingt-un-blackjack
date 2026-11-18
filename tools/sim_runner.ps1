<#
.SYNOPSIS
  Runs the simulation loop against the running emulators: ticks every table's deadlines (bots play,
  timeouts, new hands), keeps the 8 simulated tables alive, makes bots trade on spectator markets,
  pays interrupted market payouts, completes due KYC reviews, accepts friend requests sent to bots.
  Seeds automatically if the database is empty. Ctrl+C to stop.
.PARAMETER DurationSec
  Stop after this many seconds (default: run until Ctrl+C).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/sim_runner.ps1
#>
param(
  [int]$DurationSec = 0,
  [int]$TickMs = 500,
  [string]$EmulatorHost = '127.0.0.1'
)
. "$PSScriptRoot\_backend_env.ps1"
Use-EmulatorEnv $EmulatorHost
if (-not (Test-PortBusy 8080)) { throw 'Firestore emulator not reachable on :8080 - start tools/run_emulators.ps1 first.' }
Initialize-Functions
$nodeArgs = @((Join-Path $FunctionsDir 'lib\sim\runner.js'), "--tick=$TickMs")
if ($DurationSec -gt 0) { $nodeArgs += "--duration=$($DurationSec * 1000)" }
node @nodeArgs
