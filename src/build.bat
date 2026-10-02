@echo off
REM Zips the mod and drops it into Brotato's mods folder.
REM Edit GAME_DIR once to point at your Brotato install (the folder with Brotato.exe).
set GAME_DIR=C:\GOG Games\Brotato
set MOD_ID=Judah-InfDNA

if not exist "%GAME_DIR%\mods" mkdir "%GAME_DIR%\mods"
del /q "%GAME_DIR%\mods\%MOD_ID%.zip" 2>nul
tar -a -cf "%GAME_DIR%\mods\%MOD_ID%.zip" mods-unpacked
if errorlevel 1 (echo Build failed & exit /b 1)
echo Built %MOD_ID%.zip into "%GAME_DIR%\mods"
