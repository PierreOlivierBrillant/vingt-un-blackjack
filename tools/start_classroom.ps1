<#
.SYNOPSIS
  Teacher machine: runs the whole classroom server on the local network.
  1. Detects the LAN IPv4 (interface holding the default gateway; -HostIp to force).
  2. Builds the debug APK with --dart-define=BACKEND_HOST=<IP> (-SkipBuild reuses an existing APK).
  3. Starts the Firebase emulators (Auth 9099, Firestore 8080, Functions 5001 on 0.0.0.0) with
     persistence (--import / --export-on-exit, default firebase/.emulator-data, shared with
     tools/run_emulators.ps1) plus a periodic autosave.
  4. Seeds the database if it is empty (seed is a no-op when already seeded).
  5. Runs the simulation loop (same entry point as tools/sim_runner.ps1).
  6. Serves the APK + a French instructions page on http://<IP>:8088 (tools/classroom/static_server.js,
     no dependency, serves only .classroom/www).
  7. Checks the Windows firewall and, if the ports look blocked, PRINTS the New-NetFirewallRule
     command to run as administrator. It never changes the firewall itself.
  Ctrl+C stops everything (emulator data is exported on exit). Logs: .classroom/logs.
.PARAMETER HostIp
  IPv4 to advertise / bake into the APK instead of the detected one.
.PARAMETER SkipBuild
  Do not build: reuse .classroom/www/vingt-un.apk, else app/build/app/outputs/flutter-apk/app-debug.apk.
.PARAMETER Fresh
  Start from an empty database (no import; the previous data is overwritten on exit).
.PARAMETER DataDir
  Emulator persistence directory (default firebase/.emulator-data).
.PARAMETER AutosaveMinutes
  Export the emulator data every N minutes while running (0 disables; default 5).
.PARAMETER WebPort
  Port of the download page (default 8088).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\start_classroom.ps1
  powershell -ExecutionPolicy Bypass -File tools\start_classroom.ps1 -HostIp 10.10.96.42 -SkipBuild
#>
param(
  [string]$HostIp,
  [switch]$SkipBuild,
  [switch]$Fresh,
  [string]$DataDir,
  [int]$AutosaveMinutes = 5,
  [int]$WebPort = 8088,
  [int]$TickMs = 500
)
. "$PSScriptRoot\_backend_env.ps1"

$AppDir = Join-Path $RepoRoot 'app'
$ClassDir = Join-Path $RepoRoot '.classroom'
$WwwDir = Join-Path $ClassDir 'www'
$LogDir = Join-Path $ClassDir 'logs'
$HostFile = Join-Path $ClassDir 'apk-host.txt'
$ApkName = 'vingt-un.apk'
$PublishedApk = Join-Path $WwwDir $ApkName
$BuiltApk = Join-Path $AppDir 'build\app\outputs\flutter-apk\app-debug.apk'
$ServerJs = Join-Path $PSScriptRoot 'classroom\static_server.js'
$TemplateHtml = Join-Path $PSScriptRoot 'classroom\index.template.html'
$GradleJavaToolOptions = '-Djdk.net.unixdomain.tmpdir=C:\nonexistent-afunix-dir'
$ClassroomPorts = @(9099, 8080, 5001, $WebPort)
if (-not $DataDir) { $DataDir = Join-Path $FirebaseDir '.emulator-data' }
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------
function Write-Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }

function ConvertTo-ArgString([string[]]$items) {
  # Start-Process joins arguments with spaces and does not quote them (PowerShell 5.1).
  $quoted = foreach ($a in $items) {
    if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
  }
  return ($quoted -join ' ')
}

