<#
  Flutter client checks: ARB merge + l10n generation, static analysis, unit + widget +
  golden tests. Exit code is non-zero on the first failure.

    pwsh app/tool/test.ps1                 # everything
    pwsh app/tool/test.ps1 -UpdateGoldens  # after an intended UI change
    pwsh app/tool/test.ps1 -SkipGoldens    # e.g. on another OS / SDK

  Note: impellerc (shader compiler used by `flutter test` and builds) cannot
  write paths longer than 260 characters on Windows. If the checkout lives
  in a very deep directory, run from a shorter path.
#>
param(
  [switch]$UpdateGoldens,
  [switch]$SkipGoldens
)
$ErrorActionPreference = 'Stop'
$app = Split-Path -Parent $PSScriptRoot
Push-Location $app
try {
  function Step($name, [scriptblock]$cmd) {
    Write-Host "==> $name" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
  }
  Step 'pub get' { flutter pub get }
  # The ARB files read by gen-l10n are generated from l10n/parts/*.arb (see tool/merge_arb.dart).
  Step 'merge ARB' { dart run tool/merge_arb.dart }
  Step 'gen-l10n' { flutter gen-l10n }
  Step 'analyze' { flutter analyze }
  $testArgs = @('test')
  if ($UpdateGoldens) { $testArgs += '--update-goldens' }
  if ($SkipGoldens) { $testArgs += @('--exclude-tags', 'golden') }
  Step 'test' { flutter @testArgs }
  Write-Host 'All Flutter checks passed.' -ForegroundColor Green
}
finally {
  Pop-Location
}
