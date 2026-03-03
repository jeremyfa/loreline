cmake_minimum_required(VERSION 3.14)
project(loreline-sdl3-native)

set(CMAKE_CXX_STANDARD 11)

# SDL3 — prebuilt shared library
add_library(SDL3 SHARED IMPORTED)
set_target_properties(SDL3 PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../sdl3/android/jniLibs/${ANDROID_ABI}/libSDL3.so
    IMPORTED_NO_SONAME TRUE
)

# Loreline — prebuilt shared library
add_library(loreline SHARED IMPORTED)
set_target_properties(loreline PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../loreline/android/jni/${ANDROID_ABI}/libloreline.so
    IMPORTED_NO_SONAME TRUE
)

# Main native library (loaded by SDLActivity)
add_library(main SHARED ../../main.cpp)

target_include_directories(main PRIVATE
    ${CMAKE_SOURCE_DIR}/../../sdl3/android/include
    ${CMAKE_SOURCE_DIR}/../../loreline/include
    ${CMAKE_SOURCE_DIR}/../..
)

target_link_libraries(main SDL3 loreline android log)