function Get-LanIPv4 {
  # Interface holding the IPv4 default route with the lowest metric.
  try {
    $routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })
    $ranked = foreach ($r in $routes) {
      $ifm = 0
      try { $ifm = (Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric } catch { }
      [pscustomobject]@{ Route = $r; Metric = [int]$r.RouteMetric + [int]$ifm }
    }
    foreach ($x in ($ranked | Sort-Object Metric)) {
      $addr = Get-NetIPAddress -InterfaceIndex $x.Route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        Select-Object -First 1
      if ($addr) {
        return [pscustomobject]@{
          Ip = $addr.IPAddress; IfIndex = $x.Route.ifIndex
          Alias = $x.Route.InterfaceAlias; Gateway = $x.Route.NextHop
        }
      }
    }
  } catch { }
  # Fallback without the NetTCPIP module: a connected UDP socket reveals the outgoing address
  # (connect() on UDP sends no packet).
  try {
    $s = New-Object System.Net.Sockets.Socket ([System.Net.Sockets.AddressFamily]::InterNetwork),
      ([System.Net.Sockets.SocketType]::Dgram), ([System.Net.Sockets.ProtocolType]::Udp)
    $s.Connect('192.0.2.1', 9)
    $ip = $s.LocalEndPoint.Address.ToString()
    $s.Close()
    if ($ip -and $ip -ne '0.0.0.0') {
      return [pscustomobject]@{ Ip = $ip; IfIndex = $null; Alias = '?'; Gateway = '?' }
    }
  } catch { }
  return $null
}

function Get-ActiveFirewallProfile($ifIndex) {
  try {
    $p = if ($ifIndex) { Get-NetConnectionProfile -InterfaceIndex $ifIndex -ErrorAction Stop } else { Get-NetConnectionProfile -ErrorAction Stop | Select-Object -First 1 }
    switch ([string]$p.NetworkCategory) {
      'DomainAuthenticated' { return 'Domain' }
      'Private' { return 'Private' }
      default { return 'Public' }
    }
  } catch { return $null }
}

# Read-only firewall inspection. Returns @{ State = 'open'|'blocked'|'unknown'; Missing = ports; Notes = strings }.
function Test-ClassroomFirewall([string]$profileName, [int[]]$ports) {
  $notes = New-Object System.Collections.ArrayList
  if (-not $profileName) { return @{ State = 'unknown'; Missing = $ports; Notes = @('network profile unknown') } }
  try {
    $fwp = Get-NetFirewallProfile -Name $profileName -PolicyStore ActiveStore -ErrorAction Stop
    if (-not $fwp.Enabled) { return @{ State = 'open'; Missing = @(); Notes = @("firewall disabled for the $profileName profile") } }
    if ([string]$fwp.DefaultInboundAction -eq 'Allow') { return @{ State = 'open'; Missing = @(); Notes = @('inbound allowed by default') } }
    if ([string]$fwp.AllowLocalFirewallRules -eq 'False') {
      [void]$notes.Add('a group policy ignores local firewall rules: a rule added on this machine will have no effect (ask the IT team)')
    }
    $rules = @(Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -PolicyStore ActiveStore -ErrorAction Stop |
        Where-Object { $_.Profile -eq 'Any' -or ([string]$_.Profile) -match $profileName })
    # Bulk queries (one CIM call each) joined on InstanceID = rule Name; per-rule piping is very slow.
    $portFilters = @{}
    # Without elevation some filters are unreadable ("access denied", non-terminating): keep the rest.
    $fwErr = @()
    foreach ($f in @(Get-NetFirewallPortFilter -All -PolicyStore ActiveStore -ErrorAction SilentlyContinue -ErrorVariable +fwErr)) { $portFilters[[string]$f.InstanceID] = $f }
    $appFilters = @{}
    foreach ($f in @(Get-NetFirewallApplicationFilter -All -PolicyStore ActiveStore -ErrorAction SilentlyContinue -ErrorVariable +fwErr)) { $appFilters[[string]$f.InstanceID] = $f }
    if ($portFilters.Count -eq 0) { return @{ State = 'unknown'; Missing = $ports; Notes = @('cannot read the firewall port filters (not elevated)') } }
    if ($fwErr.Count -gt 0) { [void]$notes.Add('some firewall rules could not be read without elevation; the result is a best guess') }
    $covered = @{}
    foreach ($r in $rules) {
      $pf = $portFilters[[string]$r.Name]
      if (-not $pf) { continue }
      if (@('TCP', 'Any') -notcontains [string]$pf.Protocol) { continue }
      $localPorts = @($pf.LocalPort | ForEach-Object { [string]$_ })
      if ($localPorts -contains 'Any') {
        $af = $appFilters[[string]$r.Name]
        $prog = if ($af) { [string]$af.Program } else { 'Any' }
        # Port=Any/Program=Any rules are nearly always scoped to a Store package or a service:
        # not counted (worst case the advisory command is printed for nothing).
        if ($prog -match '\\node\.exe$') { foreach ($p in $ports) { if ($p -ne 8080) { $covered[$p] = $true } } }
        elseif ($prog -match '\\java(w)?\.exe$') { $covered[8080] = $true }
        continue
      }
      foreach ($lp in $localPorts) {
        foreach ($p in $ports) {
          if ($lp -eq [string]$p) { $covered[$p] = $true }
          elseif ($lp -match '^(\d+)-(\d+)$' -and $p -ge [int]$Matches[1] -and $p -le [int]$Matches[2]) { $covered[$p] = $true }
        }
      }
    }
    $missing = @($ports | Where-Object { -not $covered.ContainsKey($_) })
    $state = if ($missing.Count -eq 0) { 'open' } else { 'blocked' }
    return @{ State = $state; Missing = $missing; Notes = $notes }
  } catch {
    return @{ State = 'unknown'; Missing = $ports; Notes = @("cannot read the firewall configuration: $($_.Exception.Message)") }
  }
}

