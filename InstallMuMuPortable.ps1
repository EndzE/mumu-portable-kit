# InstallMuMuPortable.ps1 - offline portable MuMu Player 12 Global installer
# Usage: double-click "InstallMuMuPortable.cmd" in the same folder as the
#        MuMu engine exe (MuMu-setup-mumu15-V<version>-<channel>-<build>.exe)

param([string]$Target, [switch]$Yes)

$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
$script:stagingRoot = $null
$script:activeRoot = $null
$script:targetPreExisted = $false
$script:origEnv = @{
    APPDATA        = $env:APPDATA
    LOCALAPPDATA   = $env:LOCALAPPDATA
    TEMP           = $env:TEMP
    TMP            = $env:TMP
    VBOX_USER_HOME = $env:VBOX_USER_HOME
}

function Restore-Environment {
    if (-not $script:origEnv) { return }
    foreach ($k in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'VBOX_USER_HOME')) {
        $val = $script:origEnv[$k]
        if ([string]::IsNullOrEmpty($val)) {
            Remove-Item -Path "Env:\$k" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:\$k" -Value $val
        }
    }
}

function Stop-RunningMuMuHostProcesses {
    & sc.exe stop MuMuPlayerRemoteService 2>&1 | Out-Null
    & sc.exe delete MuMuPlayerRemoteService 2>&1 | Out-Null
    Start-Sleep -Milliseconds 200
    foreach ($pn in @('MuMuPlayerRemoteService', 'MuMuPlayerRemoteBackend', 'MuMuPlayerRemoteHealthd',
                      'MuMuNxMain', 'MuMuNxLauncher', 'MuMuNxService', 'MuMuManager',
                      'MuMuNxDevice', 'MuMuNxSVC', 'MuMuNxHeadless',
                      'MuMuVMMHeadless', 'MuMuVMMSVC', 'MuMuVMMManage')) {
        & taskkill.exe /F /IM "$pn.exe" 2>&1 | Out-Null
    }
    Start-Sleep -Milliseconds 300
}

function Move-DirectoryWithMerge([string]$source, [string]$destination) {
    if (-not (Test-Path -LiteralPath $destination)) {
        Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
        return
    }
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        $destChild = Join-Path $destination $_.Name
        if ($_.PSIsContainer) {
            Move-DirectoryWithMerge $_.FullName $destChild
        } else {
            Move-Item -LiteralPath $_.FullName -Destination $destChild -Force -ErrorAction Stop
        }
    }
    Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
}

function Restore-StagedTarget {
    if (-not $script:stagingRoot) { return }
    $staged = $script:stagingRoot
    $final = $targetFull
    $script:stagingRoot = $null
    if (-not (Test-Path -LiteralPath $staged)) { return }
    Stop-RunningMuMuHostProcesses
    if (-not $script:targetPreExisted) {
        $stagedItems = @(Get-ChildItem -LiteralPath $staged -Force -ErrorAction SilentlyContinue)
        if ($stagedItems.Count -eq 0) {
            Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
        } else {
            Say "[WARN] Incomplete staged install left at $staged (target did not exist prior to install)." Yellow
            $script:activeRoot = $staged
        }
        return
    }
    try {
        Move-DirectoryWithMerge $staged $final
        Say "Moved staged install back to $final." Yellow
        $script:activeRoot = $final
        $script:inst = Join-Path $final 'Netease\MuMuPlayer15'
        $script:data = Join-Path $final 'Data'
        if (Get-Command Update-StagedPaths -ErrorAction SilentlyContinue) {
            $instFinal = Join-Path $final 'Netease\MuMuPlayer15'
            $dataFinal = Join-Path $final 'Data'
            foreach ($root in @((Join-Path $instFinal 'configs'), (Join-Path $instFinal 'nx_device'), (Join-Path $instFinal 'nx_main'), (Join-Path $instFinal 'vms'), (Join-Path $dataFinal 'Roaming'), (Join-Path $dataFinal 'Local'), (Join-Path $dataFinal 'VBox'))) {
                Update-StagedPaths -Root $root -Old $staged -New $final
            }
        }
    } catch {
        Say "[WARN] Could not move staged install back to ${final}: $($_.Exception.Message)" Yellow
        Say "       The staged tree is at $staged" Yellow
        $script:activeRoot = $staged
    }
}

function Get-LogDirectory([string]$tag) {
    $sub = if ($tag -eq 'nxmain') { 'main' } else { $tag }
    $root = if ($script:activeRoot) { $script:activeRoot } elseif ($targetFull) { $targetFull } else { $null }
    if ($root -and (Test-Path -LiteralPath (Join-Path $root 'Data\Temp'))) {
        return (Join-Path $root "Data\Temp\MuMuPlayerGlobal\$sub")
    }
    return (Join-Path $env:TEMP "MuMuPlayerGlobal\$sub")
}

function Get-DriveFreeBytes([string]$driveLetter) {
    if (-not $driveLetter) { return $null }
    try {
        $di = [System.IO.DriveInfo]::new($driveLetter)
        if ($di.IsReady) { return $di.AvailableFreeSpace }
    } catch { }
    try {
        $psd = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
        if ($psd -and $null -ne $psd.Free) { return $psd.Free }
    } catch { }
    return $null
}

function Die($m) { Say "`n[ERROR] $m" Red; Restore-StagedTarget; Restore-Environment; if (-not $Yes) { Read-Host 'Press Enter to exit' }; exit 1 }
trap { Say "`n[ERROR] $_" Red; Restore-StagedTarget; Restore-Environment; if (-not $Yes) { Read-Host 'Press Enter to exit' }; exit 1 }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die 'Run this via "InstallMuMuPortable.cmd" (double-click) so it can request Administrator rights.'
}

Say ''
Say '=== MuMu Player 12 Global - portable offline installer ===' Cyan
Say ''

