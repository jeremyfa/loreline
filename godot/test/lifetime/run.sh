#!/usr/bin/env bash
set -u

# Runs the backend-agnostic lifetime tests against both Loreline Godot
# backends, one after the other, in the same project. The addon directory is
# swapped between runs because the two backends register the same class names
# and cannot coexist.
#
# Usage: run.sh [gdscript|native|both]   (default: both)
#
# Requirements:
#   - Godot 4 ($GODOT_BIN, `godot` on PATH, or the Mac app bundle).
#   - For the gdscript backend: node ./setup --gdscript
#   - For the native backend:    node ./setup --cpp-lib && node ./setup --godot
#
# CI can skip those builds by pointing at already-assembled addon directories:
#   LORELINE_GDSCRIPT_ADDON=/path/to/addons/loreline
#   LORELINE_NATIVE_ADDON=/path/to/addons/loreline
# Each is used as-is, so the same test runs against exactly what ships. A path
# that is set but missing is a hard failure, never a skip.
#
# Set LORELINE_LIFETIME_REQUIRE_BOTH=1 (CI does) to also fail when a backend is
# skipped for want of binaries, so a misconfigured job cannot pass by testing
# nothing.

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
which_backend="${1:-both}"

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
    if [ "$backend" = "gdscript" ]; then
        prebuilt="${LORELINE_GDSCRIPT_ADDON:-}"
    else
        prebuilt="${LORELINE_NATIVE_ADDON:-}"
    fi
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
    out="$("$godot" --headless --path "$here" --script res://lifetime_tests.gd 2>&1)"
    echo "$out"
    if echo "$out" | grep -q "ALL_LIFETIME_TESTS_PASSED"; then
        return 0
    fi
    return 1
}

status=0
skipped=""
for backend in gdscript native; do
    case "$which_backend" in
        both) ;;
        "$backend") ;;
        *) continue ;;
    esac
    run_backend "$backend"
    rc=$?
    if [ $rc -eq 3 ]; then
        skipped="$skipped $backend"
        if [ "${LORELINE_LIFETIME_REQUIRE_BOTH:-}" = "1" ]; then
            echo "ERROR: $backend was skipped but both backends are required" >&2
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
