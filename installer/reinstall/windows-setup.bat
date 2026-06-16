@echo off
mode con cp select=437 >nul

rem  setup.exe
rename X:\setup.exe.disabled setup.exe

rem  10 
cls
for /l %%i in (10,-1,1) do (
    echo Press Ctrl+C within %%i seconds to cancel the automatic installation.
    call :sleep 1000
    cls
)

rem win7 find  65001  win 7
rem findstr  findstr
rem echo a | find "a"

rem 
rem https://learn.microsoft.com/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim
rem win8 pe  powercfg
powercfg /s SCHEME_MIN 2>nul

rem  SCSI 
if exist X:\drivers\ (
    for /f "delims=" %%F in ('dir /s /b "X:\drivers\*.inf" 2^>nul') do (
        call :drvload_if_scsi "%%~F"
    )

    rem 
    rem Gcore  virtio-gpu 
    rem 
    rem 
    rem find /i "viogpudo" "%%~F" >nul
    rem if not errorlevel 1 (
    rem     drvload "%%~F"
    rem )
)

rem  SCSI 
rem  forfiles /p X:\custom_drivers /m *.inf /c "cmd /c echo @path"
rem  for %%F in ("X:\custom_drivers\*\*.inf")
if exist X:\custom_drivers\ (
    for /f "delims=" %%F in ('dir /s /b "X:\custom_drivers\*.inf" 2^>nul') do (
        call :drvload_if_scsi "%%~F"
    )
)

rem 
call :sleep 5000
echo rescan | diskpart
call :sleep 5000

rem  ProductType
rem for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions" /v ProductType') do (
rem     set "ProductType=%%a"
rem )

rem  installer  id
for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| find " installer "') do (
    set "VolIndex=%%a"
)

rem 
if "%VolIndex%"=="" (
    echo Error: Cannot find installer partition. >&2
    exit /b 1
)

rem  installer  Y 
(echo select vol %VolIndex% & echo assign letter=Y) | diskpart

rem  C 
rem (24h2)
rem  installer 
call :createPageFile

rem 
rem wmic pagefile

rem  id
rem vista pe  wmic diskpart

rem  win7 diskpart  chcp 437
rem (echo select vol %VolIndex% & echo list disk) | diskpart | find "* Disk " > X:\disk.txt
rem for /f "tokens=3" %%a in (X:\disk.txt) do (
rem     set "DiskIndex=%%a"
rem )

rem PE  findstr diskpart  * 

rem  diskpart 
(echo select vol %VolIndex% & echo list disk) | diskpart | find "* " > X:\disk.txt
type X:\disk.txt

rem 
setlocal enabledelayedexpansion
for /f "delims=" %%a in (X:\disk.txt) do (
    set "line=%%a"

    rem  * 
    call :is_x_starts_with_char_y "!line!" "*" && (
        rem  for %%b in (!safe_line!) do  *  *
        rem  *  * 

        rem for /f 
        for /f "tokens=1 delims=*" %%i in ("!line!") do (
            set "safe_line=%%i"
        )

        rem 
        for %%b in (!safe_line!) do (
            call :is_number "%%b" && (
                set "DiskIndex=%%b"
                goto :found_main_disk
            )
        )

        rem  for “”“”%%b
        rem for /f   “”“”%%i, %%j...
    )
)

:not_found_main_disk
echo Error: Cannot find main disk. >&2
exit /b 1

:found_main_disk
del X:\disk.txt
endlocal & set "DiskIndex=%DiskIndex%"

rem  efi  bios
rem  https://learn.microsoft.com/windows-hardware/manufacture/desktop/boot-to-uefi-mode-or-legacy-bios-mode
rem pe  mountvol
echo list vol | diskpart | find " efi " && (
    set BootType=efi
) || (
    set BootType=bios
)

rem  trans.sh 
set is4kn=0
if "%is4kn%"=="1" (
    set EFISize=260
) else (
    set EFISize=100
)

rem /
(if "%BootType%"=="efi" (
    echo select disk %DiskIndex%

    rem del
    echo select part 1
    echo delete part override
    echo select part 2
    echo delete part override
    echo select part 3
    echo delete part override

    rem 1
    echo create part efi size=%EFISize%
    echo format fs=fat32 quick

    rem 2
    echo create part msr size=16

    rem 3
    echo create part primary
    echo format fs=ntfs quick
    rem echo assign letter=Z

) else (
    echo select disk %DiskIndex%

    rem del
    echo select part 1
    echo delete part override

    rem 1
    echo create part primary
    echo format fs=ntfs quick
    echo active
    rem echo assign letter=Z

)) > X:\diskpart.txt

