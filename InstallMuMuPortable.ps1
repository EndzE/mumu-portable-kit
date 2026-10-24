# InstallMuMuPortable.ps1 - offline portable MuMu Player 12 Global installer
# Usage: double-click "InstallMuMuPortable.cmd" in the same folder as the
#        MuMu engine exe (MuMu-setup-mumu15-V<version>-<channel>-<build>.exe)

param([string]$Target)

$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
$script:stagingRoot = $null
function Restore-StagedTarget {
    if (-not $script:stagingRoot) { return }
    $staged = $script:stagingRoot
    $final = $targetFull
    $script:stagingRoot = $null
    if (-not (Test-Path -LiteralPath $staged)) { return }
    if (Test-Path -LiteralPath $final) {
        Say "[WARN] Staged install left at $staged (target already exists)." Yellow
        return
    }
    try {
        Move-Item -LiteralPath $staged -Destination $final -ErrorAction Stop
        Say "Moved staged install back to $final." Yellow
        if (Get-Command Update-StagedPaths -ErrorAction SilentlyContinue) {
            $instFinal = Join-Path $final 'Netease\MuMuPlayer15'
            $dataFinal = Join-Path $final 'Data'
            foreach ($root in @((Join-Path $instFinal 'configs'), (Join-Path $instFinal 'nx_device'), (Join-Path $instFinal 'nx_main'), (Join-Path $dataFinal 'Roaming'), (Join-Path $dataFinal 'Local'))) {
                Update-StagedPaths -Root $root -Old $staged -New $final
            }
        }
    } catch {
        Say "[WARN] Could not move staged install back to ${final}: $($_.Exception.Message)" Yellow
        Say "       The staged tree is at $staged" Yellow
    }
}
function Die($m) { Say "`n[ERROR] $m" Red; Restore-StagedTarget; Read-Host 'Press Enter to exit'; exit 1 }
trap { Say "`n[ERROR] $_" Red; Restore-StagedTarget; Read-Host 'Press Enter to exit'; exit 1 }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die 'Run this via "InstallMuMuPortable.cmd" (double-click) so it can request Administrator rights.'
}

Say ''
Say '=== MuMu Player 12 Global - portable offline installer ===' Cyan
Say ''

# --- 1. locate the engine package(s) next to this script ---
$kitDir = $PSScriptRoot
$engineMap = [ordered]@{
    mumu15 = [pscustomobject]@{ label = 'Android 15'; dir = '15.0'; svc = 'MuMuNxSup'; netSvc = 'MuMuNxNetLwf'; clsid = '{50859a2f-a5dd-4fcd-b107-ff2a37b33e4a}'; installName = 'MuMuNxVbox'; svcExe = 'MuMuNxSVC.exe' }
    nemux  = [pscustomobject]@{ label = 'Android 12'; dir = '12.0'; svc = 'MuMuVMMDrv'; netSvc = 'MuMuVMMNetLwf'; clsid = '{23cd1535-edaa-4f21-a4ab-45d97fd1d58b}'; installName = 'MuMuVMMVbox'; svcExe = 'MuMuVMMSVC.exe' }
}
$engines = @()
foreach ($t in $engineMap.Keys) {
    $exes = @(Get-ChildItem -LiteralPath $kitDir -File | Where-Object { $_.Name -match "^MuMu-setup-$t-V[\d.]+-.*\.exe$" })
    if ($exes.Count -gt 1) {
        Say "Multiple $t packages found:" Yellow
        $exes | ForEach-Object { Say "  $($_.Name)" }
        Die "Keep only one $t exe in the folder."
    }
    if ($exes.Count -eq 1) {
        $null = $exes[0].Name -match "^MuMu-setup-$t-V([\d.]+)-"
        $engines += [pscustomobject]@{ type = $t; name = $exes[0].Name; path = $exes[0].FullName; version = $Matches[1] }
    }
}
if ($engines.Count -eq 0) {
    Die "No engine package found in:`n  $kitDir`nPut the mumu15 (Android 15) and/or nemux (Android 12) engine exe next to this script and retry (at least one engine is required)."
}
$channel = 'gw-overseas12'
Say 'Engine package(s):'
foreach ($e in $engines) { Say "  $($e.name)  ($($engineMap[$e.type].label), version $($e.version))" }
foreach ($e in $engines) {
    if ($e.name -notmatch 'overseas') { Say "WARNING: $($e.name) does not look like an overseas/global build; the channel value may be wrong." Yellow }
}

# --- 1b. optional NX main launcher component (nxmain) next to this script ---
$nxmain = $null
$nxExes = @(Get-ChildItem -LiteralPath $kitDir -File | Where-Object { $_.Name -match '^MuMu-setup-nxmain-V[\d.]+-.*\.exe$' })
if ($nxExes.Count -gt 1) {
    Say 'Multiple nxmain packages found:' Yellow
    $nxExes | ForEach-Object { Say "  $($_.Name)" }
    Die 'Keep only one nxmain exe in the folder (or none at all).'
}
if ($nxExes.Count -eq 1) {
    $nxmain = $nxExes[0].FullName
    Say "nxmain : $($nxExes[0].Name)  (optional - NX main launcher / engine manager)"
    if ($nxExes[0].Name -notmatch 'overseas') { Say 'WARNING: nxmain does not look like an overseas/global build.' Yellow }
}

