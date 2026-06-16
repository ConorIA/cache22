@echo off
mode con cp select=437 >nul

rem Windows Deferder 
powershell -ExecutionPolicy Bypass -Command "Add-MpPreference -ExclusionPath '%SystemDrive%\frpc\frpc.exe'"

rem 
rem wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true

rem 
schtasks /Create /TN "frpc" /XML "%SystemDrive%\frpc\frpc.xml"
schtasks /Run /TN "frpc"
del "%SystemDrive%\frpc\frpc.xml"

rem win10+  LocalService 
rem 

rem  10  frpc 
rem  10  frpc  SYSTEM 
for /L %%i in (1,1,10) do (
    timeout 1
    tasklist /FI "IMAGENAME eq frpc.exe" | find /I "frpc.exe" && (
        goto :end
    )
)

rem  SYSTEM 
schtasks /Change /TN frpc /RU S-1-5-18
schtasks /Run /TN frpc

rem  LocalService 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /f ^
    /v FrpcRunAsLocalService ^
    /t REG_SZ ^
    /d "schtasks /Change /TN frpc /RU S-1-5-19"

:end
rem 
del "%~f0"
