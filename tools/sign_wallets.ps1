<#
.SYNOPSIS
  One-off backfill: (re)signs every wallet document with the server signing key. Run this once on a
  database that was created BEFORE wallet signatures existed (persisted .emulator-data), otherwise
  those wallets are rejected with WALLET_INTEGRITY. A fresh database does not need it.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/sign_wallets.ps1
#>
param(
  [string]$EmulatorHost = '127.0.0.1'
)
. "$PSScriptRoot\_backend_env.ps1"
Use-EmulatorEnv $EmulatorHost
if (-not (Test-PortBusy 8080)) { throw 'Firestore emulator not reachable on :8080 - start tools/run_emulators.ps1 first.' }
Initialize-Functions
Invoke-Checked 'sign_wallets' { node (Join-Path $FunctionsDir 'lib\sim\signWallets.js') }
