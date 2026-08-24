#!/usr/bin/env bash
set -u

# Runs the backend-agnostic lifetime tests against both Loreline Godot
# backends, one after the other, in the same project. The addon directory is
# swapped between runs because the two backends register the same class names
# and cannot coexist.
#
# Usage: run.sh [gdscript|native|web|all]   (default: all)
#
# The `web` backend is the GDExtension's web build: a wasm wrapper around the
# JavaScript Loreline, driven through Godot's JavaScriptBridge. It has its own
# callback path, so it gets the same lifetime tests as the other two. It cannot
# run headless: the project is exported, served, and driven in headless
# Chromium via Playwright, asserting the same marker.
#
# Requirements:
#   - Godot 4 ($GODOT_BIN, `godot` on PATH, or the Mac app bundle).
#   - For the gdscript backend: node ./setup --gdscript
#   - For the native backend:    node ./setup --cpp-lib && node ./setup --godot
#   - For the web backend:       node ./setup --js && node ./setup --godot-wasm,
#     Godot web export templates, python3 and node (Playwright is installed on
#     demand into this directory)
#
# CI can skip those builds by pointing at already-assembled addon directories:
#   LORELINE_GDSCRIPT_ADDON=/path/to/addons/loreline
#   LORELINE_NATIVE_ADDON=/path/to/addons/loreline
#   LORELINE_WEB_ADDON=/path/to/addons/loreline   (defaults to the native one)
# Each is used as-is, so the same test runs against exactly what ships. A path
# that is set but missing is a hard failure, never a skip.
#
# Set LORELINE_LIFETIME_REQUIRE_ALL=1 (CI does) to also fail when a backend is
# skipped for want of binaries, so a misconfigured job cannot pass by testing
# nothing.

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
which_backend="${1:-all}"

if [ -n "${GODOT_BIN:-}" ]; then
    godot="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
    godot="$(command -v godot)"
elif [ "$(uname)" = "Darwin" ] && [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    godot="/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "error: cannot find Godot. Set GODOT_BIN or put 'godot' on PATH." >&2
    exit 2
fi

addon="$here/addons/loreline"

# macOS refuses to dlopen a library whose signature no longer matches its path,
# and copying one into place invalidates it. Re-sign ad-hoc whatever landed in
# the addon, whether it came from a local build or from a CI artifact.
resign_if_macos() {
    [ "$(uname -s)" = "Darwin" ] || return 0
    xattr -cr "$addon" 2>/dev/null
    find "$addon" -name "*.dylib" -exec codesign --force --sign - {} \; >/dev/null 2>&1
    return 0
}

# Assembles addons/loreline for the requested backend. Prints a reason on stdout
# and returns 1 when the backend simply is not built (skippable) or 2 when the
# caller asked for something that should have been there (hard failure).
install_backend() {
    local backend="$1"
    rm -rf "$addon"
    mkdir -p "$addon"

    # A prebuilt addon (CI artifact) wins over the local build outputs.
    local prebuilt=""
    case "$backend" in
        gdscript) prebuilt="${LORELINE_GDSCRIPT_ADDON:-}" ;;
        # The shipped native package carries bin/web/*.wasm and a .gdextension
        # listing every platform, so it serves the web backend as-is.
        web)      prebuilt="${LORELINE_WEB_ADDON:-${LORELINE_NATIVE_ADDON:-}}" ;;
        *)        prebuilt="${LORELINE_NATIVE_ADDON:-}" ;;
    esac
    if [ -n "$prebuilt" ]; then
        if [ ! -d "$prebuilt" ]; then
            echo "prebuilt addon not found at $prebuilt"
            return 2
        fi
        cp -R "$prebuilt/." "$addon/"
        resign_if_macos
        return 0
    fi

    if [ "$backend" = "gdscript" ]; then
        if [ ! -d "$repo/godot/gdscript/internal" ]; then
            echo "not built (run: node ./setup --gdscript)"
            return 1
        fi
        cp -R "$repo/godot/gdscript/." "$addon/"
        return 0
    fi

    if [ "$backend" = "web" ]; then
        local wasm="$repo/godot/bin/libloreline_godot.nothreads.wasm"
        local wasm_threads="$repo/godot/bin/libloreline_godot.wasm"
        if [ ! -f "$wasm" ]; then
            echo "not built (run: node ./setup --js && node ./setup --godot-wasm)"
            return 1
        fi
        mkdir -p "$addon/bin/web"
        cp "$wasm" "$addon/bin/web/"
        [ -f "$wasm_threads" ] && cp "$wasm_threads" "$addon/bin/web/"
        cat > "$addon/loreline.gdextension" <<EOF