try {

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
# --- 1b. optional NX main launcher component (nxmain) next to this script ---
$nxmain = $null
$nxVersion = $null
$nxExes = @(Get-ChildItem -LiteralPath $kitDir -File | Where-Object { $_.Name -match '^MuMu-setup-nxmain-V[\d.]+-.*\.exe$' })
if ($nxExes.Count -gt 1) {
    Say 'Multiple nxmain packages found:' Yellow
    $nxExes | ForEach-Object { Say "  $($_.Name)" }
    Die 'Keep only one nxmain exe in the folder (or none at all).'
}
if ($nxExes.Count -eq 1) {
    $nxmain = $nxExes[0].FullName
    $null = $nxExes[0].Name -match '^MuMu-setup-nxmain-V([\d.]+)-'
    $nxVersion = if ($Matches) { $Matches[1] } else { $null }
    Say "nxmain : $($nxExes[0].Name)  (optional - NX main launcher / engine manager)"
    if ($nxExes[0].Name -notmatch 'overseas') { Say 'WARNING: nxmain does not look like an overseas/global build.' Yellow }
}

if ($engines.Count -eq 0 -and -not $nxmain) {
    Die "No engine or launcher package found in:`n  $kitDir`nPut the mumu15 (Android 15), nemux (Android 12), or nxmain (launcher) exe next to this script and retry."
}
$channel = 'gw-overseas12'
if ($engines.Count -gt 0) {
    Say 'Engine package(s):'
    foreach ($e in $engines) { Say "  $($e.name)  ($($engineMap[$e.type].label), version $($e.version))" }
    foreach ($e in $engines) {
        if ($e.name -notmatch 'overseas') { Say "WARNING: $($e.name) does not look like an overseas/global build; the channel value may be wrong." Yellow }
    }
}

# --- 2. target folder ---
$default = 'C:\MuMuPortable'
if (-not $Target) { $Target = Read-Host "Install target folder (the portable root) [$default]" }
if ([string]::IsNullOrWhiteSpace($Target)) { $Target = $default }
$target = $Target.Trim().TrimEnd('\')
if ($target -match '^[A-Za-z]:$') { Die 'Please specify a folder, not a drive root.' }
try { $targetFull = [IO.Path]::GetFullPath($target) } catch { Die "Invalid path: $target" }
$script:activeRoot = $targetFull
if ($targetFull -match '[&|<>^"]') { Die 'Target path contains unsupported characters (& | < > ^ "). Pick a simpler folder name.' }
if ($targetFull.StartsWith('\\')) { Die 'UNC network paths (\\server\share) are not supported. Install to a local drive (e.g. C: or D:).' }

$badDirs = @($env:windir, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } |
    Select-Object -Unique

foreach ($bad in $badDirs) {
    if ($targetFull.Equals($bad, [StringComparison]::OrdinalIgnoreCase) -or
        $targetFull.StartsWith($bad + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Die "Refusing to install into $bad - pick your own folder."
    }
}
$kitDirFull = [IO.Path]::GetFullPath($kitDir).TrimEnd('\')
if ($targetFull -eq $kitDirFull -or $kitDirFull.StartsWith($targetFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Die "Choose a target folder that does not contain the installer kit ($kitDirFull)."
}

function Is-VersionGreater([string]$vNew, [string]$vOld) {
    if ([string]::IsNullOrWhiteSpace($vOld)) { return $true }
    if ([string]::IsNullOrWhiteSpace($vNew)) { return $false }
    try {
        return ([version]$vNew -gt [version]$vOld)
    } catch {
        return ($vNew -ne $vOld)
    }
}

function Get-InstalledEngineVer($cfg, $instPath, [string]$type) {
    $v = $null
    if ($cfg -and $cfg.engines) {
        $eObj = $cfg.engines.$type
        if ($eObj) {
            if ($eObj.version) { $v = [string]$eObj.version }
            elseif ($eObj.player -and $eObj.player.version) { $v = [string]$eObj.player.version }
        }
    }
    if (-not $v) {
        $devExe = Join-Path $instPath ("nx_device\" + $engineMap[$type].dir + "\shell\MuMuNxDevice.exe")
        if (Test-Path -LiteralPath $devExe) {
            try { $v = (Get-Item -LiteralPath $devExe).VersionInfo.FileVersion } catch { }
        }
    }
    return $v
}

$toInstallEngines = @()
$addNxmain = $false
$script:targetPreExisted = Test-Path -LiteralPath $targetFull
if ($script:targetPreExisted) {
    $items = @(Get-ChildItem -LiteralPath $targetFull -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) {
        $instTree = Join-Path $targetFull 'Netease\MuMuPlayer15'
        if (Test-Path -LiteralPath $instTree) {
            $installedCfg = $null
            $cfgGuard = Join-Path $instTree 'configs\main\install_config.json'
            if (Test-Path -LiteralPath $cfgGuard) {
                try { $installedCfg = (Get-Content -LiteralPath $cfgGuard -Raw | ConvertFrom-Json) } catch { }
            }

            $missingOrUpgrade = @()
            foreach ($e in $engines) {
                $devExe = Join-Path $instTree ("nx_device\" + $engineMap[$e.type].dir + "\shell\MuMuNxDevice.exe")
                $installedVer = Get-InstalledEngineVer $installedCfg $instTree $e.type
                $needsInstall = $false

                if (-not (Test-Path -LiteralPath $devExe)) {
                    $needsInstall = $true
                    $missingOrUpgrade += $engineMap[$e.type].label
                } elseif (Is-VersionGreater $e.version $installedVer) {
                    $needsInstall = $true
                    $missingOrUpgrade += "$($engineMap[$e.type].label) (upgrade from $(if ($installedVer) { $installedVer } else { 'unknown' }) to $($e.version))"
                }

                if ($needsInstall) {
                    $toInstallEngines += $e
                }
            }

            if ($nxmain) {
                $instNxExe = Join-Path $instTree 'nx_main\MuMuNxMain.exe'
                $instNxVer = if (Test-Path -LiteralPath $instNxExe) {
                    try { (Get-Item -LiteralPath $instNxExe).VersionInfo.FileVersion } catch { $null }
                } else { $null }

                if (-not (Test-Path -LiteralPath $instNxExe)) {
                    $addNxmain = $true
                    $missingOrUpgrade += 'nxmain (launcher UI)'
                } elseif ($nxVersion -and (Is-VersionGreater $nxVersion $instNxVer)) {
                    $addNxmain = $true
                    $missingOrUpgrade += "nxmain (upgrade from $(if ($instNxVer) { $instNxVer } else { 'unknown' }) to $nxVersion)"
                }
            }

            if ($engines.Count -eq 0) {
                $hasAnyInstalledEngine = $false
                foreach ($t in $engineMap.Keys) {
                    if (Test-Path -LiteralPath (Join-Path $instTree ("nx_device\" + $engineMap[$t].dir + "\shell\MuMuNxDevice.exe"))) {
                        $hasAnyInstalledEngine = $true
                        break
                    }
                }
                if (-not $hasAnyInstalledEngine) {
                    Die "No engine package found in:
  $kitDir
Target $targetFull does not have an installed engine. At least one engine (Android 15 or 12) is required before adding the launcher UI."
                }
            }

            if ($missingOrUpgrade.Count -eq 0) {
                Say "$targetFull already contains a full MuMu install and none of your packages add anything new." Cyan
                $ok = if ($Yes) { 'y' } else { Read-Host 'Refresh the launcher/helper scripts and re-apply engine normalization in place? [Y/n]' }
                if ($ok -match '^(n|no)$') { Die 'Aborted.' }
            } else {
                Say "Existing install found in the target folder. New or updated component(s): $($missingOrUpgrade -join ', ')" Cyan
                $ok = if ($Yes) { 'y' } else { Read-Host 'Install/upgrade them in the existing install? [Y/n]' }
                if ($ok -match '^(n|no)$') { Die 'Aborted.' }
            }
        } else {
            if ($engines.Count -eq 0) {
                Die "No engine package found in:
  $kitDir
Target folder is not a MuMu installation. Put an engine exe next to this script and retry (at least one engine is required)."
            }
            Say 'WARNING: the target folder is not empty.' Yellow
            $ok = if ($Yes) { 'y' } else { Read-Host 'Continue anyway? (existing files are kept untouched) [y/N]' }
            if ($ok -notmatch '^(y|yes)$') { Die 'Aborted.' }
            $toInstallEngines = $engines
            $addNxmain = [bool]$nxmain
        }
    } else {
        if ($engines.Count -eq 0) {
            Die "No engine package found in:
  $kitDir
Put the mumu15 (Android 15) and/or nemux (Android 12) engine exe next to this script and retry (at least one engine is required)."
        }
        $toInstallEngines = $engines
        $addNxmain = [bool]$nxmain
    }
} else {
    if ($engines.Count -eq 0) {
        Die "No engine package found in:
  $kitDir
Put the mumu15 (Android 15) and/or nemux (Android 12) engine exe next to this script and retry (at least one engine is required)."
    }
    $toInstallEngines = $engines
    $addNxmain = [bool]$nxmain
}

$driveName = if ($targetFull -match '^([A-Za-z]):') { $Matches[1] } else { $null }
$sysDriveName = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(':') } else { 'C' }
$needGB = if ($toInstallEngines.Count -gt 0) { 4 + 3 * ($toInstallEngines.Count - 1) } elseif ($addNxmain) { 1 } else { 0 }
$sysNeedGB = if ($toInstallEngines.Count -gt 0) { 2 } else { 1 }

if ($driveName -and $driveName.Equals($sysDriveName, [StringComparison]::OrdinalIgnoreCase)) {
    $extraGB = if ($toInstallEngines.Count -gt 0) { 2 } else { 0 }
    $totalNeedGB = $needGB + $extraGB
    if ($totalNeedGB -gt 0) {
        $free = Get-DriveFreeBytes $driveName
        if ($null -ne $free -and $free -lt ($totalNeedGB * 1GB)) {
            Die ("Not enough free space on ${driveName}: (need about $totalNeedGB GB for portable tree and hypervisor drivers, found {0:N1} GB)." -f ($free / 1GB))
        }
    }
} else {
    if ($driveName -and $needGB -gt 0) {
        $free = Get-DriveFreeBytes $driveName
        if ($null -ne $free -and $free -lt ($needGB * 1GB)) {
            Die ("Not enough free space on ${driveName}: (need about $needGB GB, found {0:N1} GB)." -f ($free / 1GB))
        }
    }
    if ($toInstallEngines.Count -gt 0) {
        $sysFree = Get-DriveFreeBytes $sysDriveName
        if ($null -ne $sysFree -and $sysFree -lt ($sysNeedGB * 1GB)) {
            Die ("Not enough free space on system drive ${sysDriveName}: for hypervisor drivers (need about $sysNeedGB GB, found {0:N1} GB)." -f ($sysFree / 1GB))
        }
    }
}
$mumuProcs = @('MuMuNxDevice', 'MuMuNxSVC', 'MuMuNxHeadless', 'MuMuVMMHeadless', 'MuMuVMMSVC', 'MuMuVMMManage', 'MuMuNxMain', 'MuMuNxLauncher', 'MuMuNxService', 'MuMuManager', 'MuMuPlayerRemoteService', 'MuMuPlayerRemoteBackend', 'MuMuPlayerRemoteHealthd')
$running = @(Get-Process -Name $mumuProcs -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) { Die "MuMu is currently running ($(($running.Name | Select-Object -Unique) -join ', ')) - close it first." }
if ($toInstallEngines.Count -gt 0) {
    $rtDirs = @('C:\Program Files\MuMuNxVbox\Hypervisor', 'C:\Program Files\MuMuVMMVbox\Hypervisor')
    foreach ($t in $engineMap.Keys) {
        $hv = Join-Path $targetFull ('Netease\MuMuPlayer15\nx_device\' + $engineMap[$t].dir + '\hypervisor')
        if (Test-Path -LiteralPath $hv) { $rtDirs += $hv }
    }
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
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(json|vbox|vbox-prev|nemu|xml|ini|cfg|conf)$' })) {
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
    try {
        if ($script:targetPreExisted -and (Test-Path -LiteralPath $targetFull)) {
            Move-Item -LiteralPath $targetFull -Destination $installStaging -ErrorAction Stop
        } else {
            New-Item -ItemType Directory -Path $installStaging -Force | Out-Null
        }
        $script:stagingRoot = $installStaging
        $script:activeRoot = $installStaging
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
    $argList = @(
        "/txn_id=$script:txn",
        "/action=$action",
        "/from_orchestrator=1",
        "/silent=1",
        "/auto_start=false",
        "/product_version=$ver",
        "/fchannel=$channel",
        "/D=$inst"
    )
    Say ''
    Say "--- $tag /action=$action running (can take several minutes, please wait) ---" Cyan
    $p = Start-Process -FilePath $exePath -ArgumentList ($argList -join ' ') -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

function Handle-ComponentFailure([string]$tag, [string]$action, [int]$rc) {
    Say "[FAIL] $tag /action=$action exited with code $rc" Red
    if ($rc -eq 30012) {
        Say 'The hypervisor driver was locked by the kernel (it was loaded before this run).' Yellow
        Say 'REBOOT Windows, then run this installer again - the upgrade will complete then.' Yellow
    }
    Restore-StagedTarget
    $logPath = Get-LogDirectory $tag
    if ($tag -eq 'nxmain') { Say "nxmain logs: $logPath\" Yellow }
    else { Say "Engine logs: $logPath\" Yellow }
    Die "Installation failed during $tag '$action'."
}

function Install-Component([string]$exePath, [string]$tag, [string]$ver) {
    $script:txn = [guid]::NewGuid().ToString()
    $rc = Invoke-ComponentOnce $exePath 'install_prepare' $tag $ver
    $pv = Get-ProductVersion
    if ($rc -eq 80002 -and $pv -and $pv -ne $ver) {
        Say "[retry] $tag was rejected (downgrade check, rc=80002) - retrying with product version $pv" Yellow
        $staleTxn = Join-Path $inst (".txn\" + $script:txn)
        if (Test-Path -LiteralPath $staleTxn) { Remove-Item -LiteralPath $staleTxn -Recurse -Force -ErrorAction SilentlyContinue }
        $script:txn = [guid]::NewGuid().ToString()
        $ver = $pv
        $rc = Invoke-ComponentOnce $exePath 'install_prepare' $tag $ver
    }
    if ($rc -ne 0) { Handle-ComponentFailure $tag 'install_prepare' $rc }
    Say "    [$tag install_prepare] OK" Green

    $rc = Invoke-ComponentOnce $exePath 'commit' $tag $ver
    if ($rc -eq 80002) {
        $pv = Get-ProductVersion
        if ($pv -and $pv -ne $ver) {
            Say "[retry] $tag commit was rejected (downgrade check, rc=80002) - retrying with product version $pv" Yellow
            $rc = Invoke-ComponentOnce $exePath 'commit' $tag $pv
        }
    }
    if ($rc -ne 0) { Handle-ComponentFailure $tag 'commit' $rc }
    Say "    [$tag commit] OK" Green
}

function Invoke-Component([string]$exePath, [string]$action, [string]$tag, [string]$ver) {
    $rc = Invoke-ComponentOnce $exePath $action $tag $ver
    $pv = Get-ProductVersion
    if ($rc -eq 80002 -and $pv -and $pv -ne $ver) {
        Say "[retry] $tag was rejected (downgrade check, rc=80002) - retrying with product version $pv" Yellow
        $staleTxn = Join-Path $inst (".txn\" + $script:txn)
        if (Test-Path -LiteralPath $staleTxn) { Remove-Item -LiteralPath $staleTxn -Recurse -Force -ErrorAction SilentlyContinue }
        $script:txn = [guid]::NewGuid().ToString()
        $rc = Invoke-ComponentOnce $exePath $action $tag $pv
    }
    if ($rc -ne 0) { Handle-ComponentFailure $tag $action $rc }
    Say "    [$tag $action] OK" Green
}

foreach ($e in $toInstallEngines) {
    Say ''
    Say "--- Engine: $($e.name)  ($($engineMap[$e.type].label)) ---" Cyan
    Install-Component $e.path $e.type $e.version
    if (-not (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $engineMap[$e.type].dir + "\shell\MuMuNxDevice.exe")))) {
        Restore-StagedTarget
        $logPath = Get-LogDirectory $e.type
        Say "Engine logs: $logPath\" Yellow
        $finalInst = Join-Path (if ($script:activeRoot) { $script:activeRoot } else { $targetFull }) 'Netease\MuMuPlayer15'
        Die "The $($e.type) engine finished but the install tree looks incomplete ($finalInst). Check the engine logs."
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
    $nxVer = if ($pv = (Get-ProductVersion)) { $pv } elseif ($nxVersion) { $nxVersion } else { '1.0.0.0' }
    Install-Component $nxmain 'nxmain' $nxVer
    if (-not (Test-Path -LiteralPath "$inst\nx_main\MuMuNxMain.exe")) {
        Restore-StagedTarget
        $logPath = Get-LogDirectory 'nxmain'
        Say "nxmain logs: $logPath\" Yellow
        $finalInst = Join-Path (if ($script:activeRoot) { $script:activeRoot } else { $targetFull }) 'Netease\MuMuPlayer15'
        Die "nxmain finished but '$finalInst\nx_main\MuMuNxMain.exe' is missing. Check the logs above."
    }
    Say 'nxmain installed (launcher UI included).' Green
}

# --- move the staged tree back to the requested path before host repair/scripts ---
Stop-RunningMuMuHostProcesses
if ($installStaging) {
    Move-DirectoryWithMerge $installStaging $targetFull
    $script:stagingRoot = $null
    $script:activeRoot = $targetFull
    $installRoot = $targetFull
    $inst = Join-Path $targetFull 'Netease\MuMuPlayer15'
    $data = Join-Path $targetFull 'Data'
    $env:APPDATA = "$data\Roaming"
    $env:LOCALAPPDATA = "$data\Local"
    $env:TEMP = "$data\Temp"
    $env:TMP = "$data\Temp"
    $env:VBOX_USER_HOME = "$data\VBox"
    Say "Staged install moved to $targetFull." Green
    foreach ($root in @((Join-Path $inst 'configs'), (Join-Path $inst 'nx_device'), (Join-Path $inst 'nx_main'), (Join-Path $inst 'vms'), (Join-Path $data 'Roaming'), (Join-Path $data 'Local'), (Join-Path $data 'VBox'))) {
        Update-StagedPaths -Root $root -Old $installStaging -New $targetFull
    }
}

# --- 3c. note: host normalization (C:\Program Files runtime, COM registration, driver family) ---
# Moved to Step 6 so host mutations are consolidated and respect the user's opt-in choice.

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

rem --- keep paths in sync with this folder's location (portable move support) ---
set "MUMU_ROOT=%ROOT%"
set "MUMU_CFG=%INST%\configs\main\vm_config.json"
if exist "%MUMU_CFG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:MUMU_CFG; $newRoot=$env:MUMU_ROOT; $p=Join-Path $newRoot 'Data\MuMuSharedFolder'; try { $j=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; $oldP=$j.vm.sharefolder.user.path; if ($oldP -and $oldP -ne $p) { $oldRoot=$oldP.Substring(0, $oldP.Length - '\Data\MuMuSharedFolder'.Length); $j.vm.sharefolder.user.path=$p; [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false))); if ($oldRoot -and (Test-Path -LiteralPath $newRoot)) { foreach ($ext in @('*.json','*.vbox','*.xml','*.nemu','*.ini')) { foreach ($file in @(Get-ChildItem -LiteralPath $newRoot -Recurse -File -Filter $ext -ErrorAction SilentlyContinue)) { try { $txt=[IO.File]::ReadAllText($file.FullName); if ($txt.Contains($oldRoot)) { $upd=$txt.Replace($oldRoot,$newRoot).Replace($oldRoot.Replace('\','\\'),$newRoot.Replace('\','\\')).Replace($oldRoot.Replace('\','/'),$newRoot.Replace('\','/')); [IO.File]::WriteAllText($file.FullName, $upd, (New-Object Text.UTF8Encoding($false))) } } catch {} } } } } } catch {}"
set "MUMU_ROOT="
set "MUMU_CFG="

sc query @@SVC@@ 2>nul | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
  echo [WARN] MuMu driver (@@SVC@@) is not installed or not running on this PC.
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

rem --- keep paths in sync with this folder's location (portable move support) ---
set "MUMU_ROOT=%ROOT%"
set "MUMU_CFG=%INST%\configs\main\vm_config.json"
if exist "%MUMU_CFG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:MUMU_CFG; $newRoot=$env:MUMU_ROOT; $p=Join-Path $newRoot 'Data\MuMuSharedFolder'; try { $j=Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; $oldP=$j.vm.sharefolder.user.path; if ($oldP -and $oldP -ne $p) { $oldRoot=$oldP.Substring(0, $oldP.Length - '\Data\MuMuSharedFolder'.Length); $j.vm.sharefolder.user.path=$p; [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false))); if ($oldRoot -and (Test-Path -LiteralPath $newRoot)) { foreach ($ext in @('*.json','*.vbox','*.xml','*.nemu','*.ini')) { foreach ($file in @(Get-ChildItem -LiteralPath $newRoot -Recurse -File -Filter $ext -ErrorAction SilentlyContinue)) { try { $txt=[IO.File]::ReadAllText($file.FullName); if ($txt.Contains($oldRoot)) { $upd=$txt.Replace($oldRoot,$newRoot).Replace($oldRoot.Replace('\','\\'),$newRoot.Replace('\','\\')).Replace($oldRoot.Replace('\','/'),$newRoot.Replace('\','/')); [IO.File]::WriteAllText($file.FullName, $upd, (New-Object Text.UTF8Encoding($false))) } } catch {} } } } } } catch {}"
set "MUMU_ROOT="
set "MUMU_CFG="

set "DRV_OK="
sc query MuMuVMMDrv 2>nul | findstr "RUNNING" >nul 2>&1 && set "DRV_OK=1"
sc query MuMuNxSup 2>nul | findstr "RUNNING" >nul 2>&1 && set "DRV_OK=1"
if not defined DRV_OK (
  echo [WARN] MuMu driver (MuMuVMMDrv/MuMuNxSup) is not installed or not running on this PC.
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
foreach ($t in $engineMap.Keys) {
    $m = $engineMap[$t]
    if (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $m.dir + "\shell\MuMuNxDevice.exe"))) {
        $content = $launchEngineTpl.Replace('@@A@@', $m.dir).Replace('@@SVC@@', $m.svc)
        [IO.File]::WriteAllText((Join-Path $targetFull ("Launch " + $m.label + ".cmd")), $content, (New-Object Text.UTF8Encoding($false)))
        Say "Launch script ready: Launch $($m.label).cmd"
    }
}
if (Test-Path -LiteralPath (Join-Path $inst 'nx_main\MuMuNxMain.exe')) {
    [IO.File]::WriteAllText((Join-Path $targetFull 'Launch Launcher.cmd'), $launchLauncher, (New-Object Text.UTF8Encoding($false)))
    Say 'Launch script ready: Launch Launcher.cmd'
}

$enableEngineBlocks = foreach ($t in $engineMap.Keys) {
    $m = $engineMap[$t]
    $pf = 'C:\Program Files\' + $m.installName + '\Hypervisor'
    $pfLd = 'C:\Program Files\' + $m.installName + '\LoadedDrivers'
    @"
if exist "%INST%\nx_device\$($m.dir)\hypervisor\load.cmd" (
  echo --- $($m.label) ---
  if not exist "$pf" md "$pf"
  xcopy "%INST%\nx_device\$($m.dir)\hypervisor" "$pf" /E /I /Y /Q
  if errorlevel 1 echo [WARN] $($m.label) runtime copy failed.
  if exist "%INST%\nx_device\$($m.dir)\LoadedDrivers" (
    if not exist "$pfLd" md "$pfLd"
    xcopy "%INST%\nx_device\$($m.dir)\LoadedDrivers" "$pfLd" /E /I /Y /Q
    if errorlevel 1 echo [WARN] $($m.label) driver copy failed.
  )
  if exist "$pf\load.cmd" (
    pushd "$pf"
    if exist comregister.cmd call comregister.cmd
    call load.cmd
    if exist loadlwf.cmd call loadlwf.cmd
    popd
  ) else (
    pushd "%INST%\nx_device\$($m.dir)\hypervisor"
    if exist comregister.cmd call comregister.cmd
    call load.cmd
    if exist loadlwf.cmd call loadlwf.cmd
    popd
  )
)
"@
}
$enableEngineBlocks = $enableEngineBlocks -join "`r`n"

$enable = @'
@echo off
setlocal EnableExtensions
net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  set "SELF=%~f0"
  powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
  exit /b
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
[IO.File]::WriteAllText((Join-Path $targetFull 'Enable-Driver.cmd'), $enable, (New-Object Text.UTF8Encoding($false)))

$blockInternet = @'
@echo off
setlocal EnableExtensions

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  set "SELF=%~f0"
  powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
  exit /b
)

echo MuMu Player - offline mode: block ALL MuMu network access
echo ========================================================
echo Adds Inbound + Outbound BLOCK rules for every MuMu executable.
echo Folder-specific executables are tagged for THIS folder; shared
echo C:\Program Files runtimes (Hypervisor\*.exe) are tagged as shared.
echo Block rules override the allow rules MuMu's own installers added,
echo so the emulator runs fully offline. Local device use, adb and
echo the shared folder are unaffected (no loopback filtering).
echo Re-run this script after moving the folder or updating a
echo component. Run Allow-Internet.cmd to unblock.
echo.

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MUMU_ROOT=%ROOT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$g='MuMu Portable Offline ('+$env:MUMU_ROOT+')';$gShared='MuMu Portable Offline (Shared Runtime)';$t=Join-Path $env:MUMU_ROOT 'Netease\MuMuPlayer15';$x=@();if(Test-Path -LiteralPath $t){$x+=Get-ChildItem -LiteralPath $t -Recurse -Filter *.exe -ErrorAction SilentlyContinue};$xShared=@();foreach($p in 'C:\Program Files\MuMuNxVbox\Hypervisor','C:\Program Files\MuMuVMMVbox\Hypervisor'){if(Test-Path -LiteralPath $p){$xShared+=Get-ChildItem -LiteralPath $p -Recurse -Filter *.exe -ErrorAction SilentlyContinue}};$old=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group $gShared -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group 'MuMu Portable Offline' -ErrorAction SilentlyContinue);if($old.Count){$old|Remove-NetFirewallRule};foreach($e in $x){New-NetFirewallRule -DisplayName ('MuMuOffline '+$e.Name+' out') -Group $g -Program $e.FullName -Direction Outbound -Action Block -Profile Any|Out-Null;New-NetFirewallRule -DisplayName ('MuMuOffline '+$e.Name+' in') -Group $g -Program $e.FullName -Direction Inbound -Action Block -Profile Any|Out-Null};foreach($e in $xShared){New-NetFirewallRule -DisplayName ('MuMuOffline Shared '+$e.Name+' out') -Group $gShared -Program $e.FullName -Direction Outbound -Action Block -Profile Any|Out-Null;New-NetFirewallRule -DisplayName ('MuMuOffline Shared '+$e.Name+' in') -Group $gShared -Program $e.FullName -Direction Inbound -Action Block -Profile Any|Out-Null};$totalExes=@($x)+@($xShared);$n=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group $gShared -ErrorAction SilentlyContinue);'Blocked exes: '+$totalExes.Count+' (portable: '+@($x).Count+', shared: '+@($xShared).Count+')   rules now: '+$n.Count+'   (stale removed: '+$old.Count+')'"
set "MUMU_ROOT="
echo.
pause
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'Block-Internet.cmd'), $blockInternet, (New-Object Text.UTF8Encoding($false)))

$allowInternet = @'
@echo off
setlocal EnableExtensions

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  set "SELF=%~f0"
  powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
  exit /b
)

echo MuMu Player - leave offline mode (allow network access again)
echo ============================================================
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MUMU_ROOT=%ROOT%"
powershell -NoProfile -Command "$g='MuMu Portable Offline ('+$env:MUMU_ROOT+')';$gShared='MuMu Portable Offline (Shared Runtime)';$r=@(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group $gShared -ErrorAction SilentlyContinue)+@(Get-NetFirewallRule -Group 'MuMu Portable Offline' -ErrorAction SilentlyContinue);if($r.Count){$r|Remove-NetFirewallRule;'Removed offline block rules: '+$r.Count}else{'No offline block rules present.'}"
set "MUMU_ROOT="
echo.
pause
'@
[IO.File]::WriteAllText((Join-Path $targetFull 'Allow-Internet.cmd'), $allowInternet, (New-Object Text.UTF8Encoding($false)))
Say 'Offline scripts ready: Block-Internet.cmd / Allow-Internet.cmd'

$disable = @'
@echo off
setlocal EnableExtensions
net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  set "SELF=%~f0"
  powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
  exit /b
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
powershell -NoProfile -Command "$hits=@(try{Get-WindowsDriver -Online -ErrorAction Stop|Where-Object{$_.OriginalFileName -match 'mumu' -or $_.ProviderName -match 'mumu|netease'}|ForEach-Object{$_.Driver}}catch{@()});if(-not $hits){$cur=$null;foreach($l in [string[]](pnputil /enum-drivers)){if($l -match ':\s*(oem\d+\.inf)'){$cur=$Matches[1]}elseif($cur -and ($l -match ':\s*(.*)') -and ($Matches[1] -match 'mumu|netease')){$hits+=$cur;$cur=$null}}};$hits=@($hits|Select-Object -Unique);foreach($h in $hits){pnputil /delete-driver $h /uninstall /force|Out-Null};if($hits.Count){'Removed driver packages: '+($hits -join ', ')}else{'No MuMu driver packages present'}"
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
rem --- remove empty .MUMUVMM user dir and stray VirtualBox xml if present ---
if exist "%USERPROFILE%\.MUMUVMM" rmdir "%USERPROFILE%\.MUMUVMM" >nul 2>&1
del /f /q "%USERPROFILE%\-*-windows.xml" >nul 2>&1
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
[IO.File]::WriteAllText((Join-Path $targetFull 'Disable-Driver.cmd'), $disable, (New-Object Text.UTF8Encoding($false)))

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
[IO.File]::WriteAllText((Join-Path $targetFull 'README.txt'), $readme, (New-Object Text.UTF8Encoding($false)))

# --- 6. driver: enable on this PC (optional) ---
Say ''
$a = if ($Yes) { 'y' } else { Read-Host 'Enable the emulator driver on THIS PC now? (one-time, needed to run the emulator here) [Y/n]' }
if ($a -match '^(n|no)$') {
    Say 'Skipped. Unloading any driver installed during setup (run Enable-Driver.cmd later to use on any PC)...' Yellow
    foreach ($t in $engineMap.Keys) {
        $m = $engineMap[$t]
        $pfHv = Join-Path 'C:\Program Files' ($m.installName + '\Hypervisor')
        $hv = Join-Path $inst ("nx_device\" + $m.dir + "\hypervisor")
        $unTarget = if (Test-Path -LiteralPath (Join-Path $pfHv 'load.cmd')) { $pfHv } elseif (Test-Path -LiteralPath (Join-Path $hv 'load.cmd')) { $hv } else { $null }
        if ($unTarget) {
            Push-Location -LiteralPath $unTarget
            try { & cmd.exe /c 'load.cmd --uninstall' } finally { Pop-Location }
        }
    }
    foreach ($svcOld in 'MuMuVMMDrv', 'MuMuNxSup', 'MuMuVMMNetLwf', 'MuMuNxNetLwf') {
        & sc.exe stop $svcOld 2>&1 | Out-Null
        & sc.exe delete $svcOld 2>&1 | Out-Null
    }
    foreach ($sys in 'MuMuVMMNetLwf.sys', 'MuMuNxNetLwf.sys') {
        $sp = Join-Path "$env:SystemRoot\System32\drivers" $sys
        if (Test-Path -LiteralPath $sp) { Remove-Item -LiteralPath $sp -Force -ErrorAction SilentlyContinue }
    }
    foreach ($p in 'MuMuNxVbox', 'MuMuVMMVbox') {
        $pfDir = Join-Path 'C:\Program Files' $p
        if (Test-Path -LiteralPath $pfDir) { Remove-Item -LiteralPath $pfDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $uProf = [Environment]::GetFolderPath('UserProfile')
    $mumuVmm = Join-Path $uProf '.MUMUVMM'
    if ((Test-Path -LiteralPath $mumuVmm) -and -not (Get-ChildItem -LiteralPath $mumuVmm -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Remove-Item -LiteralPath $mumuVmm -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $uProf -Filter '-*-windows.xml' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
else {
    foreach ($t in $engineMap.Keys) {
        $m = $engineMap[$t]
        $hv = Join-Path $inst ("nx_device\" + $m.dir + "\hypervisor")
        if (-not (Test-Path -LiteralPath $hv)) { continue }
        $pfRoot = Join-Path 'C:\Program Files' $m.installName
        $pfDir = Join-Path $pfRoot 'Hypervisor'
        $pfLd = Join-Path $pfRoot 'LoadedDrivers'
        $ld = Join-Path $inst ("nx_device\" + $m.dir + "\LoadedDrivers")
        if (-not (Test-Path -LiteralPath (Join-Path $pfDir $m.svcExe))) {
            Say "Restoring $($m.label) hypervisor runtime to C:\Program Files\$($m.installName)..."
            try {
                New-Item -ItemType Directory -Path $pfDir -Force | Out-Null
                Get-ChildItem -LiteralPath $hv | Copy-Item -Destination $pfDir -Recurse -Force
            } catch { Say "[WARN] Could not restore the runtime: $($_.Exception.Message)" Yellow }
        }
        if ((Test-Path -LiteralPath $ld) -and (-not (Test-Path -LiteralPath (Join-Path $pfLd ($m.svc + '.sys'))))) {
            Say "Restoring $($m.label) drivers to C:\Program Files\$($m.installName)..."
            try {
                New-Item -ItemType Directory -Path $pfLd -Force | Out-Null
                Get-ChildItem -LiteralPath $ld | Copy-Item -Destination $pfLd -Recurse -Force
            } catch { Say "[WARN] Could not restore the drivers: $($_.Exception.Message)" Yellow }
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
        $loadTarget = if (Test-Path -LiteralPath (Join-Path $pfDir 'load.cmd')) { $pfDir } else { $hv }
        $svcStatus = & sc.exe query $m.svc 2>&1 | Out-String
        if (($svcStatus -notmatch 'SERVICE_NAME') -and (Test-Path -LiteralPath (Join-Path $loadTarget 'load.cmd'))) {
            Say "Installing $($m.label) driver family..."
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $loadTarget + '" && load.cmd') -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) driver install exited with $($p.ExitCode)" Yellow }
        } elseif ($svcStatus -match 'SERVICE_NAME' -and $svcStatus -notmatch 'RUNNING') {
            Say "Starting $($m.label) driver service ($($m.svc))..."
            & sc.exe start $m.svc 2>&1 | Out-Null
        }
        if ((-not ((& sc.exe query $m.netSvc 2>&1 | Out-String) -match 'SERVICE_NAME')) -and (Test-Path -LiteralPath (Join-Path $loadTarget 'loadlwf.cmd'))) {
            Say "Installing $($m.label) network filter..."
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('cd /d "' + $loadTarget + '" && loadlwf.cmd') -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { Say "[WARN] $($m.label) network filter exited with $($p.ExitCode)" Yellow }
        }
    }
    Say 'Driver status:'
    foreach ($t in $engineMap.Keys) {
        $m = $engineMap[$t]
        if (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $m.dir))) {
            & sc.exe query $m.svc
        }
    }
}

# --- 7. remove engine/nxmain-written host traces (known-folder APIs ignore the env redirects above) ---
$realAppData = [Environment]::GetFolderPath('ApplicationData')
$icfgDir = Join-Path $realAppData 'Netease\MuMuPlayerGlobal'
foreach ($f2 in @('install_config.json', 'new_install.json')) {
    $p = Join-Path $icfgDir $f2
    if (Test-Path -LiteralPath $p) {
        try {
            Remove-Item -LiteralPath $p -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $p)) {
                Say "Removed engine install record: $p"
            }
        } catch { }
    }
}
$hcfg = Join-Path $realAppData 'Netease\MuMuNx\hypervisor_config.json'
if (Test-Path -LiteralPath $hcfg) {
    try {
        Remove-Item -LiteralPath $hcfg -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $hcfg)) {
            Say "Removed engine install record: $hcfg"
        }
    } catch { }
}
foreach ($d in @((Join-Path $icfgDir 'data'), $icfgDir, (Join-Path $realAppData 'Netease\MuMuNx'), (Join-Path $realAppData 'Netease'))) {
    if ((Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop } catch { }
    }
}

# --- 7b. NX launcher (nxmain) host traces: shortcuts, autostart, uninstall entry, remote service ---
$deskLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MuMuPlayer.lnk'
if (Test-Path -LiteralPath $deskLnk) {
    try {
        Remove-Item -LiteralPath $deskLnk -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $deskLnk)) {
            Say "Removed desktop shortcut: $deskLnk"
        }
    } catch { }
}
$smpDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'MuMuPlayer'
if (Test-Path -LiteralPath $smpDir) {
    try {
        Remove-Item -LiteralPath $smpDir -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $smpDir)) {
            Say "Removed Start Menu folder: $smpDir"
        }
    } catch { }
}
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'MuMuPlayerGlobal' -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MuMuPlayerGlobal' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Netease\MuMuPlayerRemote' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Netease\MuMuPlayerRemoteSetup' -Recurse -Force -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Netease') -and -not (Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Netease' -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    try { Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Netease' -Force -ErrorAction Stop } catch { }
}
Remove-Item -Path 'HKLM:\SOFTWARE\WOW6432Node\NemuServer' -Recurse -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'
Stop-RunningMuMuHostProcesses
foreach ($d in @("$env:ProgramData\Netease\MuMuPlayerGlobal", "$env:ProgramData\Netease\MumuPlayerRemote")) {
    if (Test-Path -LiteralPath $d) {
        try {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $d)) {
                Say "Removed launcher runtime traces: $d"
            }
        } catch { }
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
$uProf = [Environment]::GetFolderPath('UserProfile')
$mumuVmm = Join-Path $uProf '.MUMUVMM'
if ((Test-Path -LiteralPath $mumuVmm) -and -not (Get-ChildItem -LiteralPath $mumuVmm -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    try { Remove-Item -LiteralPath $mumuVmm -Force -ErrorAction Stop; Say 'Removed empty %USERPROFILE%\.MUMUVMM' } catch { }
}
$vboxXmls = @(Get-ChildItem -LiteralPath $uProf -Filter '-*-windows.xml' -Force -ErrorAction SilentlyContinue)
foreach ($x in $vboxXmls) {
    try { Remove-Item -LiteralPath $x.FullName -Force -ErrorAction Stop; Say "Removed VirtualBox machine trace: $($x.FullName)" } catch { }
}

Say ''
Say '=================================================' Green
Say " Portable MuMu installed in: $targetFull" Green
$sumScripts = @()
foreach ($t in $engineMap.Keys) {
    $m = $engineMap[$t]
    if (Test-Path -LiteralPath (Join-Path $inst ("nx_device\" + $m.dir + "\shell\MuMuNxDevice.exe"))) {
        $sumScripts += '"Launch ' + $m.label + '.cmd"'
    }
}
if ($sumScripts) { Say (' Start with: ' + ($sumScripts -join ' / ') + '  (in that folder)') Green }
if (Test-Path -LiteralPath (Join-Path $inst 'nx_main\MuMuNxMain.exe')) { Say ' Or "Launch Launcher.cmd" for the device list UI.' Green }
Say '=================================================' Green
Say ' The whole folder can be moved or copied anywhere - it stays portable.'
Restore-Environment
if (-not $Yes) { Read-Host 'Press Enter to finish' }
exit 0
} finally {
    Restore-Environment
}
