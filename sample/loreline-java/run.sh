#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p build
javac -cp loreline.jar -d build LorelineStory.java
java -cp "loreline.jar:build" LorelineStory