[configuration]
entry_symbol = "loreline_library_init"
compatibility_minimum = "4.2"

[libraries]
web.debug.threads.wasm32 = "res://addons/loreline/bin/web/libloreline_godot.wasm"
web.release.threads.wasm32 = "res://addons/loreline/bin/web/libloreline_godot.wasm"
web.debug.wasm32 = "res://addons/loreline/bin/web/libloreline_godot.nothreads.wasm"
web.release.wasm32 = "res://addons/loreline/bin/web/libloreline_godot.nothreads.wasm"
EOF
        return 0
    fi

    # Native: pick up the host platform's freshly built binaries.
    local os arch libdir ext runtime
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
        Darwin)
            libdir="macos"; ext="dylib"
            runtime="$repo/build/cpp-lib/mac/libLoreline.dylib"
            gdext="$repo/godot/bin/libloreline_godot.dylib"
            ;;
        Linux)
            libdir="linux"
            [ "$arch" = "aarch64" ] && arch="arm64" || arch="x86_64"
            ext="so"
            runtime="$repo/build/cpp-lib/linux/libLoreline.$arch.so"
            gdext="$repo/godot/bin/libloreline_godot.$arch.so"
            ;;
        *)
            echo "unsupported host OS: $os"
            return 2
            ;;
    esac

    if [ ! -f "$gdext" ] || [ ! -f "$runtime" ]; then
        echo "not built (run: node ./setup --cpp-lib && node ./setup --godot)"
        return 1
    fi

    mkdir -p "$addon/bin/$libdir"
    cp "$gdext" "$addon/bin/$libdir/"
    cp "$runtime" "$addon/bin/$libdir/"
    local gdext_name runtime_name
    gdext_name="$(basename "$gdext")"
    runtime_name="$(basename "$runtime")"

    resign_if_macos

    cat > "$addon/loreline.gdextension" <<EOF
[configuration]
entry_symbol = "loreline_library_init"
compatibility_minimum = "4.2"

[libraries]
$libdir.debug = "res://addons/loreline/bin/$libdir/$gdext_name"
$libdir.release = "res://addons/loreline/bin/$libdir/$gdext_name"

[dependencies]
$libdir.debug = { "res://addons/loreline/bin/$libdir/$runtime_name": "" }
$libdir.release = { "res://addons/loreline/bin/$libdir/$runtime_name": "" }
EOF
    return 0
}

# Exports the project for web, serves it, and drives it in headless Chromium.
# The browser console is echoed so a failure reads like the other backends.
run_web() {
    local out_dir="$here/.web-out"
    rm -rf "$out_dir"; mkdir -p "$out_dir"
    if ! "$godot" --headless --path "$here" --export-debug Web "$out_dir/index.html" > "$here/.web-export.log" 2>&1; then
        echo "ERROR: web export failed" >&2
        tail -20 "$here/.web-export.log" >&2
        return 1
    fi

    # Playwright, installed on demand next to this script. The marker
    # package.json keeps npm from walking up and installing into the repo root
    # (which would edit the repo's own package.json).
    if [ ! -d "$here/node_modules/playwright" ]; then
        [ -f "$here/package.json" ] || echo '{"name":"loreline-lifetime-web","private":true}' > "$here/package.json"
        ( cd "$here" && npm install playwright --no-fund --no-audit >/dev/null 2>&1 \
          && npx playwright install chromium >/dev/null 2>&1 ) || {
            echo "ERROR: could not install Playwright" >&2; return 1; }
    fi

    # .cjs, not .js: the repo's package.json declares "type": "module".
    cat > "$here/.web-driver.cjs" <<'JSEOF'
const { chromium } = require('playwright');
const url = process.argv[2];
(async () => {
    const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader'] });
    const page = await browser.newPage();
    let done = false, code = 1;
    page.on('console', (m) => {
        const t = m.text();
        console.log(t);
        if (t.includes('ALL_LIFETIME_TESTS_PASSED')) { done = true; code = 0; }
        else if (t.includes('LIFETIME_TESTS_FAILED')) { done = true; code = 1; }
    });
    page.on('pageerror', (e) => console.log('[pageerror] ' + e.message));
    await page.goto(url, { waitUntil: 'load' });
    const deadline = Date.now() + 240000;
    while (!done && Date.now() < deadline) await page.waitForTimeout(500);
    await browser.close();
    if (!done) console.log('LIFETIME_TESTS_FAILED: timed out waiting for the browser');
    process.exit(done ? code : 1);
})();
JSEOF

    cat > "$here/.web-server.py" <<'PYEOF2'
import http.server, socketserver, sys, os
os.chdir(sys.argv[1])
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy','same-origin')
        self.send_header('Cross-Origin-Embedder-Policy','require-corp')
        super().end_headers()
    def log_message(self,*a): pass
socketserver.TCPServer.allow_reuse_address=True
socketserver.TCPServer(('127.0.0.1',8794),H).serve_forever()
PYEOF2

    python3 "$here/.web-server.py" "$out_dir" &
    local server_pid=$!
    sleep 2

    local rc=0
    ( cd "$here" && node .web-driver.cjs "http://127.0.0.1:8794/index.html" ) || rc=$?
    kill "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
    rm -rf "$out_dir" "$here/.web-driver.cjs" "$here/.web-server.py" "$here/.web-export.log"
    return $rc
}

