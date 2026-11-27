@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
echo GTA6 Gameplay Test 01 - setup
echo.
echo Enter the folder containing your existing kyty_emulator.exe.
echo The original installation and game files will stay in place.
set "KYTY_DIR="
set /p "KYTY_DIR=Kyty folder: "
set "KYTY_DIR=%KYTY_DIR:"=%"
if not exist "%KYTY_DIR%\kyty_emulator.exe" goto missing_exe
echo.
echo Enter your existing game folder, ELF file, or ZArchive file.
set "GAME_PATH="
set /p "GAME_PATH=GTA6 path: "
set "GAME_PATH=%GAME_PATH:"=%"
if not exist "%GAME_PATH%" goto missing_game
if /i "%KYTY_DIR%"=="%~dp0runtime-original" goto bad_source
if /i "%KYTY_DIR%"=="%~dp0runtime-patched" goto bad_source
if not exist "%~dp0logs" mkdir "%~dp0logs"
robocopy "%KYTY_DIR%" "%~dp0runtime-original" kyty_emulator.exe *.dll /R:1 /W:1 /NP /NFL /NDL >nul
if errorlevel 8 goto copy_failed
if exist "%KYTY_DIR%\assets" robocopy "%KYTY_DIR%\assets" "%~dp0runtime-original\assets" /E /R:1 /W:1 /NP /NFL /NDL >nul
if errorlevel 8 goto copy_failed
if not exist "%~dp0patched\kyty_emulator.exe" goto save_paths
robocopy "%KYTY_DIR%" "%~dp0runtime-patched" kyty_emulator.exe *.dll /R:1 /W:1 /NP /NFL /NDL >nul
if errorlevel 8 goto copy_failed
if exist "%KYTY_DIR%\assets" robocopy "%KYTY_DIR%\assets" "%~dp0runtime-patched\assets" /E /R:1 /W:1 /NP /NFL /NDL >nul
if errorlevel 8 goto copy_failed
robocopy "%~dp0patched" "%~dp0runtime-patched" /E /R:1 /W:1 /NP /NFL /NDL >nul
if errorlevel 8 goto copy_failed
:save_paths
>"%~dp0emulator-dir.txt" <nul set /p "=%KYTY_DIR%"
>"%~dp0game-path.txt" <nul set /p "=%GAME_PATH%"
echo.
echo Setup finished. Run 01-Current-Compatibility.cmd first.
if exist "%~dp0runtime-patched\kyty_emulator.exe" echo Patched tests are also available: 02 and 03.
if not exist "%~dp0runtime-patched\kyty_emulator.exe" echo This package has no compiled patch yet. Tests 02 and 03 will wait for it.
echo Each runtime keeps its own generated saves and caches in this test folder.
pause
exit /b 0
:missing_exe
echo ERROR: kyty_emulator.exe was not found in that folder.
goto failed
:missing_game
echo ERROR: The game path does not exist.
goto failed
:bad_source
echo ERROR: Select your original Kyty installation as the source.
goto failed
:copy_failed
echo ERROR: Copying the test runtime failed. Check free disk space and close Kyty.
:failed
pause
exit /b 1
