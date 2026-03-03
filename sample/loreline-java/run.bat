@echo off
cd /d "%~dp0"
if not exist build mkdir build
javac -cp loreline.jar -d build LorelineStory.java
java -cp "loreline.jar;build" LorelineStory