# --- 2. target folder ---
$default = 'C:\MuMuPortable'
if (-not $Target) { $Target = Read-Host "Install target folder (the portable root) [$default]" }
if ([string]::IsNullOrWhiteSpace($Target)) { $Target = $default }
$target = $Target.Trim().TrimEnd('\')
if ($target -match '^[A-Za-z]:$') { Die 'Please specify a folder, not a drive root.' }
try { $targetFull = [IO.Path]::GetFullPath($target) } catch { Die "Invalid path: $target" }
if ($targetFull -match '[&|<>^"]') { Die 'Target path contains unsupported characters (& | < > ^ "). Pick a simpler folder name.' }
foreach ($bad in @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($targetFull -like "$bad*") { Die "Refusing to install into $bad - pick your own folder." }
}
$kitDirFull = [IO.Path]::GetFullPath($kitDir).TrimEnd('\')
if ($targetFull -eq $kitDirFull -or $kitDirFull.StartsWith($targetFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Die "Choose a target folder that does not contain the installer kit ($kitDirFull)."
}

$toInstallEngines = $engines
$addNxmain = [bool]$nxmain
if (Test-Path -LiteralPath $targetFull) {
    $items = @(Get-ChildItem -LiteralPath $targetFull -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) {
        $instTree = Join-Path $targetFull 'Netease\MuMuPlayer15'
        if (Test-Path -LiteralPath $instTree) {
            $existingTypes = @()
            $cfgGuard = Join-Path $instTree 'configs\main\install_config.json'
            if (Test-Path -LiteralPath $cfgGuard) {
                try { $existingTypes = @((Get-Content -LiteralPath $cfgGuard -Raw | ConvertFrom-Json).engines.PSObject.Properties.Name) } catch { }
            }
            $nxMainInstalled = Test-Path -LiteralPath (Join-Path $instTree 'nx_main\MuMuNxMain.exe')
            $missing = @()
            foreach ($e in $engines) { if ($existingTypes -notcontains $e.type) { $missing += $e.type } }
            if ($nxmain -and -not $nxMainInstalled) { $missing += 'nxmain' }
            if ($missing.Count -eq 0) {
                Say "$targetFull already contains a full MuMu install and none of your packages add anything new." Cyan
                $ok = Read-Host 'Refresh the launcher/helper scripts and re-apply engine normalization in place? [Y/n]'
                if ($ok -match '^(n|no)$') { Die 'Aborted.' }
            }
            else {
                Say "Existing install found in the target folder. New component(s) in your kit: $($missing -join ', ')" Cyan
                $ok = Read-Host 'Add them to the existing install? [Y/n]'
                if ($ok -match '^(n|no)$') { Die 'Aborted.' }
            }
            $toInstallEngines = @($engines | Where-Object { $existingTypes -notcontains $_.type })
            $addNxmain = ($nxmain -and -not $nxMainInstalled)
        }
        else {
            Say 'WARNING: the target folder is not empty.' Yellow
            $ok = Read-Host 'Continue anyway? (existing files are kept untouched) [y/N]'
            if ($ok -notmatch '^(y|yes)$') { Die 'Aborted.' }
        }
    }
}
else { New-Item -ItemType Directory -Path $targetFull -Force | Out-Null }

$driveName = (Split-Path -Qualifier $targetFull).TrimEnd(':')
$free = (Get-PSDrive $driveName).Free
$needGB = 4 + 3 * ($toInstallEngines.Count - 1)
if ($free -lt ($needGB * 1GB)) { Die ("Not enough free space on ${driveName}: (need about $needGB GB, found {0:N1} GB)." -f ($free / 1GB)) }
if (Get-Process -Name MuMuNxDevice, MuMuNxSVC, MuMuNxHeadless -ErrorAction SilentlyContinue) { Die 'MuMu is currently running - close it first.' }
if ($toInstallEngines.Count -gt 0) {
    $rtDirs = @('C:\Program Files\MuMuNxVbox\Hypervisor', 'C:\Program Files\MuMuVMMVbox\Hypervisor')
    foreach ($e in $engines) { $rtDirs += (Join-Path $targetFull ('Netease\MuMuPlayer15\nx_device\' + $engineMap[$e.type].dir + '\hypervisor')) }
    $drvQ = (& sc.exe query MuMuVMMDrv 2>&1 | Out-String) + (& sc.exe query MuMuNxSup 2>&1 | Out-String)
    if ($drvQ -match 'SERVICE_NAME') {
        Say 'Existing MuMu driver found - unloading it before the engine upgrade...' Yellow
        $unloaded = $false
        foreach ($rt in $rtDirs) {
            if (Test-Path -LiteralPath (Join-Path $rt 'load.cmd')) {
                $unloaded = $true
                Push-Location -LiteralPath $rt
                try { & cmd.exe /c 'load.cmd --uninstall' } finally { Pop-Location }
            }
        }
        if (-not $unloaded) {
            foreach ($svcOld in 'MuMuVMMDrv', 'MuMuNxSup') { & sc.exe stop $svcOld | Out-Null; & sc.exe delete $svcOld | Out-Null }
        }
    }
}
Say "Target : $targetFull"

function Get-SpaceFreeStagingPath([string]$FinalPath) {
    $parent = Split-Path -Parent $FinalPath
    while ($parent -match '\s' -and (Split-Path -Parent $parent)) {
        $parent = Split-Path -Parent $parent
    }
    if (-not $parent -or $parent -match '\s') {
        Die "Could not find a whitespace-free staging folder for '$FinalPath'."
    }
    do {
        $candidate = Join-Path $parent ('MuMuPortableTmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Update-StagedPaths([string]$Root, [string]$Old, [string]$New) {
    if (-not $Root -or -not $Old -or -not (Test-Path -LiteralPath $Root)) { return }
    $oldEsc = $Old.Replace('\', '\\')
    $newEsc = $New.Replace('\', '\\')
    $oldFwd = $Old.Replace('\', '/')
    $newFwd = $New.Replace('\', '/')
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            $enc = New-Object Text.UTF8Encoding($false)
            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $enc = [Text.Encoding]::BigEndianUnicode }
            elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = New-Object Text.UTF8Encoding($true) }
            $raw = [IO.File]::ReadAllText($f.FullName)
            $upd = [regex]::Replace($raw, [regex]::Escape($Old), { param($m) $New }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $upd = [regex]::Replace($upd, [regex]::Escape($oldEsc), { param($m) $newEsc }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $upd = [regex]::Replace($upd, [regex]::Escape($oldFwd), { param($m) $newFwd }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($upd -ne $raw) {
                [IO.File]::WriteAllText($f.FullName, $upd, $enc)
                Say "Updated staged path in $($f.FullName)"
            }
        } catch { Say "[WARN] Could not update $($f.FullName): $($_.Exception.Message)" Yellow }
    }
}

# The engine consumes /D= unquoted to end-of-line, so a target path with spaces breaks
# the install. Install into a space-free sibling, then move the tree back.
$installRoot = $targetFull
$installStaging = $null
if (($targetFull -match '\s') -and (($toInstallEngines.Count -gt 0) -or $addNxmain)) {
    $installStaging = Get-SpaceFreeStagingPath $targetFull
    $script:stagingRoot = $installStaging
    try {
        if (Test-Path -LiteralPath $targetFull) {
            Move-Item -LiteralPath $targetFull -Destination $installStaging -ErrorAction Stop
        } else {
            New-Item -ItemType Directory -Path $installStaging -Force | Out-Null
        }
    } catch {
        Die "Could not move the target into a space-free staging folder. Close MuMu and anything using '$targetFull', then retry. ($($_.Exception.Message))"
    }
    $installRoot = $installStaging
    Say "Whitespace in target path - staging install in $installStaging (moved back after install)." Cyan
}

# --- portable environment: the engine writes into the tree, not into the user profile ---
$data = Join-Path $installRoot 'Data'
foreach ($d in @($data, "$data\Roaming", "$data\Local", "$data\Temp", "$data\VBox", "$data\MuMuSharedFolder", "$data\logs")) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$env:APPDATA = "$data\Roaming"
$env:LOCALAPPDATA = "$data\Local"
$env:TEMP = "$data\Temp"
$env:TMP = "$data\Temp"
$env:VBOX_USER_HOME = "$data\VBox"

# --- 3. run the engine(s), two phases each, one transaction per component ---
$inst = Join-Path $installRoot 'Netease\MuMuPlayer15'

function Get-ProductVersion {
    try { return (Get-Content -LiteralPath (Join-Path $inst 'configs\main\install_config.json') -Raw | ConvertFrom-Json).product.version } catch { return $null }
}
function Invoke-ComponentOnce([string]$exePath, [string]$action, [string]$tag, [string]$ver) {
    $bat = Join-Path $env:TEMP ('mumu-install-' + $tag + '-' + $action + '.cmd')
    $line = '"' + $exePath + '" /txn_id=' + $txn + ' /action=' + $action +
        ' /from_orchestrator=1 /silent=1 /auto_start=false /product_version=' + $ver +
        ' /fchannel=' + $channel + ' /D=' + $inst
    [IO.File]::WriteAllText($bat, "@echo off`r`n$line`r`n", [Text.Encoding]::ASCII)
    Say ''
    Say "--- $tag /action=$action running (can take several minutes, please wait) ---" Cyan
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('"' + $bat + '"') -Wait -PassThru -WindowStyle Hidden
    $rc = $p.ExitCode
    Remove-Item -LiteralPath $bat -Force -ErrorAction SilentlyContinue
    return $rc
}
function Invoke-Component([string]$exePath, [string]$action, [string]$tag, [string]$ver) {
    $rc = Invoke-ComponentOnce $exePath $action $tag $ver
    $pv = Get-ProductVersion
    if ($rc -eq 80002 -and $pv -and $pv -ne $ver) {
        Say "[retry] $tag was rejected (downgrade check, rc=80002) - retrying with product version $pv" Yellow
        $rc = Invoke-ComponentOnce $exePath $action $tag $pv
    }
    if ($rc -ne 0) {
        Say "[FAIL] $tag /action=$action exited with code $rc" Red
        if ($tag -eq 'nxmain') { Say "nxmain logs: $env:TEMP\MuMuPlayerGlobal\main\" Yellow }
        else { Say "Engine logs: $env:TEMP\MuMuPlayerGlobal\$tag\" Yellow }
        if ($rc -eq 30012) {
            Say 'The hypervisor driver was locked by the kernel (it was loaded before this run).' Yellow
            Say 'REBOOT Windows, then run this installer again - the upgrade will complete then.' Yellow
        }
        Die "Installation failed during $tag '$action'."
    }
    Say "    [$tag $action] OK" Green
}

foreach ($e in $toInstallEngines) {
    $txn = [guid]::NewGuid().ToString()
    Say ''
    Say "--- Engine: $($e.name)  ($($engineMap[$e.type].label)) ---" Cyan
    Invoke-Component $e.path 'install_prepare' $e.type $e.version
    Invoke-Component $e.path 'commit' $e.type $e.version
    if (-not (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $engineMap[$e.type].dir + "\shell\MuMuNxDevice.exe")))) {
        Die "The $($e.type) engine finished but the install tree looks incomplete ($inst). Check the engine logs."
    }
    Say "$($e.type) engine install complete." Green
}

# --- 3a. engine vms storage dir (the NX launchers validate this dir at startup;
#         without it nx_main falls back to degraded mode and refuses device management) ---
New-Item -ItemType Directory -Path "$inst\vms" -Force | Out-Null
Say "VM storage dir ready: $targetFull\Netease\MuMuPlayer15\vms"

# --- 3b. optional nxmain component (run while the tree is at the space-free staging path) ---
if ($addNxmain) {
    Say ''
    Say '--- NX main launcher component (nxmain) ---' Cyan
    $txn = [guid]::NewGuid().ToString()
    Invoke-Component $nxmain 'install_prepare' 'nxmain' (Get-ProductVersion)
    Invoke-Component $nxmain 'commit' 'nxmain' (Get-ProductVersion)
    if (-not (Test-Path -LiteralPath "$inst\nx_main\MuMuNxMain.exe")) {
        Die "nxmain finished but '$inst\nx_main\MuMuNxMain.exe' is missing. Check the logs above."
    }
    Say 'nxmain installed (launcher UI included).' Green
}

# --- move the staged tree back to the requested path before host repair/scripts ---
if ($installStaging) {
    if (Test-Path -LiteralPath $targetFull) {
        Die "The target folder was recreated during install; staged files are in $installStaging."
    }
    Move-Item -LiteralPath $installStaging -Destination $targetFull -ErrorAction Stop
    $script:stagingRoot = $null
    $installRoot = $targetFull
    $inst = Join-Path $targetFull 'Netease\MuMuPlayer15'
    $data = Join-Path $targetFull 'Data'
    $env:APPDATA = "$data\Roaming"
    $env:LOCALAPPDATA = "$data\Local"
    $env:TEMP = "$data\Temp"
    $env:TMP = "$data\Temp"
    $env:VBOX_USER_HOME = "$data\VBox"
    Say "Staged install moved to $targetFull." Green
    foreach ($root in @((Join-Path $inst 'configs'), (Join-Path $inst 'nx_device'), (Join-Path $inst 'nx_main'), (Join-Path $data 'Roaming'), (Join-Path $data 'Local'))) {
        Update-StagedPaths -Root $root -Old $installStaging -New $targetFull
    }
}

# --- 3c. per-engine repair/normalize: Program Files runtime, COM registration, driver family ---
# The engine's upgrade path replaces the shared runtime and unregisters the other engine's
# COM classes and drivers; re-register and re-install each installed engine's own family
# (validated: without this, older-engine devices fail with VERR_VIRTUALBOX_ACCESSDENIED /
#  VERR_LAUNCH_DRIVER_ERROR after a newer engine was added).
foreach ($e in $engines) {
    $m = $engineMap[$e.type]
    $hv = Join-Path $inst ("nx_device\" + $m.dir + "\hypervisor")
    if (-not (Test-Path -LiteralPath $hv)) { continue }
    if (Test-Path -LiteralPath (Join-Path $hv 'comregister.cmd')) {
        # Devices resolve the hypervisor via nx_device\<ver>\configs\device\hypervisor_config.json
        # ("install_dir" = C:\Program Files\<install_name>). If that runtime is missing (e.g. after
        # Cleanup-Residue removed it) every VM start in the device fails with
        # VERR_RPC_SERVER_UNAVAILABLE - restore it from the engine-local copy and register COM
        # from there (matches the installer-known-good layout).
        $pfDir = Join-Path 'C:\Program Files' ($m.installName + '\Hypervisor')
        if (-not (Test-Path -LiteralPath (Join-Path $pfDir $m.svcExe))) {
            Say "Restoring $($m.label) hypervisor runtime to C:\Program Files\$($m.installName)..."
            try {
                New-Item -ItemType Directory -Path $pfDir -Force | Out-Null
                Copy-Item -Path (Join-Path $hv '*') -Destination $pfDir -Recurse -Force
            } catch { Say "[WARN] Could not restore the runtime: $($_.Exception.Message)" Yellow }
        }
        $regTarget = if (Test-Path -LiteralPath (Join-Path $pfDir $m.svcExe)) { $pfDir } else { $hv }
        $svcExe = $null
        try { $svcExe = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$($m.clsid)\LocalServer32" -ErrorAction Stop).'(default)' } catch { }
        $svcExePath = if ($svcExe) { $svcExe.Trim().Trim('"') } else { '' }
        $registered = [bool]$svcExePath -and (Test-Path -LiteralPath $svcExePath)
        if ($registered -and ($regTarget -ne $hv) -and (-not $svcExePath.StartsWith($regTarget, [StringComparison]::OrdinalIgnoreCase))) { $registered = $false }
        if (-not $registered) {
            Say "Registering $($m.label) COM classes ($regTarget)..."
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $regTarget + '" && comregister.cmd') -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) comregister exited with $($p.ExitCode)" Yellow }
        }
    }
    if ((-not ((& sc.exe query $m.svc 2>&1 | Out-String) -match 'SERVICE_NAME')) -and (Test-Path -LiteralPath (Join-Path $hv 'load.cmd'))) {
        Say "Installing $($m.label) driver family..."
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $hv + '" && load.cmd') -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) driver install exited with $($p.ExitCode)" Yellow }
    }
    if ((-not ((& sc.exe query $m.netSvc 2>&1 | Out-String) -match 'SERVICE_NAME')) -and (Test-Path -LiteralPath (Join-Path $hv 'loadlwf.cmd'))) {
        Say "Installing $($m.label) network filter..."
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $hv + '" && loadlwf.cmd') -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) network filter exited with $($p.ExitCode)" Yellow }
    }
}

# --- 4. shared folder -> inside the portable tree ---
$cfgFile = "$inst\configs\main\vm_config.json"
$data = Join-Path $targetFull 'Data'
$shared = Join-Path $data 'MuMuSharedFolder'
New-Item -ItemType Directory -Path $shared -Force | Out-Null
$cfg = $null
if (Test-Path -LiteralPath $cfgFile) {
    try { $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json } catch { $cfg = $null }
}
if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }
function Ensure($o, $k) {
    if ($null -eq $o.$k -or $o.$k -isnot [pscustomobject]) { $o | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]@{}) -Force }
    return $o.$k
}
$vm = Ensure $cfg 'vm'; $sf = Ensure $vm 'sharefolder'; $usr = Ensure $sf 'user'
$usr | Add-Member -NotePropertyName 'name' -NotePropertyValue 'MuMuSharedFolder' -Force
$usr | Add-Member -NotePropertyName 'path' -NotePropertyValue $shared -Force
[IO.File]::WriteAllText($cfgFile, ($cfg | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
Say "Shared folder -> $shared"

# --- 5. portable launch scripts + driver scripts + readme into the target ---
$launchEngineTpl = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "INST=%ROOT%\Netease\MuMuPlayer15"
set "SHELL=%INST%\nx_device\@@A@@\shell"
set "DATA=%ROOT%\Data"
set "LOG=%DATA%\logs"

if not exist "%INST%" (
  echo [ERROR] MuMu install folder not found:
  echo         %INST%
  exit /b 1
)

for %%D in ("%DATA%" "%DATA%\Roaming" "%DATA%\Local" "%DATA%\Temp" "%DATA%\VBox" "%DATA%\MuMuSharedFolder" "%LOG%") do if not exist "%%~D" md "%%~D" >nul 2>&1

rem --- keep the shared-folder path in sync with this folder's location (portable move support) ---
set "MUMU_ROOT=%ROOT%"
set "MUMU_CFG=%INST%\configs\main\vm_config.json"
if exist "%MUMU_CFG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:MUMU_CFG; $p=Join-Path $env:MUMU_ROOT 'Data\MuMuSharedFolder'; try { $j=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; if ($j.vm.sharefolder.user.path -ne $p) { $j.vm.sharefolder.user.path=$p; [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 10)) } } catch { }"
set "MUMU_ROOT="
set "MUMU_CFG="

sc query MuMuVMMDrv >nul 2>&1
if errorlevel 1 sc query MuMuNxSup >nul 2>&1
if errorlevel 1 (
  echo [WARN] MuMu driver MuMuVMMDrv/MuMuNxSup is not installed on this PC.
  echo        Run "Enable-Driver.cmd" as Administrator once, then relaunch.
  echo        MuMu cannot boot a device without its driver - aborting.
  echo.
  pause
  exit /b 1
)

set "APPDATA=%DATA%\Roaming"
set "LOCALAPPDATA=%DATA%\Local"
set "TEMP=%DATA%\Temp"
set "TMP=%DATA%\Temp"
set "VBOX_USER_HOME=%DATA%\VBox"

if not exist "%SHELL%\MuMuNxDevice.exe" (
  echo [ERROR] MuMuNxDevice.exe not found in %SHELL%
  exit /b 1
)

rem --- engine user-profile dir the VMM COM layer needs (recreate if a cleanup removed it) ---
if not exist "%USERPROFILE%\.MUMUVMM" md "%USERPROFILE%\.MUMUVMM" >nul 2>&1

rem --- boot the first device of THIS engine; fall back to the engine default if none exists yet ---
set "VMNAME="
for /d %%D in ("%INST%\vms\MuMuPlayerGlobal-@@A@@-*") do if not defined VMNAME set "VMNAME=%%~nxD"
if not defined VMNAME (
  echo [WARN] No Android @@A@@ device exists yet - create one via "Launch Launcher.cmd" and "+ New".
  echo.
  start "" "%SHELL%\MuMuNxDevice.exe" %*
  exit /b 0
)
set "VMIDX=%VMNAME:MuMuPlayerGlobal-@@A@@-=%"
start "" "%SHELL%\MuMuNxDevice.exe" -v %VMIDX% --vm %VMNAME% %*
exit /b 0
'@

$launchLauncher = @'
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "INST=%ROOT%\Netease\MuMuPlayer15"
set "DATA=%ROOT%\Data"
set "LOG=%DATA%\logs"

if not exist "%INST%" (
  echo [ERROR] MuMu install folder not found:
  echo         %INST%
  exit /b 1
)

for %%D in ("%DATA%" "%DATA%\Roaming" "%DATA%\Local" "%DATA%\Temp" "%DATA%\VBox" "%DATA%\MuMuSharedFolder" "%LOG%") do if not exist "%%~D" md "%%~D" >nul 2>&1

rem --- keep the shared-folder path in sync with this folder's location (portable move support) ---
set "MUMU_ROOT=%ROOT%"
set "MUMU_CFG=%INST%\configs\main\vm_config.json"
if exist "%MUMU_CFG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:MUMU_CFG; $p=Join-Path $env:MUMU_ROOT 'Data\MuMuSharedFolder'; try { $j=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; if ($j.vm.sharefolder.user.path -ne $p) { $j.vm.sharefolder.user.path=$p; [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 10)) } } catch { }"
set "MUMU_ROOT="
set "MUMU_CFG="

sc query MuMuVMMDrv >nul 2>&1
if errorlevel 1 sc query MuMuNxSup >nul 2>&1
if errorlevel 1 (
  echo [WARN] MuMu driver MuMuVMMDrv/MuMuNxSup is not installed on this PC.
  echo        Run "Enable-Driver.cmd" as Administrator once, then relaunch.
  echo        MuMu cannot boot a device without its driver - aborting.
  echo.
  pause
  exit /b 1
)

set "APPDATA=%DATA%\Roaming"
set "LOCALAPPDATA=%DATA%\Local"
set "TEMP=%DATA%\Temp"
set "TMP=%DATA%\Temp"
set "VBOX_USER_HOME=%DATA%\VBox"

rem --- engine user-profile dir the VMM COM layer needs (recreate if a cleanup removed it) ---
if not exist "%USERPROFILE%\.MUMUVMM" md "%USERPROFILE%\.MUMUVMM" >nul 2>&1

if not exist "%INST%\nx_main\MuMuNxMain.exe" (
  echo [ERROR] Launcher not found: %INST%\nx_main\MuMuNxMain.exe
  echo         This install was created without the nxmain launcher component.
  exit /b 1
)

rem --- opens the launcher UI; boot the engines you need from the device list ---
start "" "%INST%\nx_main\MuMuNxMain.exe" %*
exit /b 0
'@
Remove-Item -LiteralPath (Join-Path $targetFull 'Launch Engine.cmd') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $targetFull 'Launch MuMu.cmd') -Force -ErrorAction SilentlyContinue
$mumuVmmDir = Join-Path $env:USERPROFILE '.MUMUVMM'
if (-not (Test-Path -LiteralPath $mumuVmmDir)) { New-Item -ItemType Directory -Path $mumuVmmDir | Out-Null }
foreach ($e in $engines) {
    $m = $engineMap[$e.type]
    if (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $m.dir + "\shell\MuMuNxDevice.exe"))) {
        $content = $launchEngineTpl.Replace('@@A@@', $m.dir)
        [IO.File]::WriteAllText((Join-Path $targetFull ("Launch " + $m.label + ".cmd")), $content, [Text.Encoding]::ASCII)
        Say "Launch script ready: Launch $($m.label).cmd"
    }
}
if (Test-Path -LiteralPath (Join-Path $inst 'nx_main\MuMuNxMain.exe')) {
    [IO.File]::WriteAllText((Join-Path $targetFull 'Launch Launcher.cmd'), $launchLauncher, [Text.Encoding]::ASCII)
    Say 'Launch script ready: Launch Launcher.cmd'
}

$enableEngineBlocks = foreach ($t in $engineMap.Keys) {
    $m = $engineMap[$t]
    $pf = 'C:\Program Files\' + $m.installName + '\Hypervisor'
    @"
if exist "%INST%\nx_device\$($m.dir)\hypervisor\load.cmd" (
  echo --- $($m.label) ---
  if not exist "$pf" md "$pf"
  xcopy "%INST%\nx_device\$($m.dir)\hypervisor" "$pf" /E /I /Y /Q
  if errorlevel 1 echo [WARN] $($m.label) runtime copy failed.
  if exist "$pf\comregister.cmd" (
    pushd "$pf"
    call comregister.cmd
    popd
  )
  pushd "%INST%\nx_device\$($m.dir)\hypervisor"
  call load.cmd
  if exist loadlwf.cmd call loadlwf.cmd
  popd
)
"@
}
$enableEngineBlocks = $enableEngineBlocks -join "`r`n"

$enable = @'
@echo off
setlocal EnableExtensions
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] This script must be run as Administrator.
  echo         Right-click it and choose "Run as administrator".
  pause
  exit /b 1
)

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "INST=%ROOT%\Netease\MuMuPlayer15"
if not exist "%USERPROFILE%\.MUMUVMM" md "%USERPROFILE%\.MUMUVMM"

echo === Installing MuMu hypervisor runtimes into C:\Program Files ===

@@ENGINE_BLOCKS@@

echo.
echo === Driver status ===
for %%S in (MuMuVMMDrv MuMuNxSup MuMuVMMNetLwf MuMuNxNetLwf) do sc query %%S 2>nul | findstr "STATE" || echo   %%S not installed
echo.
echo Done. If the drivers above show RUNNING you can launch MuMu with the Launch *.cmd scripts.
pause
'@
$enable = $enable.Replace('@@ENGINE_BLOCKS@@', $enableEngineBlocks)
[IO.File]::WriteAllText((Join-Path $targetFull 'Enable-Driver.cmd'), $enable, [Text.Encoding]::ASCII)

$blockInternet = @'
@echo off
setlocal EnableExtensions

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo MuMu Player - offline mode: block ALL MuMu network access
echo ========================================================
echo This PC-wide Windows Firewall change adds Inbound + Outbound
echo BLOCK rules for every MuMu executable, tagged with a group
echo named after THIS folder - several portable setups on one PC
echo keep separate offline switches and never overwrite each other.
echo The rules (incl. the shared C:\Program Files runtimes) override
echo the allow rules MuMu's own installers added, so the emulator
echo runs fully offline. Local device use, adb and the shared
echo folder are unaffected (no loopback filtering).
echo Re-run this script after moving the folder or updating a
echo component. Run Allow-Internet.cmd to revert THIS folder only.
echo.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MUMU_ROOT=%ROOT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$g='MuMu Portable Offline ('+$env:MUMU_ROOT+')';$t=Join-Path $env:MUMU_ROOT 'Netease\MuMuPlayer15';$d=@();if(Test-Path (Join-Path $t 'nx_main')){$d+=Join-Path $t 'nx_main'};foreach($v in @(Get-ChildItem (Join-Path $t 'nx_device') -Directory -ErrorAction SilentlyContinue)){$d+=Join-Path $v.FullName 'shell';$d+=Join-Path $v.FullName 'device'};$d+='C:\Program Files\MuMuNxVbox\Hypervisor','C:\Program Files\MuMuVMMVbox\Hypervisor';$x=@($d|Where-Object{Test-Path $_}|ForEach-Object{Get-ChildItem $_ -Recurse -Filter *.exe -ErrorAction SilentlyContinue});$old=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group 'MuMu Portable Offline' -ErrorAction SilentlyContinue);if($old.Count){$old|Remove-NetFirewallRule};foreach($e in $x){New-NetFirewallRule -DisplayName ('MuMuOffline '+$e.Name+' out') -Group $g -Program $e.FullName -Direction Outbound -Action Block -Profile Any|Out-Null;New-NetFirewallRule -DisplayName ('MuMuOffline '+$e.Name+' in') -Group $g -Program $e.FullName -Direction Inbound -Action Block -Profile Any|Out-Null};$n=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue);'Blocked exes: '+@($x).Count+'   rules now: '+$n.Count+'   (stale removed: '+$old.Count+')'"
set "MUMU_ROOT="
echo.
pause
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'Block-Internet.cmd'), $blockInternet, [Text.Encoding]::ASCII)