run_backend() {
    local backend="$1"
    echo ""
    echo "############ backend: $backend ############"
    local reason rc
    reason="$(install_backend "$backend")"
    rc=$?
    if [ $rc -eq 2 ]; then
        echo "ERROR: $backend $reason" >&2
        return 1
    elif [ $rc -ne 0 ]; then
        echo "SKIP: $backend $reason"
        return 3
    fi

    rm -rf "$here/.godot"
    if [ "$backend" = "web" ]; then
        # The export needs an imported project. No web binary loads on the
        # host, so this import carries no GDExtension and stays clean.
        "$godot" --headless --path "$here" --import >/dev/null 2>&1 || true
        run_web
        return $?
    fi
    if [ "$backend" = "gdscript" ]; then
        # The GDScript backend needs the editor import: it is what fills
        # .godot/global_script_class_cache.cfg, and the runtime resolves
        # `Loreline` and friends through that. No GDExtension is involved here,
        # so this import is clean and its exit status is checked.
        if ! "$godot" --headless --path "$here" --import >/dev/null 2>&1; then
            echo "ERROR: project import failed for the $backend backend" >&2
            return 1
        fi
    else
        # Deliberately no editor import for the native backend. Godot 4.6
        # crashes on headless shutdown of an editor run that has a GDExtension
        # loaded: EditorHelp::_gen_extensions_docs is deferred onto the call
        # queue and then runs from Main::cleanup, after the state it reads has
        # been torn down. Nothing here needs the editor anyway, since the
        # runtime loads extensions from this file, so write it directly and
        # skip the editor entirely. Keeps CI free of native crashes.
        mkdir -p "$here/.godot"
        echo "res://addons/loreline/loreline.gdextension" > "$here/.godot/extension_list.cfg"
    fi
    local out
    out="$("$godot" --headless --path "$here" res://lifetime_scene.tscn 2>&1)"
    echo "$out"
    if echo "$out" | grep -q "ALL_LIFETIME_TESTS_PASSED"; then
        return 0
    fi
    return 1
}

status=0
skipped=""
for backend in gdscript native web; do
    case "$which_backend" in
        all|both) ;;
        "$backend") ;;
        *) continue ;;
    esac
    run_backend "$backend"
    rc=$?
    if [ $rc -eq 3 ]; then
        skipped="$skipped $backend"
        if [ "${LORELINE_LIFETIME_REQUIRE_ALL:-}" = "1" ]; then
            echo "ERROR: $backend was skipped but every backend is required" >&2
            status=1
        fi
    elif [ $rc -ne 0 ]; then
        echo "FAILED: $backend"
        status=1
    fi
done

rm -rf "$addon" "$here/.godot"

echo ""
if [ -n "$skipped" ]; then
    echo "skipped backends:$skipped"
fi
if [ $status -eq 0 ]; then
    echo "LIFETIME_TESTS_OK"
else
    echo "LIFETIME_TESTS_FAILED"
fi
exit $status
