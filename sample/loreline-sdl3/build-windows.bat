@echo off
cd /d "%~dp0"
mkdir build\windows 2>nul
cd build\windows
cmake ..\..
cmake --build . --config Release
echo Built: build\windows\Release\loreline-sdl3.exe
