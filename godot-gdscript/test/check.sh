#!/usr/bin/env bash
# Rebuild the GDScript runtime and run the load-all parse check headlessly.
# Prints categorized parse errors. Usage: bash godot-gdscript/test/check.sh
set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
proj="$root/godot-gdscript/test"
godot="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log="$root/.tmp/loadall.log"

cd "$root"
rm -rf godot-gdscript/addons/loreline_gd/core "$proj/core" "$proj/.godot"
./haxe build-gdscript.hxml || exit 1
cp -r godot-gdscript/addons/loreline_gd/core "$proj/core"
perl -e 'alarm 240; exec @ARGV' "$godot" --headless --path "$proj" --import > /dev/null 2>&1
perl -e 'alarm 120; exec @ARGV' "$godot" --headless --path "$proj" --script res://load_all.gd > "$log" 2>&1

grep -E 'LOAD_ALL' "$log"
echo "--- error classes ---"
grep -E 'Parse Error' "$log" | sed 's/.*Parse Error: //' | sed 's/"[^"]*"/"X"/g' | sort | uniq -c | sort -rn | head -25
echo "--- full log: $log ---"
