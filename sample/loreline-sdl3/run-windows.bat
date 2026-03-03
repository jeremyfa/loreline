@echo off
cd /d "%~dp0"
call build-windows.bat
if errorlevel 1 exit /b %errorlevel%
build\windows\Release\loreline-sdl3.exe
