<#
.SYNOPSIS
  Runs the simulation loop against the running emulators: follows every open table of both
  collections (blackjack `tables`, kernel games `gameTables`) and applies their deadlines (bots play,
  timeouts, new rounds), keeps the 8 blackjack simulated tables and N simulated tables per available
  kernel game alive, makes bots trade on spectator markets, pays interrupted market payouts,
  completes due KYC reviews, accepts friend requests sent to bots, runs the Rendez-vous bots' tasks.
  Seeds automatically if the database is empty (and adds the Sprint 2 bots / game tables if missing).
  Ctrl+C to stop.
.PARAMETER DurationSec
  Stop after this many seconds (default: run until Ctrl+C).
.PARAMETER GameTablesPerGame
  Simulated tables per kernel game, 0..8 (default: $env:SIM_GAME_TABLES, else 2). Lower it on a weak machine.
.PARAMETER LoadProbe
  Instead of running the world: measure the runner's tick duration (p50/p95/p99) with the 8 blackjack
  tables plus GameTablesPerGame tables per game played by the test-only modules, for DurationSec (default 60 s).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/sim_runner.ps1
  powershell -ExecutionPolicy Bypass -File tools/sim_runner.ps1 -GameTablesPerGame 1
  powershell -ExecutionPolicy Bypass -File tools/sim_runner.ps1 -LoadProbe -DurationSec 120
#>
param(
  [int]$DurationSec = 0,
  [int]$TickMs = 500,
  [int]$GameTablesPerGame = -1,
  [switch]$LoadProbe,
  [string]$EmulatorHost = '127.0.0.1'
)
. "$PSScriptRoot\_backend_env.ps1"
Use-EmulatorEnv $EmulatorHost
if (-not (Test-PortBusy 8080)) { throw 'Firestore emulator not reachable on :8080 - start tools/run_emulators.ps1 first.' }
Initialize-Functions
if ($LoadProbe) {
  $sec = if ($DurationSec -gt 0) { $DurationSec } else { 60 }
  $n = if ($GameTablesPerGame -ge 0) { $GameTablesPerGame } else { 2 }
  node (Join-Path $FunctionsDir 'lib\sim\loadProbe.js') "--duration=$($sec * 1000)" "--game-tables=$n" "--tick=$TickMs"
  exit $LASTEXITCODE
}
$nodeArgs = @((Join-Path $FunctionsDir 'lib\sim\runner.js'), "--tick=$TickMs")
if ($DurationSec -gt 0) { $nodeArgs += "--duration=$($DurationSec * 1000)" }
if ($GameTablesPerGame -ge 0) { $nodeArgs += "--game-tables=$GameTablesPerGame" }
node @nodeArgs
