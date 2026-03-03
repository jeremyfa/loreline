#!/bin/bash
set -e
cd "$(dirname "$0")"
./build-mac.sh
exec ./build/mac/loreline-sdl3
