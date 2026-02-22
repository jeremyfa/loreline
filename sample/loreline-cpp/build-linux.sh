#!/bin/bash
set -e
cd "$(dirname "$0")"
ARCH=$(uname -m)
mkdir -p build/linux
cd build/linux
cmake ../.. -DLORELINE_INCLUDE_DIR=loreline/include -DLORELINE_LIB_DIR=loreline/linux-${ARCH}
cmake --build .
cp ../../loreline/linux-${ARCH}/libLoreline.so .
echo "Built: build/linux/loreline-sample"
