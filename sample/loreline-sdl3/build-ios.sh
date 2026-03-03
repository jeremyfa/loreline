#!/bin/bash
set -e
cd "$(dirname "$0")"

BUILD_DIR="build/ios"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project ios/loreline-sdl3.xcodeproj \
    -scheme loreline-sdl3 \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "loreline-sdl3.app" -type d | head -1)
echo "Built: $APP_PATH"
