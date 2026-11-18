<#
.SYNOPSIS
  Runs every test of the project.
  BACKEND section (firebase/functions): typecheck (tsc --noEmit), lint (eslint), unit tests
  (engine, golden transcripts, Monte-Carlo house edge, LMSR, table state machine), Firestore rules
  tests (emulators:exec --only firestore) and emulator integration tests
  (emulators:exec --only auth,firestore,functions).
  FLUTTER section: delegated to tools/test_flutter.ps1 when present (owned by the app).
  The emulators must NOT already be running (tests start their own, on the standard ports).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/test_all.ps1            # everything
  powershell -ExecutionPolicy Bypass -File tools/test_all.ps1 -BackendOnly
#>
param(
  [switch]$BackendOnly,
  [switch]$SkipIntegration
)
. "$PSScriptRoot\_backend_env.ps1"
$results = [ordered]@{}

function Step([string]$name, [scriptblock]$block) {
  Write-Host "`n==> $name" -ForegroundColor Cyan
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $block
  $ok = ($LASTEXITCODE -eq 0)
  $results[$name] = if ($ok) { "PASS ($([int]$sw.Elapsed.TotalSeconds)s)" } else { "FAIL (exit $LASTEXITCODE)" }
  if (-not $ok) { Write-Host "$name FAILED" -ForegroundColor Red }
}

# ------------------------------------------------------------------------------------------
# BACKEND
# ------------------------------------------------------------------------------------------
foreach ($p in 9099, 8080, 5001) {
  if (Test-PortBusy $p) { throw "Port $p is in use: stop the running emulators before tools/test_all.ps1." }
}
Initialize-Functions
Step 'backend: typecheck' { npm --prefix $FunctionsDir run typecheck --silent }
Step 'backend: lint' { npm --prefix $FunctionsDir run lint --silent }
Step 'backend: unit tests' { npm --prefix $FunctionsDir run test:unit --silent }
Push-Location $FirebaseDir
try {
  Step 'backend: firestore rules tests' {
    firebase emulators:exec --project $ProjectId --only firestore "npm --prefix functions run test:rules --silent"
  }
  if (-not $SkipIntegration) {
    Step 'backend: emulator integration tests' {
      firebase emulators:exec --project $ProjectId --only auth,firestore,functions "npm --prefix functions run test:integration --silent"
    }
  }
} finally { Pop-Location }

# ------------------------------------------------------------------------------------------
# FLUTTER (owned by the app; runs if the app provides its script)
# ------------------------------------------------------------------------------------------
if (-not $BackendOnly) {
  $flutterScript = Join-Path $PSScriptRoot 'test_flutter.ps1'
  if (Test-Path $flutterScript) {
    Step 'flutter: tests' { & $flutterScript }
  } else {
    $results['flutter: tests'] = 'SKIPPED (tools/test_flutter.ps1 not found)'
  }
}

Write-Host "`n===== SUMMARY =====" -ForegroundColor Cyan
$failed = $false
foreach ($k in $results.Keys) {
  $v = $results[$k]
  $color = if ($v -like 'PASS*') { 'Green' } elseif ($v -like 'SKIP*') { 'Yellow' } else { 'Red' }
  if ($v -like 'FAIL*') { $failed = $true }
  Write-Host ("{0,-45} {1}" -f $k, $v) -ForegroundColor $color
}
if ($failed) { exit 1 } else { exit 0 }
