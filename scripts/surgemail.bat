@echo off
REM 'surgemail' command wrapper -> PowerShell helper
setlocal
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set PS="%ProgramFiles%\PowerShell\7\pwsh.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0\surgemail-helper.ps1" -Command %*
endlocal