rem  diskpart /s  diskpart 
rem  0
diskpart /s X:\diskpart.txt
del X:\diskpart.txt

rem 
rem X boot.wim (ram)
rem Y installer
rem Z os

rem  BuildNumber
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
    set "BuildNumber=%%a"
)

rem C(24h2)
rem 1g /
if %BuildNumber% GEQ 26040 (
    rem  installer  boot.wim 
    rem vista/2008  boot.wim200M-(+)164M
    rem call :createPageFileOnZ
)

rem  id
set "file=X:\windows.xml"
set "tempFile=X:\tmp.xml"

set "search=%%disk_id%%"
set "replace=%DiskIndex%"

(for /f "delims=" %%i in (%file%) do (
    set "line=%%i"

    setlocal EnableDelayedExpansion
    echo !line:%search%=%replace%!
    endlocal

)) > %tempFile%
move /y %tempFile% %file%


rem https://github.com/pbatard/rufus/issues/1990
for %%a in (RAM TPM SecureBoot) do (
    reg add HKLM\SYSTEM\Setup\LabConfig /t REG_DWORD /v Bypass%%aCheck /d 1 /f
)

rem 
set ForceOldSetup=0
set EnableUnattended=1
set EnableEMS=0

rem  ramdisk X:\setup.exe 
rem vista 
rem server 23h2 
rem  /installfrom ?

rem  iso install.wim  setup.exe
rem https://github.com/bin456789/reinstall/issues/578

if "%ForceOldSetup%"=="1" if exist Y:\sources\setup.exe (
    set setup=Y:\sources\setup.exe
    goto :SetupExeFound
)
if exist Y:\setup.exe (
    set setup=Y:\setup.exe
) else if exist Y:\sources\setup.exe (
    set setup=Y:\sources\setup.exe
) else if exist X:\setup.exe (
    set setup=X:\setup.exe
) else (
    echo "Error: setup.exe not found." >&2
    exit /b 1
)
:SetupExeFound

if "%EnableUnattended%"=="1" (
    set Unattended=/unattend:X:\windows.xml
)

rem  Compact OS

rem  BIOS MBR 
rem  MBR
rem server 2025 + bios 
rem  server 2025  bios
rem TODO:  ms-sys 
if %BuildNumber% GEQ 26040 if "%BootType%"=="bios" (
    rem set ForceOldSetup=1
    bootrec /fixmbr
)

rem  winre 
rem  winre 
rem winre  installer 
rem  winre winre  C 
if %BuildNumber% GEQ 26040 if "%ForceOldSetup%"=="0" (
    set ResizeRecoveryPartition=/ResizeRecoveryPartition Disable
)

rem  windows server  EMS/SAC
rem  windows  SAC 
rem  trans.sh  SAC  EnableEMS  EMS
if "%EnableEMS%"=="1" (
    rem set EMS=/EMSPort:UseBIOSSettings /EMSBaudRate:115200
    set EMS=/EMSPort:COM1 /EMSBaudRate:115200
)

echo on
%setup% %ResizeRecoveryPartition% %EMS% %Unattended%
exit /b





:is_number
rem 
rem num  0
rem  0 
set /a "num=%~1" >nul 2>nul
if "%num%"=="%~1" (
    exit /b 0
)
exit /b 1

:is_x_starts_with_char_y
set "tempStr=%~1"
if "%tempStr:~0,1%"=="%~2" (
   exit /b 0
)
exit /b 1

:sleep
rem  ping 
rem  timeout 
rem timeout /t 10 /nobreak
echo wscript.sleep(%~1) > X:\sleep.vbs
cscript //nologo X:\sleep.vbs
del X:\sleep.vbs
exit /b

:createPageFile
rem pagefile  64M
for /l %%i in (1, 1, 100) do (
    wpeutil CreatePageFile /path=Y:\pagefile%%i.sys >nul 2>nul && echo Created pagefile%%i.sys || exit /b
)
exit /b

:createPageFileOnZ
wpeutil CreatePageFile /path=Z:\pagefile.sys /size=512
exit /b

:drvload_if_scsi
rem  Class=SCSIAdapter 
find /i "SCSIAdapter" "%~1" >nul
if not errorlevel 1 (
    rem  N 
    rem 1. dism /online /add-driver /driver:"%~1"     # PE  /online 
    rem 2. pnputil -i -a "%~1"
    rem 3. devcon
    rem 4. dpinst
    rem 5. drvload  https://learn.microsoft.com/windows-hardware/manufacture/desktop/drvload-command-line-options
    drvload "%~1"
)
exit /b
