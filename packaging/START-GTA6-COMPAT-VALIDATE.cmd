@echo off
setlocal DisableDelayedExpansion
set "GTA6_TEST_GAME_PATH=%~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-NoCache.ps1" -ValidateCompatShaders
set "TEST_EXIT=%ERRORLEVEL%"
pause
exit /b %TEST_EXIT%
