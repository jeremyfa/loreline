#!/usr/bin/env bash
set -u

# End-to-end web smoke test for the Loreline Godot integration.
#
# Patches the sample project's main_scene to the test_web_runner scene,
# exports a Web build, serves it locally, runs headless Chromium via
# Playwright and asserts the ALL_WEB_TESTS_PASSED marker, then restores
# the original main_scene. Used by CI and by local developers (Mac+Linux).
#
# Requirements:
#   - Godot 4.6.x installed (resolved like run-headless-test.sh: $GODOT_BIN,
#     `godot` on PATH, or /Applications/Godot.app/Contents/MacOS/Godot on Mac).
#   - Matching Godot Web export templates installed (Mac: ~/Library/Application
#     Support/Godot/export_templates/<ver>/; Linux: ~/.local/share/godot/
#     export_templates/<ver>/).
#   - python3 (for the static HTTP server).
#   - node + npm (for Playwright). The script will `npm install` Playwright and
#     `npx playwright install chromium` on first run if missing.

project_dir="$(cd "$(dirname "$0")" && pwd)"

# Resolve Godot binary
if [ -n "${GODOT_BIN:-}" ]; then
    godot="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
    godot="$(command -v godot)"
elif [ "$(uname)" = "Darwin" ] && [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    godot="/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "error: cannot find Godot binary. Set GODOT_BIN or put 'godot' on PATH." >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found (needed for the static HTTP server)." >&2
    exit 2
fi

if ! command -v node >/dev/null 2>&1; then
    echo "error: node not found (needed for the Playwright harness)." >&2
    exit 2
fi

port="${WEB_TEST_PORT:-8765}"
timeout_ms="${WEB_TEST_TIMEOUT:-90000}"

out_dir="$project_dir/.tmp-web"
project_file="$project_dir/project.godot"
backup_file="$project_dir/.tmp-project.godot.bak.$$"

cleanup() {
    if [ -f "$backup_file" ]; then
        mv "$backup_file" "$project_file"
    fi
    if [ -n "${server_pid:-}" ] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "==> godot:   $godot"
echo "==> project: $project_dir"
echo "==> output:  $out_dir"
echo "==> port:    $port"
echo

# 1. Patch project.godot to use the web runner scene as main_scene.
cp "$project_file" "$backup_file"
awk '
    /^run\/main_scene=/ { print "run/main_scene=\"res://scenes/test_web_runner.tscn\""; next }
    { print }
' "$project_file" > "$project_file.tmp"
mv "$project_file.tmp" "$project_file"

# 2. Ensure Playwright is installed in the project dir.
cd "$project_dir"
if [ ! -d node_modules/playwright ]; then
    echo "==> installing playwright (first run)"
    if [ ! -f package.json ]; then
        npm init -y >/dev/null
    fi
    npm install --no-save --silent playwright
    npx --yes playwright install chromium
fi

# Tell Godot to skip node_modules during indexing/export (would otherwise be
# bundled into the .pck because the Web preset uses export_filter=all_resources).
# .gdignore is the Godot-native marker for "do not scan this directory".
touch node_modules/.gdignore

# 3. Import the project (needed before --export-release).
echo "==> importing project"
"$godot" --headless --path "$project_dir" --import || true

# 4. Export the Web build.
mkdir -p "$out_dir"
echo "==> exporting Web build to $out_dir"
"$godot" --headless --path "$project_dir" --export-release Web "$out_dir/index.html"

if [ ! -f "$out_dir/index.html" ]; then
    echo "FAIL: export did not produce $out_dir/index.html" >&2
    exit 1
fi

# 5. Serve and run Playwright.
echo "==> serving $out_dir on http://localhost:$port"
(cd "$out_dir" && python3 -m http.server "$port" >/dev/null 2>&1) &
server_pid=$!

# Wait briefly for the server to come up.
sleep 1

set +e
node "$project_dir/web-test-runner.js" \
    --url "http://localhost:$port/index.html" \
    --markers "ALL_WEB_TESTS_PASSED" \
    --timeout "$timeout_ms"
test_status=$?
set -e

exit "$test_status"
