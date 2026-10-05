@echo off
rem Joins the two game files into one and unzips them. Keep this file and both InfDNA_v0.6.1.part files in the same folder.
cd /d "%~dp0"
if not exist InfDNA_v0.6.1.part1 goto missing
if not exist InfDNA_v0.6.1.part2 goto missing
echo Joining the game files...
copy /b InfDNA_v0.6.1.part1+InfDNA_v0.6.1.part2 InfDNA_v0.6.1_windows.zip >nul
if errorlevel 1 goto joinfail
echo Unzipping (this takes a few seconds)...
tar -xf InfDNA_v0.6.1_windows.zip
if errorlevel 1 goto unzipfail
del InfDNA_v0.6.1.part1 InfDNA_v0.6.1.part2 InfDNA_v0.6.1_windows.zip
echo.
echo Done. Starting InfDNA. Next time just double-click InfDNA.exe.
echo (If Windows says it protected your PC: click More info, then Run anyway.)
start "" InfDNA.exe
goto end
:missing
echo.
echo I can't find both game files. Put InfDNA_v0.6.1.part1 and InfDNA_v0.6.1.part2 in the same folder as this file, then run it again.
pause
goto end
:joinfail
echo.
echo Joining the files failed. Download both parts again and run this file again.
pause
goto end
:unzipfail
echo.
echo Unzipping failed. Download both parts again and run this file again.
pause
:end
