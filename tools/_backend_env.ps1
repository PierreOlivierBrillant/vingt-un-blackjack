# Shared helpers for the backend scripts (dot-source me). Never changes system settings.
$ErrorActionPreference = 'Stop'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:FirebaseDir = Join-Path $RepoRoot 'firebase'
$script:FunctionsDir = Join-Path $FirebaseDir 'functions'
$script:ProjectId = 'demo-blackjack'

# Java 21 on Windows opens NIO selectors through AF_UNIX sockets created in the user temp dir;
# on some profiles that fails ("Unable to establish loopback connection") and the Firestore
# emulator dies at start. Point only the emulator JVMs at the system temp dir (process-local env var).
if (-not $env:JAVA_TOOL_OPTIONS -or $env:JAVA_TOOL_OPTIONS -notmatch 'unixdomain') {
  $udsDir = Join-Path $env:SystemRoot 'Temp'
  $env:JAVA_TOOL_OPTIONS = "$($env:JAVA_TOOL_OPTIONS) -Djdk.net.unixdomain.tmpdir=$udsDir".Trim()
}

function Invoke-Checked([string]$what, [scriptblock]$block) {
  Write-Host "==> $what" -ForegroundColor Cyan
  & $block
  if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

function Initialize-Functions([switch]$SkipBuild) {
  if (-not (Test-Path (Join-Path $FunctionsDir 'node_modules'))) {
    Invoke-Checked 'npm install (functions)' { npm --prefix $FunctionsDir install --no-fund --no-audit }
  }
  if (-not $SkipBuild) {
    Invoke-Checked 'build functions (tsc)' { npm --prefix $FunctionsDir run build --silent }
  }
}

function Test-PortBusy([int]$port) {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(300) -and $c.Connected
    $c.Close()
    return $ok
  } catch { return $false }
}

function Use-EmulatorEnv([string]$HostName = '127.0.0.1') {
  $env:FIRESTORE_EMULATOR_HOST = "${HostName}:8080"
  $env:FIREBASE_AUTH_EMULATOR_HOST = "${HostName}:9099"
  $env:GCLOUD_PROJECT = $ProjectId
}