$allowInternet = @'
@echo off
setlocal EnableExtensions

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo MuMu Player - leave offline mode (allow network access again)
echo ============================================================
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MUMU_ROOT=%ROOT%"
powershell -NoProfile -Command "$g='MuMu Portable Offline ('+$env:MUMU_ROOT+')';$r=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group 'MuMu Portable Offline' -ErrorAction SilentlyContinue);if($r.Count){$r|Remove-NetFirewallRule;'Removed offline block rules: '+$r.Count}else{'No offline block rules present.'}"
set "MUMU_ROOT="
echo.
pause
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'Allow-Internet.cmd'), $allowInternet, [Text.Encoding]::ASCII)
Say 'Offline scripts ready: Block-Internet.cmd / Allow-Internet.cmd'

$disable = @'
@echo off
setlocal EnableExtensions
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] This script must be run as Administrator.
  echo         Right-click it and choose "Run as administrator".
  pause
  exit /b 1
)

set "INST=%~dp0Netease\MuMuPlayer15"

echo === Unregistering the NX remote service first (marked services are never auto-restarted) ===
sc delete MuMuPlayerRemoteService >nul 2>&1
sc stop MuMuPlayerRemoteService >nul 2>&1

echo === Closing MuMu processes (if any) ===
taskkill /F /IM MuMuNxDevice.exe >nul 2>&1
taskkill /F /IM MuMuNxHeadless.exe >nul 2>&1
taskkill /F /IM MuMuNxSVC.exe >nul 2>&1
taskkill /F /IM MuMuNxMain.exe >nul 2>&1
taskkill /F /IM MuMuNxLauncher.exe >nul 2>&1
taskkill /F /IM MuMuNxService.exe >nul 2>&1
taskkill /F /IM MuMuManager.exe >nul 2>&1
taskkill /F /IM MuMuVMMHeadless.exe >nul 2>&1
taskkill /F /IM MuMuVMMSVC.exe >nul 2>&1
taskkill /F /IM MuMuVMMManage.exe >nul 2>&1
taskkill /F /IM MuMuPlayerRemoteService.exe >nul 2>&1
taskkill /F /IM MuMuPlayerRemoteBackend.exe >nul 2>&1
taskkill /F /IM MuMuPlayerRemoteHealthd.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo === Unloading driver(s) for every installed engine ===
for %%V in (15.0 12.0) do if exist "%INST%\nx_device\%%V\hypervisor\load.cmd" (
  echo --- engine %%V ---
  pushd "%INST%\nx_device\%%V\hypervisor"
  call load.cmd --uninstall
  popd
)
for %%P in (MuMuNxVbox MuMuVMMVbox) do if exist "C:\Program Files\%%P\Hypervisor\load.cmd" (
  echo --- runtime %%P ---
  pushd "C:\Program Files\%%P\Hypervisor"
  call load.cmd --uninstall
  popd
)
del /f /q "%SystemRoot%\System32\drivers\MuMuVMMNetLwf.sys" >nul 2>&1
del /f /q "%SystemRoot%\System32\drivers\MuMuNxNetLwf.sys" >nul 2>&1
if exist "%SystemRoot%\System32\drivers\MuMuVMMNetLwf.sys" echo [WARN] MuMuVMMNetLwf.sys is still present - reboot and run this script again.
if exist "%SystemRoot%\System32\drivers\MuMuNxNetLwf.sys" echo [WARN] MuMuNxNetLwf.sys is still present - reboot and run this script again.

