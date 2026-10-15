@echo off
setlocal
cd /d "%~dp0"
echo RemoteOps - Offline recipe acceptance test
echo No VM required. Only the local SIM target model is used.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tests\Invoke-OfflineValidation.ps1"
set "TEST_RESULT=%ERRORLEVEL%"
echo.
echo Test exit code: %TEST_RESULT%
pause
exit /b %TEST_RESULT%
