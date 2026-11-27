@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
set "PROFILE=%~1"
if not exist "%~dp0patched\kyty_emulator.exe" goto missing_runtime
set "GAME_PATH=%~2"
if defined GAME_PATH goto check_game
if exist "%~dp0game-path.txt" set /p "GAME_PATH=" <"%~dp0game-path.txt"
if defined GAME_PATH if exist "%GAME_PATH%" goto check_game
echo Enter the existing GTA6 game folder, ELF file, or ZArchive file.
echo You can also drag your game folder onto START-GTA6.cmd next time.
set "GAME_PATH="
set /p "GAME_PATH=GTA6 path: "
:check_game
set "GAME_PATH=%GAME_PATH:"=%"
if not exist "%GAME_PATH%" goto missing_game
>"%~dp0game-path.txt" <nul set /p "=%GAME_PATH%"
"%~dp0patched\kyty_emulator.exe" --help 2>&1 | findstr /C:"GTA6 Gameplay Test 01" >nul
if errorlevel 1 goto wrong_runtime
if not exist "%~dp0logs" mkdir "%~dp0logs"
set "LOGFILE=%~dp0logs\patched-%PROFILE%-%RANDOM%-%RANDOM%.txt"
set "COMPAT_ARGS="
if /i "%PROFILE%"=="compat" set "COMPAT_ARGS=--redzone --guest-tsc --readback-linear-images --readback-tiled-images --readback-storage-images --sync-raw-image-buffers --flush-draws 1 --tessellation --occlusion-queries"
>"%LOGFILE%" echo GTA6 Gameplay Test 01 - compiled runtime - %PROFILE%
>>"%LOGFILE%" echo Compatibility options: %COMPAT_ARGS%
if exist "%~dp0BUILD-RESULT.txt" type "%~dp0BUILD-RESULT.txt" >>"%LOGFILE%"
certutil -hashfile "%~dp0patched\kyty_emulator.exe" SHA256 >>"%LOGFILE%" 2>&1
echo Starting the patched GTA6 test. Compatibility mode can be very slow.
echo The game stays in its existing location; generated test saves and caches go
echo into this package's patched folder. Close the game window to end a hung run.
echo Log: "%LOGFILE%"
pushd "%~dp0patched"
"%~dp0patched\kyty_emulator.exe" --game "%GAME_PATH%" --shader-cache --printf-direction Console %COMPAT_ARGS% >>"%LOGFILE%" 2>&1
set "TEST_EXIT=%ERRORLEVEL%"
popd
>>"%LOGFILE%" echo Test process exit code: %TEST_EXIT%
echo Test ended with process exit code %TEST_EXIT%.
echo Send the log and say whether the character/camera responded to input.
start "" notepad.exe "%LOGFILE%"
pause
exit /b %TEST_EXIT%
:missing_runtime
echo ERROR: The compiled runtime is missing. Extract the whole Windows test ZIP.
goto failed
:missing_game
echo ERROR: That game path does not exist.
goto failed
:wrong_runtime
echo ERROR: The bundled executable did not show the GTA6 Test 01 banner.
echo Keep the package intact and send the error before replacing any files.
:failed
pause
exit /b 1
