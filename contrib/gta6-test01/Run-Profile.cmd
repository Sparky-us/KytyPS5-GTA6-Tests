@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
if not exist "%~dp0game-path.txt" goto need_setup
set "GAME_PATH="
set /p "GAME_PATH=" <"%~dp0game-path.txt"
if not exist "%GAME_PATH%" goto need_setup
set "PROFILE=%~1"
set "RUNTIME=runtime-original"
if /i "%~2"=="patched" set "RUNTIME=runtime-patched"
if not exist "%~dp0%RUNTIME%\kyty_emulator.exe" goto need_runtime
set "COMPAT_ARGS="
if /i "%PROFILE%"=="compat" set "COMPAT_ARGS=--redzone --guest-tsc --readback-linear-images --readback-tiled-images --readback-storage-images --sync-raw-image-buffers --flush-draws 1 --tessellation --occlusion-queries"
if not exist "%~dp0logs" mkdir "%~dp0logs"
set "LOGFILE=%~dp0logs\%RUNTIME%-%PROFILE%-%RANDOM%-%RANDOM%.txt"
>"%LOGFILE%" echo GTA6 Gameplay Test 01: runtime=%RUNTIME% profile=%PROFILE%
>>"%LOGFILE%" echo Compatibility options: %COMPAT_ARGS%
certutil -hashfile "%~dp0%RUNTIME%\kyty_emulator.exe" SHA256 >>"%LOGFILE%" 2>&1
echo Starting GTA6 using %RUNTIME% / %PROFILE%.
echo A fresh log is being captured at:
echo %LOGFILE%
echo.
echo Compatibility mode can be very slow. Close the game window to end a hung run.
echo.
pushd "%~dp0%RUNTIME%"
"%~dp0%RUNTIME%\kyty_emulator.exe" --game "%GAME_PATH%" --shader-cache --printf-direction Console %COMPAT_ARGS% >>"%LOGFILE%" 2>&1
set "TEST_EXIT=%ERRORLEVEL%"
popd
>>"%LOGFILE%" echo Test process exit code: %TEST_EXIT%
echo Test finished with process exit code %TEST_EXIT%.
echo Send the log and describe the furthest screen you reached.
start "" notepad.exe "%LOGFILE%"
pause
exit /b %TEST_EXIT%
:need_setup
echo Run Setup.cmd first and check the game path.
pause
exit /b 1
:need_runtime
echo That runtime is not installed yet. This script will not silently use another build.
echo If you have received the patched executable, extract it into patched and rerun Setup.cmd.
pause
exit /b 1
