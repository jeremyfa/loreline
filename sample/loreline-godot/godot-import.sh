#!/usr/bin/env bash
set -u

# Runs the headless editor import of a Godot project without loading any
# GDExtension, then lists the extensions in .godot/extension_list.cfg so that
# the runs that follow load them as usual.
#
# Why: Godot 4.6 crashes when a headless editor run quits right after loading
# an extension. EditorHelp::_load_doc_thread defers _gen_extensions_docs to the
# main thread, the import is done and quits before that call runs,
# cleanup_doc() frees the doc data, and Main::cleanup then flushes the call
# queue into doc->generate() on a null pointer (editor/doc/editor_help.cpp,
# still the same on master). It only crashes when extension classes are
# registered, which is why a project without an extension imports fine.
# The import itself never needs the extension: .lor files are read by a
# runtime loader, not imported.
#
# Usage: bash godot-import.sh <godot-binary> <project-dir>
# Exits with the status of the import.

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <godot-binary> <project-dir>" >&2
    exit 2
fi

godot="$1"
project_dir="$(cd "$2" && pwd)"
stash="$(mktemp -d)"

# Every .gdextension file of the project (and its .uid), relative to the project
extensions=()
while IFS= read -r path; do
    extensions+=("${path#"$project_dir"/}")
done < <(find "$project_dir" -name "*.gdextension" -not -path "*/.godot/*" | sort)

put_back() {
    for rel in ${extensions[@]+"${extensions[@]}"}; do
        for file in "$rel" "$rel.uid"; do
            if [ -e "$stash/$file" ]; then
                mv "$stash/$file" "$project_dir/$file"
            fi
        done
    done
    rm -rf "$stash"
}
trap put_back EXIT

for rel in ${extensions[@]+"${extensions[@]}"}; do
    for file in "$rel" "$rel.uid"; do
        if [ -e "$project_dir/$file" ]; then
            mkdir -p "$stash/$(dirname "$file")"
            mv "$project_dir/$file" "$stash/$file"
        fi
    done
done
rm -f "$project_dir/.godot/extension_list.cfg"

"$godot" --headless --path "$project_dir" --import
status=$?

put_back
trap - EXIT

if [ ${#extensions[@]} -gt 0 ]; then
    mkdir -p "$project_dir/.godot"
    : > "$project_dir/.godot/extension_list.cfg"
    for rel in "${extensions[@]}"; do
        echo "res://$rel" >> "$project_dir/.godot/extension_list.cfg"
    done
fi

exit $status
