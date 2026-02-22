cmake_minimum_required(VERSION 3.14)
project(loreline-sample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set LORELINE_DIR to the directory containing the Loreline library.
# Expected layout:
#   LORELINE_DIR/
#     include/Loreline.h
#     libLoreline.dylib (macOS) / libLoreline.so (Linux) / Loreline.dll (Windows)
#
# Or override individually with LORELINE_INCLUDE_DIR and LORELINE_LIB_DIR.
if(NOT DEFINED LORELINE_DIR AND (NOT DEFINED LORELINE_INCLUDE_DIR OR NOT DEFINED LORELINE_LIB_DIR))
    message(FATAL_ERROR
        "Set -DLORELINE_DIR=/path/to/loreline-lib, or both -DLORELINE_INCLUDE_DIR and -DLORELINE_LIB_DIR")
endif()

if(NOT DEFINED LORELINE_INCLUDE_DIR)
    set(LORELINE_INCLUDE_DIR ${LORELINE_DIR}/include)
endif()
if(NOT DEFINED LORELINE_LIB_DIR)
    set(LORELINE_LIB_DIR ${LORELINE_DIR})
endif()

add_executable(loreline-sample main.cpp)
target_include_directories(loreline-sample PRIVATE ${LORELINE_INCLUDE_DIR})
target_link_directories(loreline-sample PRIVATE ${LORELINE_LIB_DIR})
target_link_libraries(loreline-sample PRIVATE Loreline)

# Copy story files next to the binary
file(COPY story DESTINATION ${CMAKE_BINARY_DIR})

# Set rpath so the dynamic library is found next to the executable
if(APPLE)
    set_target_properties(loreline-sample PROPERTIES
        BUILD_RPATH "@executable_path"
        INSTALL_RPATH "@executable_path")
elseif(UNIX)
    set_target_properties(loreline-sample PROPERTIES
        BUILD_RPATH "$ORIGIN"
        INSTALL_RPATH "$ORIGIN")
elseif(WIN32)
    # Copy DLL next to executable after build
    add_custom_command(TARGET loreline-sample POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${LORELINE_LIB_DIR}/Loreline.dll"
            $<TARGET_FILE_DIR:loreline-sample>)
endif()
