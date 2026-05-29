#!/usr/bin/env bash
set -u

# Run a Godot scene from the sample project in headless mode and assert that
# the captured stdout contains all required substring markers.
#
# Usage:
#   bash run-headless-test.sh <scene-path-from-project-root> <marker> [<marker> ...]
#
# Example:
#   bash run-headless-test.sh scenes/test_saverestore.tscn "TEST PASSED"
#
# Godot binary resolution: $GODOT_BIN, then `godot` on PATH, then on macOS
# /Applications/Godot.app/Contents/MacOS/Godot.
#
# Timeout: uses `timeout` (GNU coreutils), `gtimeout` (brew coreutils on macOS),
# or falls back to a tiny perl alarm. Default 30 seconds, override with
# $RUN_TIMEOUT.

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <scene-path> <marker> [<marker> ...]" >&2
    exit 2
fi

scene="$1"
shift
markers=("$@")

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

# Resolve timeout
timeout_secs="${RUN_TIMEOUT:-30}"
if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout "$timeout_secs")
elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd=(gtimeout "$timeout_secs")
else
    timeout_cmd=(perl -e 'alarm shift @ARGV; exec @ARGV or die "$!"' "$timeout_secs")
fi

log_dir="${TMPDIR:-/tmp}"
log_file="$log_dir/loreline-godot-test-$$-$(basename "$scene" .tscn).log"

echo "==> godot: $godot"
echo "==> scene: res://$scene"
echo "==> log:   $log_file"
echo "==> timeout: ${timeout_secs}s"
echo

set +e
"${timeout_cmd[@]}" \
    "$godot" --headless --path "$project_dir" "res://$scene" 2>&1 \
    | tee "$log_file"
exit_code=${PIPESTATUS[0]}
set -e

echo
echo "==> godot exit code: $exit_code"

# 124 = timeout fired (both GNU timeout and the perl fallback's SIGALRM
# typically yield a non-zero, non-124 code, so we treat any non-zero as
# potential timeout when no markers are found).
if [ "$exit_code" -eq 124 ]; then
    echo "FAIL: godot timed out after ${timeout_secs}s" >&2
    exit 1
fi

# Hard failure marker — only the test scripts ever print this.
if grep -q "TEST FAILED:" "$log_file"; then
    echo "FAIL: scene reported TEST FAILED" >&2
    exit 1
fi

missing=()
for marker in "${markers[@]}"; do
    if ! grep -F -q -- "$marker" "$log_file"; then
        missing+=("$marker")
    fi
done

if [ "${#missing[@]}" -ne 0 ]; then
    echo "FAIL: missing required markers:" >&2
    for m in "${missing[@]}"; do
        echo "  - $m" >&2
    done
    exit 1
fi

echo "OK: all ${#markers[@]} markers found"
exit 0
