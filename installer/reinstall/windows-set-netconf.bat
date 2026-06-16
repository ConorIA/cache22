rem set mac_addr=11:22:33:aa:bb:cc

rem set ipv4_addr=192.168.1.2/24
rem set ipv4_gateway=192.168.1.1
rem set ipv4_dns1=192.168.1.1
rem set ipv4_dns2=192.168.1.2

rem set ipv6_addr=2222::2/64
rem set ipv6_gateway=2222::1
rem set ipv6_dns1=::1
rem set ipv6_dns2=::2

@echo off
mode con cp select=437 >nul

rem  IPv6  IPv6 
netsh interface ipv6 set global randomizeidentifiers=disabled

rem  MAC 
if not defined mac_addr goto :del

rem vista  powershell
rem win11 24h2  wmic dd  wmic
if exist "%windir%\system32\wbem\wmic.exe" (
    rem wmic  \r\r\n
    rem  findstr   \r
    for /f "tokens=2 delims==" %%a in (
        'wmic nic where "MACAddress='%mac_addr%'" get InterfaceIndex /format:list ^| findstr "^InterfaceIndex=[0-9][0-9]*$"'
    ) do set id=%%a
)

if not defined id (
    for /f %%a in ('powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
        -Command "(Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.MACAddress -eq '%mac_addr%' }).InterfaceIndex" ^| findstr "^[0-9][0-9]*$"'
    ) do set id=%%a
)

if not defined id (
    for /f %%a in ('powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
        -Command "(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.MACAddress -eq '%mac_addr%' }).InterfaceIndex" ^| findstr "^[0-9][0-9]*$"'
    ) do set id=%%a
)

if defined id (
    rem  IPv4 
    if defined ipv4_addr if defined ipv4_gateway (
        rem  setlocal EnableDelayedExpansion
        rem netsh interface ipv4 set address !id! static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0
        rem !id!  \r 
        rem %id% 

        rem gwmetric  1 0
        netsh interface ipv4 set address %id% static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0
    )

    rem  IPv4 DNS 
    for %%i in (1, 2) do (
        if defined ipv4_dns%%i (
            netsh interface ipv4 add | findstr "dnsservers" >nul
            if ErrorLevel 1 (
                rem vista
                setlocal EnableDelayedExpansion
                netsh interface ipv4 add dnsserver %id% !ipv4_dns%%i! %%i
                endlocal
            ) else (
                rem win7
                setlocal EnableDelayedExpansion
                netsh interface ipv4 add dnsservers %id% !ipv4_dns%%i! %%i no
                endlocal
            )
        )
    )

    rem  IPv6 
    if defined ipv6_addr if defined ipv6_gateway (
        netsh interface ipv6 set address %id% %ipv6_addr%
        netsh interface ipv6 add route prefix=::/0 %id% %ipv6_gateway%
    )

    rem  IPv6 DNS 
    for %%i in (1, 2) do (
        if defined ipv6_dns%%i (
            netsh interface ipv6 add | findstr "dnsservers" >nul
            if ErrorLevel 1 (
                rem vista
                setlocal EnableDelayedExpansion
                netsh interface ipv6 add dnsserver %id% !ipv6_dns%%i! %%i
                endlocal
            ) else (
                rem win7
                setlocal EnableDelayedExpansion
                netsh interface ipv6 add dnsservers %id% !ipv6_dns%%i! %%i no
                endlocal
            )
        )
    )
)

:del
rem 
del "%~f0"
