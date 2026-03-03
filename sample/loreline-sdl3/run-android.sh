#!/bin/bash
set -e
cd "${0%/*}"

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

./build-android.sh

APK_PATH="android/app/build/outputs/apk/debug/app-debug.apk"
PACKAGE_NAME="app.loreline.sdl3sample"

# Check if a device is connected
adb devices | grep "device$" > /dev/null
if [ $? -ne 0 ]; then
    echo "No device connected. Please connect your Android device and enable USB debugging."
    exit 1
fi

# Install the APK
adb install -r "$APK_PATH"
if [ $? -ne 0 ]; then
    echo "Failed to install APK."
    exit 1
fi

# Launch the app
adb shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
if [ $? -eq 0 ]; then
    echo "App started successfully."
else
    echo "Failed to start the app."
fi

# Stream logcat
adb logcat