echo.
echo === Driver status ===
sc query MuMuVMMDrv 2>nul || echo MuMuVMMDrv not present (good).
sc query MuMuVMMNetLwf 2>nul || echo MuMuVMMNetLwf not present (good).
sc query MuMuNxSup 2>nul || echo MuMuNxSup not present (good).
sc query MuMuNxNetLwf 2>nul || echo MuMuNxNetLwf not present (good).
echo.
echo === Removing MuMu virtual display device(s) and driver packages ===
powershell -NoProfile -Command "$d=@(Get-PnpDevice -ErrorAction SilentlyContinue|Where-Object{$_.InstanceId -match 'MUMU' -or $_.FriendlyName -match 'MuMu'});foreach($x in $d){pnputil /remove-device $x.InstanceId|Out-Null};if($d.Count){'Removed PnP devices: '+$d.Count}else{'No MuMu PnP devices present'}"
powershell -NoProfile -Command "$cur=$null;$hits=@();foreach($l in [string[]](pnputil /enum-drivers)){if($l -match 'Published Name\s*:\s*(oem\d+\.inf)'){$cur=$Matches[1]}elseif($cur -and $l -match 'Original Name\s*:\s*(\S+)'){if($Matches[1] -match 'mumu'){$hits+=$cur};$cur=$null}};foreach($h in $hits){pnputil /delete-driver $h /uninstall /force|Out-Null};if($hits.Count){'Removed driver packages: '+($hits -join ', ')}else{'No MuMu driver packages present'}"
echo.
echo === Removing firewall rules ===
powershell -NoProfile -Command "$n='MuMuVMMSVC','MuMuVMMHeadless','MuMuNxDevice','NXDeviceAria2','MuMuNxLauncher','MuMuNxMain','NXMainAria2';$r=@(Get-NetFirewallRule -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName -in $n});if($r.Count){$r|Remove-NetFirewallRule;'Removed firewall rules: '+($r.DisplayName -join ', ')}else{'No MuMu firewall rules present'}"
powershell -NoProfile -Command "$r=@(Get-NetFirewallRule -ErrorAction SilentlyContinue|Where-Object{$_.Group -like 'MuMu Portable Offline*'});if($r.Count){$r|Remove-NetFirewallRule;'Removed offline block rules: '+$r.Count}else{'No offline block rules present'}"
echo.
echo === Removing NX launcher leftovers (shortcuts, autostart, uninstall entry) ===
del "%USERPROFILE%\Desktop\MuMuPlayer.lnk" >nul 2>&1
rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\MuMuPlayer" >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v MuMuPlayerGlobal /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MuMuPlayerGlobal" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Netease\MuMuPlayerRemote" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Netease\MuMuPlayerRemoteSetup" /f >nul 2>&1
rem --- remove the parent only if it is now empty ---
powershell -NoProfile -Command "if ((Test-Path 'HKLM:\SOFTWARE\Netease') -and -not (Get-ChildItem 'HKLM:\SOFTWARE\Netease' -ErrorAction SilentlyContinue | Select-Object -First 1)) { Remove-Item 'HKLM:\SOFTWARE\Netease' -Force -ErrorAction SilentlyContinue }" >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\NemuServer" /f >nul 2>&1
rmdir /s /q "%ProgramData%\Netease\MuMuPlayerGlobal" >nul 2>&1
rmdir /s /q "%ProgramData%\Netease\MumuPlayerRemote" >nul 2>&1
rmdir "%ProgramData%\Netease" >nul 2>&1
echo Done.
echo.
echo === Removing the Program Files runtime directories ===
for %%P in (MuMuNxVbox MuMuVMMVbox) do (
  if exist "C:\Program Files\%%P" (
    echo Removing "C:\Program Files\%%P" ...
    rmdir /s /q "C:\Program Files\%%P"
  )
)
for %%P in (MuMuNxVbox MuMuVMMVbox) do if exist "C:\Program Files\%%P" (
  echo [WARN] Could not fully remove "C:\Program Files\%%P" ^(driver files possibly still in use^).
  echo        Reboot and run this script again to finish cleanup.
)
if not exist "C:\Program Files\MuMuNxVbox" if not exist "C:\Program Files\MuMuVMMVbox" echo Removed.
echo.
echo Note: firewall rules (incl. offline block rules), the NX remote service,
echo launcher shortcuts, the uninstall entry and %%ProgramData%%\Netease
echo traces are removed above (recreated automatically at next install or
echo first launch of the launcher).
echo User-data traces (registry HKCU\Software\Netease, %%APPDATA%%\Netease,
echo %%USERPROFILE%%\.MUMUNX, Documents\MuMuSharedFolder) are NOT removed by this script.
pause
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'Disable-Driver.cmd'), $disable, [Text.Encoding]::ASCII)

