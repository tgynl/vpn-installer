@echo off
REM Double-click launcher for install-ucsd-vpn-employee.ps1
REM This just runs the PowerShell script with a policy that allows it to execute,
REM without changing the user's permanent PowerShell execution policy.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-ucsd-vpn-employee.ps1"
pause
