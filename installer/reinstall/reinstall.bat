@echo off
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
set confhome_cn=https://cnb.cool/bin456789/reinstall/-/git/raw/main
rem set confhome_cn=https://www.ghproxy.cc/https://raw.githubusercontent.com/bin456789/reinstall/main

set pkgs=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,bind-utils,libiconv,binutils
set cmds=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,nslookup,iconv,ar

rem 65001 

rem  :: 
rem  

rem Windows 7 SP1 winhttp  tls 1.2
rem https://support.microsoft.com/en-us/topic/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-winhttp-in-windows-c4bd73d2-31d7-761e-0178-11268bb10392
rem 
rem https
rem 
cd /d %~dp0

rem 
fltmc >nul 2>&1
if errorlevel 1 (
    echo Please run as administrator^^!
    exit /b
)

rem  %tmp%  id
rem https://learn.microsoft.com/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted
rem if not exist %tmp% (
rem     md %tmp%
rem )

rem  geoip
if not exist geoip (
    rem www.cloudflare.com/dash.cloudflare.com 
    call :download http://www.qualcomm.cn/cdn-cgi/trace %~dp0geoip || goto :download_failed
)

rem  loc=
findstr /c:"loc=" geoip >nul
if errorlevel 1 (
    echo Invalid geoip file
    del geoip
    exit /b 1
)

rem 
findstr /c:"loc=CN" geoip >nul
if not errorlevel 1 (
    rem mirrors.tuna.tsinghua.edu.cn  https
    set mirror=http://mirror.nju.edu.cn
    if defined confhome_cn (
        set confhome=!confhome_cn!
    ) else if defined github_proxy (
        echo !confhome! | findstr /c:"://raw.githubusercontent.com/" >nul
        if not errorlevel 1 (
            set confhome=!confhome:http://=https://!
            set confhome=!confhome:https://raw.githubusercontent.com=%github_proxy%!
        )
    )
) else (
    rem  equinix  cdn
    set mirror=http://mirrors.kernel.org
)

call :check_cygwin_installed || (
    rem win10 arm  x86 
    rem win11 arm  x86  x86_64 

    rem windows 11 24h2  wmic
    rem wmic os get osarchitecture  mode con cp select=437
    rem wmic ComputerSystem get SystemType 
    rem for /f "tokens=*" %%a in ('wmic ComputerSystem get SystemType ^| find /i "based"') do (
    rem     set "SystemType=%%a"
    rem )

    rem  powershell
    rem for /f "delims=" %%a in ('powershell -NoLogo -NoProfile -NonInteractive -Command "(Get-WmiObject win32_computersystem).SystemType"') do (
    rem     set "SystemType=%%a"
    rem )

    rem SystemArch
    for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PROCESSOR_ARCHITECTURE') do (
        set SystemArch=%%a
    )

    rem  PROCESSOR_ARCHITEW6432  PROCESSOR_ARCHITECTURE 
    rem ARM64 win11  PROCESSOR_ARCHITEW6432   PROCESSOR_ARCHITECTURE
    rem cmd                                ARM64
    rem 32cmd          ARM64                       x86

    rem if defined PROCESSOR_ARCHITEW6432 (
    rem     set "SystemArch=%PROCESSOR_ARCHITEW6432%"
    rem ) else (
    rem     set "SystemArch=%PROCESSOR_ARCHITECTURE%"
    rem )

    rem BuildNumber
    for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
        set /a BuildNumber=%%a
    )

    set CygwinEOL=1

    echo !SystemArch! | find "ARM" > nul
    if not errorlevel 1 (
        if !BuildNumber! GEQ 22000 (
            set CygwinEOL=0
        )
    ) else (
        echo !SystemArch! | find "AMD64" > nul
        if not errorlevel 1 (
            if !BuildNumber! GEQ 9600 (
                set CygwinEOL=0
            )
        )
    )

    rem win7/8 cygwin  EOL cygwin  Cygwin Time Machine 
    rem  Cygwin Time Machine 
    rem , cygwin EOL  cygwin-archive x86 
    if !CygwinEOL! == 1 (
        set CygwinArch=x86
        set dir=/sourceware/cygwin-archive/20221123
    ) else (
        set CygwinArch=x86_64
        set dir=/sourceware/cygwin
    )

    rem daocloud  90  IPv6
    rem https://github.com/DaoCloud/public-binary-files-mirror
    rem 
    rem https://files.m.daocloud.io/www.cloudflare.com/cdn-cgi/trace?a=1
    rem https://files.m.daocloud.io/www.cloudflare.com/cdn-cgi/trace?b=2
    rem  https://www.cygwin.com/setup-x86_64.exe?xxx=20250101 

    rem  Cygwin
    if not exist setup-!CygwinArch!.exe (
        call :download http://www.cygwin.com/setup-!CygwinArch!.exe %~dp0setup-!CygwinArch!.exe || goto :download_failed
    )

    rem  1M 
    rem  IP  exe html
    for %%A in (setup-!CygwinArch!.exe) do if %%~zA LSS 1048576 (
        echo Invalid Cgywin installer
        del setup-!CygwinArch!.exe
        exit /b 1
    )

    rem  Cygwin
    set site=!mirror!!dir!
    start /wait setup-!CygwinArch!.exe ^
        --allow-unsupported-windows ^
        --quiet-mode ^
        --only-site ^
        --site !site! ^
        --root %SystemDrive%\cygwin ^
        --local-package-dir %~dp0cygwin-local-package-dir ^
        --packages %pkgs%

    rem  Cygwin 
    if errorlevel 1 goto :install_cygwin_failed
    call :check_cygwin_installed || goto :install_cygwin_failed
)