$readme = @'
MuMu Player 12 Global - portable build
======================================

This folder IS the install. No setup needed; nothing is written to the
system on launch. The install is version-pinned and fully offline.

FIRST RUN ON A NEW PC (once, needs Administrator)
-------------------------------------------------
  Right-click  Enable-Driver.cmd -> Run as administrator
  Installs the forked-VirtualBox support driver (MuMuVMMDrv/MuMuNxSup) and the
  per-engine hypervisor runtimes to C:\Program Files (Android 15: MuMuNxVbox,
  Android 12: MuMuVMMVbox).

START THE EMULATOR
------------------
  Double-click  Launch Android 15.cmd  (or Launch Android 12.cmd)
  One script per installed engine version - it boots the first engine of
  that version directly (on a fresh install the device is created locally
  here - fully offline; the launcher window may also pop up, that is the
  app's own startup behaviour).

  Double-click  Launch Launcher.cmd
  Opens the device list UI; create and boot devices of any installed
  version from there. Only present when the launcher component was
  included.

  More devices: use "+ New" in the launcher - it also works offline once
  the first engine of that version exists.

GO FULLY OFFLINE ON THIS PC (Administrator, optional)
-----------------------------------------------------
  Right-click  Block-Internet.cmd -> Run as administrator
  Adds Windows Firewall block rules (Inbound + Outbound) for every MuMu
  executable on this PC, so MuMu makes no network requests at all - no
  simplewall needed. Block rules override the allow rules MuMu's own
  installers add. Local devices, adb and the shared folder keep working;
  the Android guest loses internet too (by design).
  Re-run after moving this folder or updating a component.
  Rules are tagged per folder, so several portable setups on one PC
  keep separate offline switches.
  Revert with  Allow-Internet.cmd  (same right-click; this folder only).
  Both are also undone by Disable-Driver.cmd.

REMOVE THE DRIVER FROM A PC (Administrator)
------------------------------------------
  Right-click  Disable-Driver.cmd -> Run as administrator

NOTES
-----
- All user data (settings, screenshots, shared folder, VM profile) lives
  inside .\Data. The real %APPDATA% / %USERPROFILE% are not used when
  starting via the Launch *.cmd scripts.
- Setup writes small engine install records to your user profile; the
  installer removes them at the end.
- The folder can be moved to any path or drive; absolute paths are
  re-derived and self-repaired on launch.
- Always start via the provided Launch *.cmd scripts (they set up the
  portable environment). Do not run the exes directly.
- Each installed engine version gets its own direct-boot script ("Launch
  Android 15.cmd" / "Launch Android 12.cmd"); the device list / "+ New"
  manager comes with the optional NX launcher component. Add engines or the
  launcher later by putting the exe next to the installer and running the
  installer again on this same folder.
- If the NX launcher offers to download updates, ignore it: this kit is
  meant to stay on a pinned version.
- Shared folder visible inside Android: .\Data\MuMuSharedFolder
- Driver requirement: one-time Administrator action per PC (kernel
  driver). Everything else is fully portable.
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'README.txt'), $readme, [Text.Encoding]::ASCII)

