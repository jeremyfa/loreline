@echo off
cd /d "%~dp0"
mkdir build\windows 2>nul
cd build\windows
cmake ..\.. -DLORELINE_INCLUDE_DIR=loreline\include -DLORELINE_LIB_DIR=loreline\windows
cmake --build . --config Release
copy ..\..\loreline\windows\Loreline.dll Release\ >nul 2>&1
echo Built: build\windows\Release\loreline-sample.exe
