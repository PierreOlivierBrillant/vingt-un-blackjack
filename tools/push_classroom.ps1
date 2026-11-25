<#
.SYNOPSIS
  Teacher machine: pushes the classroom APK onto the students' Android EMULATORS, remotely, in parallel,
  with the current user's rights (PowerShell remoting / WinRM, port 5985). Run it once the students
  have their emulator open (tools\start_classroom.ps1 must be running: the APK is downloaded from its
  page, http://<teacher>:8088, and its SHA-256 is checked on each machine).

  On each machine: finds adb (C:\Android\Sdk or %ANDROID_HOME%), lists the RUNNING emulators
  (emulator-NNNN that report ro.kernel.qemu/ro.boot.qemu = 1; physical devices are never touched),
  installs the APK on each of them and opens the app. It never starts an emulator itself (that would
  run hidden in the remote session): machines without a running emulator are only reported.

  Nothing survives a DeepFreeze reboot: push again (or let students run the one-line install shown on
  the page) after the machines restart.
.PARAMETER ComputerName
  Student machines (DNS names preferred: WinRM's Kerberos authentication needs names; IPv4
  addresses are resolved to names when possible). Default: the names in tools\classroom\hosts.txt
  (one per line, # comments allowed).
.PARAMETER TeacherIp
  Address of this machine as seen by the students (default: the one baked into the published APK).
.PARAMETER WhatIf
  Only report, for each machine: reachable or not, adb found, running emulators. Installs nothing.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\push_classroom.ps1 -WhatIf
  powershell -ExecutionPolicy Bypass -File tools\push_classroom.ps1 -ComputerName LAB-PC01,LAB-PC02
#>
param(
  [string[]]$ComputerName,
  [string]$TeacherIp,
  [int]$Port = 8088,
  [switch]$WhatIf,
  [int]$ThrottleLimit = 24
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$classDir = Join-Path $repoRoot '.classroom'
$apk = Join-Path $classDir 'www\vingt-un.apk'
$hostsFile = Join-Path $PSScriptRoot 'classroom\hosts.txt'

if (-not $ComputerName) {
  if (-not (Test-Path $hostsFile)) {
    throw "No -ComputerName and no $hostsFile (one machine name per line). List the student machines first."
  }
  $ComputerName = @(Get-Content $hostsFile | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
}
if ($ComputerName.Count -eq 0) { throw 'No student machine given.' }

if (-not $TeacherIp) {
  $hostFile = Join-Path $classDir 'apk-host.txt'
  if (Test-Path $hostFile) { $TeacherIp = (Get-Content -Raw $hostFile).Trim() }
}
if (-not $TeacherIp) { throw 'Unknown teacher address: pass -TeacherIp (or start tools\start_classroom.ps1 first).' }
if (-not (Test-Path $apk)) { throw "$apk not found: start tools\start_classroom.ps1 first (it publishes the APK)." }
$sha = (Get-FileHash -Algorithm SHA256 $apk).Hash.ToLowerInvariant()
$url = "http://${TeacherIp}:$Port/vingt-un.apk"
try { $null = Invoke-WebRequest -Uri "http://${TeacherIp}:$Port/" -UseBasicParsing -TimeoutSec 5 } catch {
  throw "The classroom page http://${TeacherIp}:$Port/ does not answer: start tools\start_classroom.ps1 first."
}

# WinRM authenticates with Kerberos by name: turn IPv4 addresses into names when DNS knows them.
$targets = foreach ($c in $ComputerName) {
  $ipObj = $null
  if ([System.Net.IPAddress]::TryParse($c, [ref]$ipObj)) {
    try { [System.Net.Dns]::GetHostEntry($c).HostName } catch { Write-Warning "$c has no DNS name; WinRM may refuse an IP address."; $c }
  } else { $c }
}

$remote = {
  param([string]$Url, [string]$Sha, [bool]$ReportOnly)
  $ErrorActionPreference = 'Stop'
  $result = [ordered]@{ Machine = $env:COMPUTERNAME; Emulators = ''; Status = '' }
  $adb = $null
  foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, 'C:\Android\Sdk')) {
    if ($sdk -and (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { $adb = Join-Path $sdk 'platform-tools\adb.exe'; break }
  }
  if (-not $adb) { $result.Status = 'adb not found (C:\Android\Sdk)'; return [pscustomobject]$result }
  function Adb([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $out = & $adb @a 2>&1 | ForEach-Object { "$_" }
    return ($out -join "`n")
  }
  $emus = @()
  foreach ($line in ((Adb @('devices')) -split "`n")) {
    if ($line -match '^(emulator-\d+)\s+device\s*$') {
      $s = $Matches[1]
      $q1 = (Adb @('-s', $s, 'shell', 'getprop', 'ro.kernel.qemu')).Trim()
      $q2 = (Adb @('-s', $s, 'shell', 'getprop', 'ro.boot.qemu')).Trim()
      if ($q1 -eq '1' -or $q2 -eq '1') { $emus += $s }
    }
  }
  $result.Emulators = $emus -join ','
  if ($emus.Count -eq 0) { $result.Status = 'no emulator running (student: start it, or run the one-line install)'; return [pscustomobject]$result }
  if ($ReportOnly) { $result.Status = 'ready'; return [pscustomobject]$result }
  $tmp = Join-Path $env:TEMP ('vingt-un-' + [guid]::NewGuid().ToString('N') + '.apk')
  try {
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    if ((Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLowerInvariant() -ne $Sha) { $result.Status = 'checksum mismatch: not installed'; return [pscustomobject]$result }
    $ok = @()
    foreach ($s in $emus) {
      $out = Adb @('-s', $s, 'install', '-r', $tmp)
      if ($out -match 'Success') {
        $null = Adb @('-s', $s, 'shell', 'monkey', '-p', 'dev.ninetynine.vingtun', '-c', 'android.intent.category.LAUNCHER', '1')
        $ok += $s
      }
    }
    $result.Status = if ($ok.Count -eq $emus.Count) { 'installed + opened' } else { "installed on $($ok -join ',') only" }
  } catch {
    $result.Status = "error: $($_.Exception.Message)"
  } finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
  return [pscustomobject]$result
}

$mode = if ($WhatIf) { 'report only (-WhatIf): nothing is installed' } else { 'install' }
Write-Host "Pushing $url (sha256 $($sha.Substring(0, 12))...) to $($targets.Count) machine(s), $mode." -ForegroundColor Cyan
$errors = @()
$results = Invoke-Command -ComputerName $targets -ScriptBlock $remote -ArgumentList $url, $sha, ([bool]$WhatIf) `
  -ThrottleLimit $ThrottleLimit -ErrorAction SilentlyContinue -ErrorVariable +errors
$results | Select-Object Machine, Emulators, Status | Sort-Object Machine | Format-Table -AutoSize -Wrap
foreach ($e in $errors) {
  $name = if ($e.TargetObject) { $e.TargetObject } else { $e.OriginInfo.PSComputerName }
  Write-Host "unreachable: $name ($($e.Exception.Message.Split([Environment]::NewLine)[0]))" -ForegroundColor Yellow
}
$installed = @($results | Where-Object { $_.Status -like 'installed*' }).Count
Write-Host "$installed machine(s) installed, $(@($results).Count - $installed) reported without install, $($errors.Count) unreachable." -ForegroundColor Cyan
