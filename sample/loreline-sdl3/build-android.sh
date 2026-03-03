#!/bin/bash
set -e
cd "$(dirname "$0")"

# Ensure ANDROID_HOME is set and platform-tools/adb is on PATH
if [ -z "$ANDROID_HOME" ]; then
    if [ -d "$HOME/Library/Android/sdk" ]; then
        export ANDROID_HOME="$HOME/Library/Android/sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_HOME="$HOME/Android/Sdk"
    fi
fi
if [ -n "$ANDROID_HOME" ]; then
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/ndk-bundle:$PATH"
fi

# Copy assets into the Android project (symlinks are not followed by AAPT)
ASSETS_DIR="android/app/src/main/assets"
mkdir -p "$ASSETS_DIR"
rm -rf "$ASSETS_DIR/fonts" "$ASSETS_DIR/story"
cp -R fonts "$ASSETS_DIR/fonts"
cp -R story "$ASSETS_DIR/story"

cd android
./gradlew assembleDebug

APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
echo "Built: android/$APK_PATH"
