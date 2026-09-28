@echo off
rem Open this folder in a PowerShell session that can run local scripts.
rem The execution policy applies only until this window is closed.
pushd "%~dp0"
if errorlevel 1 (
    echo Could not open the script folder.
    pause
    exit /b 1
)
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass
set "result=%errorlevel%"
popd
exit /b %result%
