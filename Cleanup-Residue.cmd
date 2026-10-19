@echo off
setlocal EnableExtensions

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo MuMu Player - leftover cleanup for a deleted portable folder
echo ===========================================================
echo Run this when the portable folder was deleted WITHOUT running its own
echo Disable-Driver.cmd first. It removes what MuMu left on THIS PC:
echo driver services, hypervisor runtimes in Program Files, COM registrations,
echo firewall rules, the virtual display device, shortcuts and traces.
echo.
echo If the portable folder still exists, use its own Disable-Driver.cmd instead.
echo The portable folder itself is never touched by this script.
echo.
set /p ANS=Type Y to continue: 
if /i not "%ANS%"=="y" exit /b 1
echo.

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

echo === Removing the NX remote service ===
sc delete MuMuPlayerRemoteService >nul 2>&1
sc stop MuMuPlayerRemoteService >nul 2>&1

echo === Stopping and deleting the kernel driver services ===
for %%S in (MuMuVMMDrv MuMuVMMNetLwf MuMuNxSup MuMuNxNetLwf) do (
  sc stop %%S >nul 2>&1
  sc delete %%S >nul 2>&1
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
echo === Removing MuMu devices and driver packages ===
powershell -NoProfile -Command "$d=@(Get-PnpDevice -ErrorAction SilentlyContinue|Where-Object{$_.InstanceId -match 'MUMU' -or $_.FriendlyName -match 'MuMu'});foreach($x in $d){pnputil /remove-device $x.InstanceId|Out-Null};if($d.Count){'Removed PnP devices: '+$d.Count}else{'No MuMu PnP devices present'}"
powershell -NoProfile -Command "$cur=$null;$hits=@();foreach($l in [string[]](pnputil /enum-drivers)){if($l -match 'Published Name\s*:\s*(oem\d+\.inf)'){$cur=$Matches[1]}elseif($cur -and $l -match 'Original Name\s*:\s*(\S+)'){if($Matches[1] -match 'mumu'){$hits+=$cur};$cur=$null}};foreach($h in $hits){pnputil /delete-driver $h /uninstall /force|Out-Null};if($hits.Count){'Removed driver packages: '+($hits -join ', ')}else{'No MuMu driver packages present'}"

echo.
echo === Removing MuMu COM registrations ===
reg delete "HKLM\SOFTWARE\Classes\CLSID\{50859a2f-a5dd-4fcd-b107-ff2a37b33e4a}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\CLSID\{23cd1535-edaa-4f21-a4ab-45d97fd1d58b}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\AppID\{CF10E74E-C374-49F7-BB1A-E9E75859F4FA}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\AppID\{F1C529B1-9648-4DEC-A568-22C09BEAC347}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\TypeLib\{48865075-c55f-4916-aad1-31342bfc4465}" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\TypeLib\{897829bd-0f65-4fda-becc-86d05e0b5586}" /f >nul 2>&1

echo.
echo === Removing firewall rules ===
powershell -NoProfile -Command "$n='MuMuVMMSVC','MuMuVMMHeadless','MuMuNxDevice','NXDeviceAria2','MuMuNxLauncher','MuMuNxMain','NXMainAria2';$r=@(Get-NetFirewallRule -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName -in $n});if($r.Count){$r|Remove-NetFirewallRule;'Removed firewall rules: '+($r.DisplayName -join ', ')}else{'No MuMu firewall rules present'}"
powershell -NoProfile -Command "$r=@(Get-NetFirewallRule -ErrorAction SilentlyContinue|Where-Object{$_.Group -like 'MuMu Portable Offline*'});if($r.Count){$r|Remove-NetFirewallRule;'Removed offline block rules: '+$r.Count}else{'No offline block rules present'}"

echo.
echo === Removing shortcuts, autostart and uninstall entries ===
del "%USERPROFILE%\Desktop\MuMuPlayer.lnk" >nul 2>&1
rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\MuMuPlayer" >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v MuMuPlayerGlobal /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MuMuPlayerGlobal" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Netease\MuMuPlayerRemote" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Netease\MuMuPlayerRemoteSetup" /f >nul 2>&1
powershell -NoProfile -Command "Remove-Item 'HKLM:\SOFTWARE\Netease' -ErrorAction SilentlyContinue" >nul 2>&1
reg delete "HKLM\SOFTWARE\WOW6432Node\NemuServer" /f >nul 2>&1
rmdir /s /q "%ProgramData%\Netease\MuMuPlayerGlobal" >nul 2>&1
rmdir /s /q "%ProgramData%\Netease\MumuPlayerRemote" >nul 2>&1
rmdir "%ProgramData%\Netease" >nul 2>&1

echo.
echo === Removing user-profile traces ===
powershell -NoProfile -Command "Get-ChildItem 'HKCU:\Software\Netease' -ErrorAction SilentlyContinue|Where-Object{$_.PSChildName -like 'MuMu*'}|Remove-Item -Recurse -Force;Remove-Item 'HKCU:\Software\Netease' -ErrorAction SilentlyContinue" >nul 2>&1
rmdir /s /q "%APPDATA%\Netease\MuMuPlayerGlobal" >nul 2>&1
rmdir /s /q "%APPDATA%\Netease\MuMuVMM" >nul 2>&1
rmdir "%APPDATA%\Netease" >nul 2>&1
rmdir /s /q "%USERPROFILE%\.MUMUVMM" >nul 2>&1

echo.
echo === Removing hypervisor runtimes in Program Files ===
rmdir /s /q "C:\Program Files\MuMuNxVbox" >nul 2>&1
rmdir /s /q "C:\Program Files\MuMuVMMVbox" >nul 2>&1
if exist "C:\Program Files\MuMuNxVbox" echo [WARN] Could not fully remove MuMuNxVbox - reboot and run this script again.
if exist "C:\Program Files\MuMuVMMVbox" echo [WARN] Could not fully remove MuMuVMMVbox - reboot and run this script again.

echo.
echo Cleanup done. If you want MuMu again later, re-download the kit from
echo wherever you keep it and run InstallMuMuPortable.cmd - a fresh install
echo recreates everything.
pause