function Start-Child([string]$name, [string]$exe, [string[]]$argList, [string]$workDir) {
  $out = Join-Path $LogDir "$name.log"
  $err = Join-Path $LogDir "$name.err.log"
  $p = Start-Process -FilePath $exe -ArgumentList (ConvertTo-ArgString $argList) -WorkingDirectory $workDir `
    -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $null = $p.Handle # keeps ExitCode readable after exit
  $script:Children += [pscustomobject]@{ Name = $name; Process = $p; Log = $out }
  return $p
}

function Stop-Tree($proc) {
  if ($proc -and -not $proc.HasExited) {
    try {
      Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($proc.Id) /T /F" -NoNewWindow -Wait `
        -RedirectStandardOutput (Join-Path $LogDir 'taskkill.log') -RedirectStandardError (Join-Path $LogDir 'taskkill.err.log')
    } catch { }
  }
}

function Test-Hub {
  try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:4400/emulators' -TimeoutSec 2 -UseBasicParsing
    $names = @($r.PSObject.Properties.Name)
    return (($names -contains 'auth') -and ($names -contains 'firestore') -and ($names -contains 'functions'))
  } catch { return $false }
}

function Invoke-Export {
  # Exports the running emulators' data to $DataDir (used by autosave and by a non-Ctrl+C stop).
  $p = Start-Process -FilePath $script:FbExe -ArgumentList (ConvertTo-ArgString ($script:FbPrefix + @('emulators:export', $DataDir, '--force', '--project', $ProjectId))) `
    -WorkingDirectory $FirebaseDir -NoNewWindow -PassThru -Wait `
    -RedirectStandardOutput (Join-Path $LogDir 'export.log') -RedirectStandardError (Join-Path $LogDir 'export.err.log')
  return ($p.ExitCode -eq 0)
}

# ------------------------------------------------------------------------------------------
# 1. IP and preconditions
# ------------------------------------------------------------------------------------------
$lan = Get-LanIPv4
if ($HostIp) {
  $parsed = $null
  if (-not [System.Net.IPAddress]::TryParse($HostIp, [ref]$parsed) -or
      $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw "-HostIp '$HostIp' is not an IPv4 address."
  }
  $ip = $parsed.ToString()
  $ifIndex = $null
  try {
    $own = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $ip -ErrorAction Stop | Select-Object -First 1
    $ifIndex = $own.InterfaceIndex
  } catch { Write-Warning "$ip is not assigned to this machine; students will not reach the server through it." }
} else {
  if (-not $lan) { throw 'Could not detect the LAN IPv4 address (no default gateway?). Pass -HostIp.' }
  $ip = $lan.Ip
  $ifIndex = $lan.IfIndex
  Write-Host "LAN address: $ip (interface '$($lan.Alias)', gateway $($lan.Gateway))"
}