# --- 6. driver: enable on this PC (optional) ---
Say ''
$q = (& sc.exe query MuMuVMMDrv 2>&1 | Out-String) + (& sc.exe query MuMuNxSup 2>&1 | Out-String)
if ($q -match 'RUNNING') { Say 'MuMu driver present and running (set up by the engine) - nothing to do.' Green }
elseif ($q -match 'SERVICE_NAME') {
    $svc = if ($q -match 'MuMuVMMDrv') { 'MuMuVMMDrv' } else { 'MuMuNxSup' }
    Say "MuMu driver present but not running - starting $svc..." Yellow
    & sc.exe start $svc | Out-Null
    & sc.exe query $svc
}
else {
    $a = Read-Host 'Enable the emulator driver on THIS PC now? (one-time, needed to run the emulator here) [Y/n]'
    if ($a -match '^(n|no)$') { Say 'Skipped. To enable later: run Enable-Driver.cmd (as Administrator) in the target folder.' Yellow }
    else {
        foreach ($e in $engines) {
            $m = $engineMap[$e.type]
            $hv = Join-Path $inst ("nx_device\" + $m.dir + "\hypervisor")
            if (-not (Test-Path -LiteralPath (Join-Path $hv 'load.cmd'))) { continue }
            $dst = Join-Path 'C:\Program Files' ($m.installName + '\Hypervisor')
            Say "Restoring $($m.label) hypervisor runtime to C:\Program Files\$($m.installName)..."
            try {
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
                Copy-Item -Path (Join-Path $hv '*') -Destination $dst -Recurse -Force
            } catch { Say "[WARN] Could not restore the runtime: $($_.Exception.Message)" Yellow }
            if (Test-Path -LiteralPath (Join-Path $dst 'comregister.cmd')) {
                $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $dst + '" && comregister.cmd') -Wait -PassThru -WindowStyle Hidden
                if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) comregister exited with $($p.ExitCode)" Yellow }
            }
        }
        Say 'Loading driver(s)...'
        foreach ($e in $engines) {
            $m = $engineMap[$e.type]
            $hv = Join-Path $inst ("nx_device\" + $m.dir + "\hypervisor")
            if (-not (Test-Path -LiteralPath (Join-Path $hv 'load.cmd'))) { continue }
            Push-Location -LiteralPath $hv
            try { & cmd.exe /c 'load.cmd' } finally { Pop-Location }
            if (Test-Path -LiteralPath (Join-Path $hv 'loadlwf.cmd')) {
                Push-Location -LiteralPath $hv
                try { & cmd.exe /c 'loadlwf.cmd' } finally { Pop-Location }
            }
        }
        Say 'Driver status:'
        & sc.exe query MuMuVMMDrv
        if ($LASTEXITCODE -ne 0) { & sc.exe query MuMuNxSup }
    }
}

