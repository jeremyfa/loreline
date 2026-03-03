cmake_minimum_required(VERSION 3.14)
project(loreline-sdl3 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- SDL3 ---
# Expects sdl3/{platform}/ with include/ and lib/ (or bin/ on Windows).
# Downloaded by: node ./setup --sample sdl3
if(NOT DEFINED SDL3_DIR)
    if(APPLE)
        set(SDL3_DIR ${CMAKE_SOURCE_DIR}/sdl3/mac)
    elseif(WIN32)
        set(SDL3_DIR ${CMAKE_SOURCE_DIR}/sdl3/windows)
    else()
        execute_process(COMMAND uname -m OUTPUT_VARIABLE ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(ARCH STREQUAL "aarch64" OR ARCH STREQUAL "arm64")
            set(SDL3_DIR ${CMAKE_SOURCE_DIR}/sdl3/linux-arm64)
        else()
            set(SDL3_DIR ${CMAKE_SOURCE_DIR}/sdl3/linux-x64)
        endif()
    endif()
endif()

# --- Loreline ---
# Expects loreline/ with include/Loreline.h and platform lib.
# Copied by: node ./setup --sample sdl3
if(NOT DEFINED LORELINE_DIR)
    set(LORELINE_DIR ${CMAKE_SOURCE_DIR}/loreline)
endif()
if(NOT DEFINED LORELINE_INCLUDE_DIR)
    set(LORELINE_INCLUDE_DIR ${LORELINE_DIR}/include)
endif()
if(NOT DEFINED LORELINE_LIB_DIR)
    if(APPLE)
        set(LORELINE_LIB_DIR ${LORELINE_DIR}/mac)
    elseif(WIN32)
        set(LORELINE_LIB_DIR ${LORELINE_DIR}/windows)
    else()
        execute_process(COMMAND uname -m OUTPUT_VARIABLE ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(ARCH STREQUAL "aarch64")
            set(LORELINE_LIB_DIR ${LORELINE_DIR}/linux-aarch64)
        else()
            set(LORELINE_LIB_DIR ${LORELINE_DIR}/linux-x86_64)
        endif()
    endif()
endif()

add_executable(loreline-sdl3 main.cpp)

target_include_directories(loreline-sdl3 PRIVATE
    ${SDL3_DIR}/include
    ${LORELINE_INCLUDE_DIR}
    ${CMAKE_SOURCE_DIR}
)

# SDL3 linking
target_link_directories(loreline-sdl3 PRIVATE ${SDL3_DIR}/lib)
target_link_libraries(loreline-sdl3 PRIVATE SDL3)

# Loreline linking
target_link_directories(loreline-sdl3 PRIVATE ${LORELINE_LIB_DIR})
target_link_libraries(loreline-sdl3 PRIVATE Loreline)

# Platform-specific settings
if(APPLE)
    set_target_properties(loreline-sdl3 PROPERTIES
        BUILD_RPATH "@executable_path"
        INSTALL_RPATH "@executable_path")
elseif(UNIX)
    set_target_properties(loreline-sdl3 PROPERTIES
        BUILD_RPATH "$ORIGIN"
        INSTALL_RPATH "$ORIGIN")
elseif(WIN32)
    # Copy DLLs next to executable after build
    add_custom_command(TARGET loreline-sdl3 POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${SDL3_DIR}/bin/SDL3.dll" $<TARGET_FILE_DIR:loreline-sdl3>
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${LORELINE_LIB_DIR}/Loreline.dll" $<TARGET_FILE_DIR:loreline-sdl3>)
endif()

# Copy resource directories next to the binary
file(COPY story fonts DESTINATION ${CMAKE_BINARY_DIR})
