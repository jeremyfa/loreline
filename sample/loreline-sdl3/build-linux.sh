#!/bin/bash
set -e
cd "$(dirname "$0")"
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    SDL3_PLATFORM="linux-arm64"
    LORELINE_PLATFORM="linux-aarch64"
else
    SDL3_PLATFORM="linux-x64"
    LORELINE_PLATFORM="linux-x86_64"
fi
mkdir -p build/linux
cd build/linux
cmake ../..
cmake --build .
cp ../../sdl3/${SDL3_PLATFORM}/lib/libSDL3.so* . 2>/dev/null || true
cp ../../loreline/${LORELINE_PLATFORM}/libLoreline.so .
echo "Built: build/linux/loreline-sdl3"
