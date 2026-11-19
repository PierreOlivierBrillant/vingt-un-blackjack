<#
.SYNOPSIS
  Asks a running tools\start_classroom.ps1 to stop cleanly (same path as Ctrl+C: the emulator data
  is exported to the persistence directory, then the emulators, the simulation loop and the
  download page server are stopped). Useful when the server runs in another window or in the
  background. Waits until the ports are free (or -TimeoutSeconds).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\stop_classroom.ps1
#>
param([int]$TimeoutSeconds = 180)
. "$PSScriptRoot\_backend_env.ps1"

$classDir = Join-Path $RepoRoot '.classroom'
New-Item -ItemType Directory -Force -Path $classDir | Out-Null
$stopFile = Join-Path $classDir 'stop-request'
Set-Content -Path $stopFile -Value (Get-Date -Format o)
Write-Host 'Stop requested; waiting for the classroom server to export its data and exit...'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  $busy = @(9099, 8080, 5001, 8088 | Where-Object { Test-PortBusy $_ })
  if ($busy.Count -eq 0 -and -not (Test-Path $stopFile)) { Write-Host 'Classroom server stopped.' -ForegroundColor Green; exit 0 }
}
Write-Host "Still running after $TimeoutSeconds s (ports busy or stop not acknowledged)." -ForegroundColor Yellow
exit 1
