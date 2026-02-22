#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p build/mac
cd build/mac
cmake ../.. -DLORELINE_INCLUDE_DIR=loreline/include -DLORELINE_LIB_DIR=loreline/mac
cmake --build .
cp ../../loreline/mac/libLoreline.dylib .
echo "Built: build/mac/loreline-sample"
