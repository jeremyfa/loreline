#!/bin/bash
set -e
cd "$(dirname "$0")"
./build-linux.sh
exec ./build/linux/loreline-sdl3