rem c cygpath -ua .  /cygdrive/c /
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua ./') do set thisdir=%%a

rem  reinstall.sh
if not exist reinstall.sh (
    call :download_with_curl %confhome%/reinstall.sh %thisdir%reinstall.sh || goto :download_failed
    call :chmod a+x %thisdir%reinstall.sh
)

rem %*  --iso https://x.com/?yyy=123
rem  bash
rem for %%a in (%*) do (
rem     set "param=!param! "%%~a""
rem )

rem  unix  windows 
%SystemDrive%\cygwin\bin\dos2unix -q '%thisdir%reinstall.sh'

rem  bash 
rem %SystemDrive%\cygwin\bin\bash -l %thisdir%reinstall.sh %* 
rem  -l
rem  reinstall.sh  source /etc/profile
rem  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
%SystemDrive%\cygwin\bin\bash %thisdir%reinstall.sh %*
exit /b

rem bits  Content-Length 
rem cloudflare  cdn-cgi/trace  Content-Length
rem “” bits 
rem https://learn.microsoft.com/en-us/windows/win32/bits/http-requirements-for-bits-downloads
rem bitsadmin /transfer "%~3" /priority foreground %~1 %~2

:download
rem certutil  windows Defender 
rem windows server 2019  certutil 
echo Downloading: %~1 %~2
del /q "%~2" 2>nul
if exist "%~2" (echo Cannot delete %~2 & exit /b 1)

certutil -urlcache -f -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

certutil -urlcache -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

rem 
del /q "%~2" 2>nul
exit /b 1

:download_with_curl
rem  --insecure 
rem curl: (77) error setting certificate verify locations:
rem   CAfile: /etc/ssl/certs/ca-certificates.crt
rem   CApath: none
echo Download: %~1 %~2
%SystemDrive%\cygwin\bin\curl -L --insecure "%~1" -o "%~2"
exit /b

:chmod
%SystemDrive%\cygwin\bin\chmod "%~1" "%~2"
exit /b

:download_failed
echo Download failed.
exit /b 1

:install_cygwin_failed
echo Failed to install Cygwin.
exit /b 1

:check_cygwin_installed
set "cmds_space=%cmds:,= %"
for %%c in (%cmds_space%) do (
    if not exist "%SystemDrive%\cygwin\bin\%%c" if not exist "%SystemDrive%\cygwin\bin\%%c.exe" (
        exit /b 1
    )
)
exit /b 0
