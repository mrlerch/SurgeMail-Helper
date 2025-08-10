@echo off
REM SurgeMail Helper (Batch shim) - run PowerShell helper as 'surgemail'
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0surgemail-helper.ps1" -Command %*