foreach ($p in 9099, 8080, 5001, 4000, 4400, 4500, $WebPort) {
  if (Test-PortBusy $p) { throw "Port $p is already in use (emulators or a previous classroom server still running?)." }
}
foreach ($t in 'node', 'flutter') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "'$t' not found in PATH." }
}
# Run the Firebase CLI through node directly: Ctrl+C then reaches it without cmd.exe's
# "Terminate batch job (Y/N)?" prompt, and the export-on-exit can complete.
$fbCmd = Get-Command firebase.cmd -ErrorAction SilentlyContinue
if (-not $fbCmd) { $fbCmd = Get-Command firebase -ErrorAction SilentlyContinue }
if (-not $fbCmd) { throw "Firebase CLI not found in PATH (npm install -g firebase-tools)." }
$fbJs = Join-Path (Split-Path -Parent $fbCmd.Source) 'node_modules\firebase-tools\lib\bin\firebase.js'
if (Test-Path $fbJs) {
  $script:FbExe = (Get-Command node).Source
  $script:FbPrefix = @($fbJs)
} else {
  $script:FbExe = $env:ComSpec
  $script:FbPrefix = @('/c', $fbCmd.Source)
}

New-Item -ItemType Directory -Force -Path $WwwDir, $LogDir | Out-Null
$script:Children = @()
$interrupted = $false
$savedJavaToolOptions = $env:JAVA_TOOL_OPTIONS

