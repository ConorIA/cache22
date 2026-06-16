@echo off
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

rem https://learn.microsoft.com/troubleshoot/windows-server/networking/netsh-advfirewall-firewall-control-firewall-behavior#command-example-4-configure-icmp-settings
rem  netsh firewall set icmpsetting 8 ( - ICMPv4-In)

set ICMPv4EchoTypeNum=8
set ICMPv6EchoTypeNum=128

for %%i in (4, 6) do (
    netsh advfirewall firewall add rule ^
        name="ICMP Echo Request (ICMPv%%i-In)" ^
        dir=in ^
        action=allow ^
        program=System ^
        protocol=ICMPv%%i:!ICMPv%%iEchoTypeNum!,any
)

rem 
del "%~f0"
