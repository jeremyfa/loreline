#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p build/mac
cd build/mac
cmake ../..
cmake --build .
cp ../../sdl3/mac/lib/libSDL3*.dylib . 2>/dev/null || true
cp ../../loreline/mac/libLoreline.dylib .
echo "Built: build/mac/loreline-sdl3"