# --- 7. remove engine/nxmain-written host traces (known-folder APIs ignore the env redirects above) ---
$realAppData = [Environment]::GetFolderPath('ApplicationData')
$icfgDir = Join-Path $realAppData 'Netease\MuMuPlayerGlobal'
foreach ($f2 in @('install_config.json', 'new_install.json')) {
    $p = Join-Path $icfgDir $f2
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        Say "Removed engine install record: $p"
    }
}
$hcfg = Join-Path $realAppData 'Netease\MuMuNx\hypervisor_config.json'
if (Test-Path -LiteralPath $hcfg) {
    Remove-Item -LiteralPath $hcfg -Force -ErrorAction SilentlyContinue
    Say "Removed engine install record: $hcfg"
}
foreach ($d in @((Join-Path $icfgDir 'data'), $icfgDir, (Join-Path $realAppData 'Netease\MuMuNx'), (Join-Path $realAppData 'Netease'))) {
    if ((Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop } catch { }
    }
}

# --- 7b. NX launcher (nxmain) host traces: shortcuts, autostart, uninstall entry, remote service ---
$deskLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MuMuPlayer.lnk'
if (Test-Path -LiteralPath $deskLnk) { Remove-Item -LiteralPath $deskLnk -Force -ErrorAction SilentlyContinue; Say "Removed desktop shortcut: $deskLnk" }
$smpDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'MuMuPlayer'
if (Test-Path -LiteralPath $smpDir) { Remove-Item -LiteralPath $smpDir -Recurse -Force -ErrorAction SilentlyContinue; Say "Removed Start Menu folder: $smpDir" }
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'MuMuPlayerGlobal' -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MuMuPlayerGlobal' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Netease\MuMuPlayerRemote' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Netease\MuMuPlayerRemoteSetup' -Recurse -Force -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Netease') -and -not (Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Netease' -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    try { Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Netease' -Force -ErrorAction Stop } catch { }
}
Remove-Item -Path 'HKLM:\SOFTWARE\WOW6432Node\NemuServer' -Recurse -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'
& sc.exe delete MuMuPlayerRemoteService 2>&1 | Out-Null
& sc.exe stop MuMuPlayerRemoteService 2>&1 | Out-Null
Start-Sleep -Milliseconds 300
foreach ($pn in @('MuMuPlayerRemoteService', 'MuMuPlayerRemoteBackend', 'MuMuPlayerRemoteHealthd')) {
    & taskkill.exe /F /IM "$pn.exe" 2>&1 | Out-Null
}
Start-Sleep -Milliseconds 500
foreach ($d in @("$env:ProgramData\Netease\MuMuPlayerGlobal", "$env:ProgramData\Netease\MumuPlayerRemote")) {
    if (Test-Path -LiteralPath $d) {
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        Say "Removed launcher runtime traces: $d"
    }
}
if ((Test-Path -LiteralPath "$env:ProgramData\Netease") -and -not (Get-ChildItem -LiteralPath "$env:ProgramData\Netease" -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    try { Remove-Item -LiteralPath "$env:ProgramData\Netease" -Force -ErrorAction Stop } catch { }
}
$svcQ = (& sc.exe query MuMuPlayerRemoteService 2>&1 | Out-String)
Say 'Removed NX launcher host traces (shortcuts, autostart, uninstall entry, remote service).'
if ($svcQ -notmatch '1060') {
    Say 'Note: the NX remote service finishes unregistering after its process exits (reboot at the latest).' Yellow
}
$docsShared = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'MuMuSharedFolder'
if ((Test-Path -LiteralPath $docsShared) -and -not (Get-ChildItem -LiteralPath $docsShared -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    try { Remove-Item -LiteralPath $docsShared -Force -ErrorAction Stop; Say 'Removed empty Documents\MuMuSharedFolder (unused - the share folder lives in Data)' } catch { }
}

Say ''
Say '=================================================' Green
Say " Portable MuMu installed in: $targetFull" Green
$sumScripts = @()
foreach ($e in $engines) {
    if (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $engineMap[$e.type].dir + "\shell\MuMuNxDevice.exe"))) { $sumScripts += '"Launch ' + $engineMap[$e.type].label + '.cmd"' }
}
if ($sumScripts) { Say (' Start with: ' + ($sumScripts -join ' / ') + '  (in that folder)') Green }
if (Test-Path -LiteralPath (Join-Path $inst 'nx_main\MuMuNxMain.exe')) { Say ' Or "Launch Launcher.cmd" for the device list UI.' Green }
Say '=================================================' Green
Say ' The whole folder can be moved or copied anywhere - it stays portable.'
Read-Host 'Press Enter to finish'
exit 0
