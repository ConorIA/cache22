@echo off
mode con cp select=437 >nul

rem set RdpPort=3333

rem https://learn.microsoft.com/windows-server/remote/remote-desktop-services/clients/change-listening-port
rem HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules

rem RemoteDesktop-Shadow-In-TCP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=6|App=%SystemRoot%\system32\RdpSa.exe|Name=@FirewallAPI.dll,-28778|Desc=@FirewallAPI.dll,-28779|EmbedCtxt=@FirewallAPI.dll,-28752|Edge=TRUE|Defer=App|

rem RemoteDesktop-UserMode-In-TCP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28775|Desc=@FirewallAPI.dll,-28756|EmbedCtxt=@FirewallAPI.dll,-28752|

rem RemoteDesktop-UserMode-In-UDP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=17|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28776|Desc=@FirewallAPI.dll,-28777|EmbedCtxt=@FirewallAPI.dll,-28752|

rem 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d %RdpPort% /f

rem 
rem  rdp 
rem : program=%SystemRoot%\system32\svchost.exe service=TermService
rem win7 :    program=System                            service=
rem 
for %%a in (TCP, UDP) do (
    netsh advfirewall firewall add rule ^
        name="Remote Desktop - Custom Port (%%a-In)" ^
        dir=in ^
        action=allow ^
        service=any ^
        protocol=%%a ^
        localport=%RdpPort%
)

rem  rdp 
sc query TermService
if %errorlevel% == 1060 goto :del

rem   sc  net
rem UmRdpService  TermService
rem sc stop  sc stop TermService  sc stop UmRdpService
rem net stop 
rem sc stop net stop  timeout 
rem TermService UmRdpService 

rem  rdp  goto 
rem The Remote Desktop Services service could not be stopped.

rem  logo 
rem  netstat netstat -ano rdp (pid)
rem 

set retryCount=5

:restartRDP
if %retryCount% LEQ 0 goto :del
net stop TermService /y && net start TermService || (
    set /a retryCount-=1
    timeout 10
    goto :restartRDP
)

:del
del "%~f0"