try {
  # ----------------------------------------------------------------------------------------
  # 2. APK
  # ----------------------------------------------------------------------------------------
  if (-not $SkipBuild) {
    Write-Step "flutter build apk --debug (BACKEND_HOST=$ip)"
    $env:JAVA_TOOL_OPTIONS = $GradleJavaToolOptions
    Push-Location $AppDir
    try {
      & flutter build apk --debug "--dart-define=BACKEND_HOST=$ip"
      if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed (exit $LASTEXITCODE)" }
    } finally {
      Pop-Location
      $env:JAVA_TOOL_OPTIONS = $savedJavaToolOptions
    }
    Copy-Item -Force $BuiltApk $PublishedApk
    [IO.File]::WriteAllText($HostFile, $ip, $Utf8NoBom)
  } else {
    if (Test-Path $PublishedApk) {
      $bakedHost = if (Test-Path $HostFile) { (Get-Content -Raw $HostFile).Trim() } else { $null }
    } elseif (Test-Path $BuiltApk) {
      Copy-Item -Force $BuiltApk $PublishedApk
      $bakedHost = $null
      if (Test-Path $HostFile) { Remove-Item -Force $HostFile }
    } else {
      throw "-SkipBuild: no APK found ($PublishedApk or $BuiltApk). Run once without -SkipBuild."
    }
    if (-not $bakedHost) {
      Write-Warning "Reused APK: unknown baked BACKEND_HOST. Students may have to type $ip on the 'Serveur' screen."
    } elseif ($bakedHost -ne $ip) {
      Write-Warning "Reused APK was built for $bakedHost, not $ip. Rebuild (no -SkipBuild) or have students type $ip on the 'Serveur' screen."
    } else {
      Write-Host "Reusing APK built for $ip"
    }
  }

  # Download page
  $apkItem = Get-Item $PublishedApk
  $sha = (Get-FileHash -Algorithm SHA256 $PublishedApk).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText((Join-Path $WwwDir "$ApkName.sha256"), "$sha  $ApkName`n", $Utf8NoBom)
  $html = [IO.File]::ReadAllText($TemplateHtml, [Text.Encoding]::UTF8)
  $sizeText = '{0:N1} Mo' -f ($apkItem.Length / 1MB)
  $html = $html.Replace('{{HOST}}', $ip).Replace('{{APK}}', $ApkName).Replace('{{SHA256}}', $sha).
    Replace('{{SIZE}}', $sizeText).Replace('{{DATE}}', $apkItem.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))
  [IO.File]::WriteAllText((Join-Path $WwwDir 'index.html'), $html, $Utf8NoBom)

  # ----------------------------------------------------------------------------------------
  # 3. Emulators
  # ----------------------------------------------------------------------------------------
  Initialize-Functions
  $fbArgs = @('emulators:start', '--project', $ProjectId, '--export-on-exit', $DataDir)
  if (-not $Fresh -and (Test-Path (Join-Path $DataDir 'firebase-export-metadata.json'))) {
    $fbArgs += @('--import', $DataDir)
    Write-Host "Importing emulator data from $DataDir"
  }
  Write-Step 'starting Firebase emulators'
  $emu = Start-Child 'emulators' $script:FbExe ($script:FbPrefix + $fbArgs) $FirebaseDir
  $deadline = (Get-Date).AddSeconds(180)
  while (-not (Test-Hub)) {
    if ($emu.HasExited) { throw "Firebase emulators exited (code $($emu.ExitCode)); see $LogDir\emulators*.log" }
    if ((Get-Date) -gt $deadline) { throw "Emulators not ready after 180 s; see $LogDir\emulators*.log" }
    Start-Sleep -Milliseconds 1000
  }
  foreach ($p in 9099, 8080, 5001) {
    if (-not (Test-PortBusy $p)) { throw "Emulator port $p is not listening; see $LogDir\emulators*.log" }
  }

  # ----------------------------------------------------------------------------------------
  # 4-5. Seed (no-op if already seeded) and simulation loop
  # ----------------------------------------------------------------------------------------
  Use-EmulatorEnv '127.0.0.1'
  Invoke-Checked 'seed (skipped if the database is not empty)' { node (Join-Path $FunctionsDir 'lib\sim\seed.js') }
  Write-Step 'starting the simulation loop'
  $sim = Start-Child 'sim_runner' (Get-Command node).Source @((Join-Path $FunctionsDir 'lib\sim\runner.js'), "--tick=$TickMs") $RepoRoot

  # ----------------------------------------------------------------------------------------
  # 6. Download page server
  # ----------------------------------------------------------------------------------------
  Write-Step "serving $WwwDir on port $WebPort"
  $web = Start-Child 'static_server' (Get-Command node).Source @($ServerJs, '--root', $WwwDir, '--port', "$WebPort", '--host', '0.0.0.0') $RepoRoot
  $ok = $false
  for ($i = 0; $i -lt 20 -and -not $ok; $i++) {
    Start-Sleep -Milliseconds 250
    try { $ok = ((Invoke-WebRequest -Uri "http://127.0.0.1:$WebPort/" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { }
  }
  if (-not $ok) { throw "Download page server did not start; see $LogDir\static_server*.log" }

  # ----------------------------------------------------------------------------------------
  # 7. Firewall (read-only check; never modified here)
  # ----------------------------------------------------------------------------------------
  Write-Step 'checking the Windows firewall (read-only)'
  $profileName = Get-ActiveFirewallProfile $ifIndex
  $fw = Test-ClassroomFirewall $profileName $ClassroomPorts
  if ($fw.State -ne 'open') {
    $portsText = ($ClassroomPorts -join ',')
    Write-Host ''
    if ($fw.State -eq 'blocked') {
      Write-Host "Firewall: no inbound allow rule found for port(s) $($fw.Missing -join ', ') on the '$profileName' profile." -ForegroundColor Yellow
    } else {
      Write-Host 'Firewall: could not determine whether the ports are open.' -ForegroundColor Yellow
    }
    Write-Host 'If students cannot connect, run this in an ADMINISTRATOR PowerShell (this script does not do it):' -ForegroundColor Yellow
    Write-Host "  New-NetFirewallRule -DisplayName 'Vingt-Un salle de classe' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $portsText -Profile Private -RemoteAddress LocalSubnet" -ForegroundColor White
    Write-Host '  (remove later with: Remove-NetFirewallRule -DisplayName ''Vingt-Un salle de classe'')'
    if ($profileName -and $profileName -ne 'Private') {
      Write-Host "Note: this network uses the '$profileName' profile; a rule limited to the Private profile will NOT apply to it. On a school domain network, ask the IT team to open these ports." -ForegroundColor Yellow
    }
  } else {
    Write-Host 'Firewall: ports appear to be allowed.' -ForegroundColor Green
  }
  foreach ($n in $fw.Notes) { Write-Host "Firewall note: $n" -ForegroundColor Yellow }

  # ----------------------------------------------------------------------------------------
  # Ready
  # ----------------------------------------------------------------------------------------
  $url = "http://${ip}:$WebPort"
  Write-Host ''
  Write-Host '==================================================================' -ForegroundColor Green
  Write-Host "  Classroom server ready.   Teacher IP: $ip" -ForegroundColor Green
  Write-Host "  Students open:            $url" -ForegroundColor Green
  Write-Host "  or run: tools\install_student.ps1 -TeacherIp $ip" -ForegroundColor Green
  Write-Host "  Emulator UI (this machine only): http://127.0.0.1:4000" -ForegroundColor Green
  Write-Host "  Logs: $LogDir" -ForegroundColor Green
  Write-Host '  Ctrl+C to stop (data is exported on exit).' -ForegroundColor Green
  Write-Host '==================================================================' -ForegroundColor Green

  $interrupted = $true # from here on, leaving the loop without a break means Ctrl+C
  $nextSave = if ($AutosaveMinutes -gt 0) { (Get-Date).AddMinutes($AutosaveMinutes) } else { [datetime]::MaxValue }
  $simWarned = $false
  while ($true) {
    Start-Sleep -Seconds 2
    if ($emu.HasExited) { $interrupted = $false; Write-Host "Firebase emulators exited (code $($emu.ExitCode)); see $LogDir\emulators*.log" -ForegroundColor Red; break }
    if ($web.HasExited) { $interrupted = $false; Write-Host "Download page server exited; see $LogDir\static_server*.log" -ForegroundColor Red; break }
    if ($sim.HasExited -and -not $simWarned) {
      $simWarned = $true
      Write-Warning "Simulation loop exited (code $($sim.ExitCode)); bots stop playing. See $LogDir\sim_runner*.log"
    }
    if ((Get-Date) -ge $nextSave) {
      if (Invoke-Export) { Write-Host "$(Get-Date -Format HH:mm:ss) autosave -> $DataDir" } else { Write-Warning "autosave failed; see $LogDir\export*.log" }
      $nextSave = (Get-Date).AddMinutes($AutosaveMinutes)
    }
  }
} catch {
  $interrupted = $false
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  $failed = $true
} finally {
  $env:JAVA_TOOL_OPTIONS = $savedJavaToolOptions
  Write-Host 'Stopping the classroom server...' -ForegroundColor Cyan
  # On Ctrl+C every child received the signal too; give the Firebase CLI time to export.
  $emuChild = $script:Children | Where-Object { $_.Name -eq 'emulators' } | Select-Object -First 1
  if ($emuChild) {
    $grace = if ($interrupted) { 120 } else { 3 }
    if (-not $emuChild.Process.WaitForExit($grace * 1000)) {
      if (Test-Hub) {
        if (Invoke-Export) { Write-Host "Emulator data exported to $DataDir" } else { Write-Warning 'Export before stop failed.' }
      }
    }
  }
  foreach ($c in $script:Children) { Stop-Tree $c.Process }
  Write-Host 'Stopped.'
}
if ($failed) { exit 1 }
