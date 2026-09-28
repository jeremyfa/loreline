#!/usr/bin/env python3
"""Loreline Python test runner.

Follows the same test protocol as the JS, C#, and C++ test runners:
  - Collects .lor files from the given directory
  - Extracts <test> YAML blocks from /* */ comments
  - Runs each test in LF and CRLF modes
  - Runs roundtrip (parse -> print -> parse -> print) stability checks
  - Reports pass/fail counts

Drives the PUBLIC `loreline` binding (the same API a real user uses), so the
suite exercises the public wrapper layer end to end, including custom functions.

Note: ast-print is intentionally only run by the CLI test runner.
AstPrinter is a pure Haxe debug pretty-printer with no target-specific
behavior, so a single CLI run is enough to catch any missing node-type
case. That's why the CLI test count is higher than each per-target
runner's count.
"""

import os
import re
import sys

# Ensure the py/ package is importable when run from the repo root
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from loreline import Loreline, Script  # noqa: E402
from loreline import _core  # noqa: E402

pass_count = 0
fail_count = 0
file_count = 0
file_fail_count = 0


# Canonical host-registered functions used by test/Functions-Custom.lor to verify
# the custom-function contract via the PUBLIC API: each receives (interpreter, args),
# where `interpreter` is the public Python Interpreter wrapper (snake_case) and
# `args` is a native list, and the interpreter can read/write runtime state.
custom_test_functions = {
    "custom_echo": lambda interp, args: ",".join(str(a) for a in args),
    "custom_arg_count": lambda interp, args: len(args),
    "custom_set_state": lambda interp, args: interp.set_state_field(args[0], args[1]),
    "custom_get_state": lambda interp, args: interp.get_state_field(args[0]),
}


# -- Helpers --------------------------------------------------------------

def collect_test_files(directory):
    """Recursively collect .lor test files, skipping imports/ and modified/ dirs."""
    files = []
    for entry in sorted(os.listdir(directory)):
        full_path = os.path.join(directory, entry)
        if os.path.isdir(full_path):
            if entry not in ("imports", "modified"):
                files.extend(collect_test_files(full_path))
        elif entry.endswith(".lor") and not re.search(r"\.\w{2}\.lor$", entry):
            files.append(full_path)
    return files


def handle_file(path, callback):
    """File handler for imports."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            callback(f.read())
    except Exception:
        callback(None)


def insert_tags_in_text(text, tags, multiline):
    """Replicate TestRunner.insertTagsInText: insert tag markers into text."""
    offsets_with_tags = set()
    for tag in tags:
        offsets_with_tags.add(tag.offset)

    chars = list(text)
    length = len(chars)
    result = []

    for i in range(length):
        if i in offsets_with_tags:
            for tag in tags:
                if tag.offset == i:
                    result.append("<<")
                    if tag.closing:
                        result.append("/")
                    result.append(tag.value)
                    result.append(">>")
        c = chars[i]
        if multiline and c == "\n":
            result.append("\n  ")
        else:
            result.append(c)

    # Tags at end of text
    for tag in tags:
        if tag.offset >= length:
            result.append("<<")
            if tag.closing:
                result.append("/")
            result.append(tag.value)
            result.append(">>")

    return "".join(result).rstrip()


def compare_output(expected, actual):
    """Compare output, return -1 if match or line index of first difference."""
    expected_lines = expected.replace("\r\n", "\n").strip().split("\n")
    actual_lines = actual.replace("\r\n", "\n").strip().split("\n")
    min_len = min(len(expected_lines), len(actual_lines))
    max_len = max(len(expected_lines), len(actual_lines))

    for i in range(min_len):
        if expected_lines[i] != actual_lines[i]:
            return i
    if min_len < max_len:
        return min_len
    return -1


def parse_simple_yaml(text):
    """Minimal YAML parser for test blocks.

    Supports the subset used by loreline tests:
      - Top-level list of maps (``- key: value``)
      - Scalar values: strings, integers, booleans
      - Inline flow sequences: ``[0, 1, 2]``
      - Block scalar with ``|`` (literal block)
    """
    lines = text.split("\n")
    items = []
    current = None
    block_key = None
    block_indent = 0
    block_lines = []
    i = 0

    def flush_block():
        nonlocal block_key, block_lines
        if block_key and current is not None:
            # Strip trailing empty lines, then add single trailing newline (YAML |)
            while block_lines and block_lines[-1] == "":
                block_lines.pop()
            current[block_key] = "\n".join(block_lines) + "\n"
        block_key = None
        block_lines = []

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()

        # Inside a block scalar?
        if block_key is not None:
            # Empty line, could be part of block or end of it
            if stripped == "":
                # Peek ahead: if next non-empty line is still indented, this is part of block
                block_lines.append("")
                i += 1
                continue
            # Check if this line is indented at the block level
            if len(line) >= block_indent and line[:block_indent] == " " * block_indent:
                block_lines.append(line[block_indent:].rstrip())
                i += 1
                continue
            else:
                flush_block()
                # Fall through to process this line normally

        # New list item
        m = re.match(r"^- (\w+):\s*(.*)", stripped)
        if m:
            current = {}
            items.append(current)
            key = m.group(1)
            value = m.group(2)
            if value == "|":
                block_key = key
                block_indent = 4  # "- " is 2 + "  " content indent = 4
                block_lines = []
            else:
                current[key] = _parse_yaml_value(value)
            i += 1
            continue

        # Continuation key in current item
        m2 = re.match(r"^  (\w+):\s*(.*)", stripped)
        if m2 and current is not None:
            key = m2.group(1)
            value = m2.group(2)
            if value == "|":
                block_key = key
                block_indent = 4  # 2 (item indent) + 2 (content indent)
                block_lines = []
            else:
                current[key] = _parse_yaml_value(value)
            i += 1
            continue

        i += 1

    flush_block()
    return items


def _parse_yaml_value(s):
    """Parse a simple YAML scalar or inline flow sequence."""
    s = s.strip()
    if not s:
        return None
    # Inline flow sequence: [0, 1, 2]
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [_parse_yaml_value(v.strip()) for v in inner.split(",")]
    # Integer
    if re.match(r"^-?\d+$", s):
        return int(s)
    # Boolean
    if s == "true":
        return True
    if s == "false":
        return False
    # Null
    if s == "null" or s == "~":
        return None
    # String (strip optional quotes)
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s


def extract_tests(content):
    """Extract <test> YAML blocks from a .lor file."""
    tests = []
    for match in re.finditer(r"<test>([\s\S]*?)</test>", content):
        yaml_content = match.group(1).strip()
        parsed = parse_simple_yaml(yaml_content)
        if isinstance(parsed, list):
            tests.extend(parsed)
    return tests


# -- Test runner ----------------------------------------------------------

def save_indices(raw):
    """Read a saveAtChoice / saveAtDialogue value: absent, one index, or a list of indices."""
    if raw is None:
        return []
    if isinstance(raw, int) and not isinstance(raw, bool):
        return [raw]
    if isinstance(raw, list) and all(isinstance(v, int) and not isinstance(v, bool) for v in raw):
        return list(raw)
    raise ValueError("Invalid save indices: " + repr(raw))


def json_round_trip(save_data):
    """Pass save data through JSON, like a host storing it."""
    return _core.loreline_Json.parse(_core.loreline_Json.stringify(save_data, False))


def run_test(file_path, content, test_item, crlf):
    """Run a single test case. Returns (passed, actual, expected, error)."""
    # Normalize line endings
    if crlf:
        content = content.replace("\r\n", "\n").replace("\n", "\r\n")
    else:
        content = content.replace("\r\n", "\n")

    choices = list(test_item.get("choices", []) or [])
    beat_name = test_item.get("beat") or None
    save_at_choice = save_indices(test_item.get("saveAtChoice"))
    save_at_dialogue = save_indices(test_item.get("saveAtDialogue"))
    expected = test_item["expected"]
    output = [""]  # Use list for mutability in closures
    choice_count = [0]
    dialogue_count = [0]
    # Set after a save: the event re-presented by the restore is not counted,
    # so that save indices refer to the events of an uninterrupted run
    replaying_dialogue = [False]
    replaying_choice = [False]
    parsed_script = [None]
    result = [None]  # (passed, actual, expected, error)

    # Parse the script up-front so load_locale can walk its import tree
    early_script = Loreline.parse(content, file_path, handle_file)

    # Translations are loaded across the import tree; passed to play/resume as a kwarg
    translations = None
    translation_val = test_item.get("translation")
    if translation_val and early_script:
        translations = Loreline.load_locale(
            translation_val, early_script, file_path, handle_file
        )

    # Load restoreFile content if specified
    restore_input = None
    if test_item.get("restoreFile"):
        restore_path = os.path.join(os.path.dirname(file_path), test_item["restoreFile"])
        with open(restore_path, "r", encoding="utf-8") as f:
            restore_input = f.read()
        if crlf:
            restore_input = restore_input.replace("\r\n", "\n").replace("\n", "\r\n")
        else:
            restore_input = restore_input.replace("\r\n", "\n")

    def on_finish(interp):
        cmp = compare_output(expected, output[0])
        result[0] = (cmp == -1, output[0], expected, None)

    def resume(script, save_data):
        Loreline.resume(
            script, on_dialogue, on_choice, on_finish, save_data,
            functions=custom_test_functions, translations=translations,
        )

    def on_dialogue(interp, character, text, tags, advance):
        multiline = "\n" in text
        if tags is None:
            tags = []
        if character is not None:
            char_name = interp.get_character_field(character, "name")
            if char_name is None:
                char_name = character
            tagged_text = insert_tags_in_text(text, tags, multiline)
            if multiline:
                output[0] += char_name + ":\n  " + tagged_text + "\n\n"
            else:
                output[0] += char_name + ": " + tagged_text + "\n\n"
        else:
            tagged_text = insert_tags_in_text(text, tags, multiline)
            output[0] += "~ " + tagged_text + "\n\n"

        if replaying_dialogue[0]:
            replaying_dialogue[0] = False
            advance()
            return

        # Save/restore test at dialogue
        if dialogue_count[0] in save_at_dialogue:
            dialogue_count[0] += 1
            replaying_dialogue[0] = True
            save_data = json_round_trip(interp.save())

            if restore_input is not None:
                restore_script = Loreline.parse(restore_input, file_path, handle_file)
                if restore_script:
                    resume(restore_script, save_data)
                else:
                    result[0] = (False, output[0], expected, "Error parsing restoreInput script")
            else:
                resume(parsed_script[0], save_data)
            return

        dialogue_count[0] += 1
        advance()

    def on_choice(interp, choice_options, select):
        for opt in choice_options:
            prefix = "+" if opt.enabled else "-"
            multiline = "\n" in opt.text
            opt_tags = opt.tags if opt.tags is not None else []
            tagged_text = insert_tags_in_text(opt.text, opt_tags, multiline)
            output[0] += prefix + " " + tagged_text + "\n"
        output[0] += "\n"

        # Save/restore test (the re-presented choice is not counted)
        replayed = replaying_choice[0]
        if replaying_choice[0]:
            replaying_choice[0] = False
        elif choice_count[0] in save_at_choice:
            choice_count[0] += 1
            replaying_choice[0] = True
            save_data = json_round_trip(interp.save())

            if restore_input is not None:
                restore_script = Loreline.parse(restore_input, file_path, handle_file)
                if restore_script:
                    resume(restore_script, save_data)
                else:
                    result[0] = (False, output[0], expected, "Error parsing restoreInput script")
            else:
                resume(parsed_script[0], save_data)
            return

        if not replayed:
            choice_count[0] += 1

        if not choices:
            on_finish(interp)
        else:
            index = choices.pop(0)
            select(index)

    try:
        script = early_script
        if script:
            parsed_script[0] = script
            Loreline.play(
                script, on_dialogue, on_choice, on_finish, beat_name,
                functions=custom_test_functions, translations=translations,
            )
        else:
            result[0] = (False, output[0], expected, "Error parsing script")
    except Exception as e:
        result[0] = (False, output[0], expected, str(e))

    if result[0] is None:
        result[0] = (False, output[0], expected, "Test did not produce a result")

    return result[0]


# -- Main -----------------------------------------------------------------

def main():
    global pass_count, fail_count, file_count, file_fail_count

    if len(sys.argv) < 2:
        print("Usage: python3 py/test-runner.py <test-directory>", file=sys.stderr)
        sys.exit(1)

    test_dir = sys.argv[1]

    # Test fixtures exercise every supported translation format.
    Loreline.translation_format("po", True)
    Loreline.translation_format("xliff", True)
    Loreline.translation_format("csv", True)

    test_files = collect_test_files(test_dir)

    if not test_files:
        print("No test files found in", test_dir, file=sys.stderr)
        sys.exit(1)

    for file_path in test_files:
        with open(file_path, "r", encoding="utf-8") as f:
            raw_content = f.read()

        test_items = extract_tests(raw_content)
        if not test_items:
            continue

        file_count += 1
        fail_before = fail_count

        for item in test_items:
            for crlf in (False, True):
                mode_label = "CRLF" if crlf else "LF"
                choices_label = ""
                if item.get("choices"):
                    choices_label = " ~ [" + ",".join(str(c) for c in item["choices"]) + "]"
                label = f"{file_path} ~ {mode_label}{choices_label}"

                passed, actual, expected, error = run_test(file_path, raw_content, item, crlf)

                if passed:
                    pass_count += 1
                    print(f"\033[1m\033[32mPASS\033[0m - \033[90m{label}\033[0m")
                else:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    if error:
                        print(f"  Error: {error}")

                    # Show diff
                    expected_lines = expected.replace("\r\n", "\n").strip().split("\n")
                    actual_lines = actual.replace("\r\n", "\n").strip().split("\n")
                    min_len = min(len(expected_lines), len(actual_lines))

                    shown = False
                    for i in range(min_len):
                        if expected_lines[i] != actual_lines[i]:
                            print(f"  > Unexpected output at line {i + 1}")
                            print(f"  >  got: {actual_lines[i]}")
                            print(f"  > need: {expected_lines[i]}")
                            shown = True
                            break
                    if not shown and min_len < max(len(expected_lines), len(actual_lines)):
                        if min_len < len(actual_lines):
                            print(f"  > Unexpected output at line {min_len + 1}")
                            print(f"  >  got: {actual_lines[min_len]}")
                            print(f"  > need: (empty)")
                        else:
                            print(f"  > Unexpected output at line {min_len + 1}")
                            print(f"  >  got: (empty)")
                            print(f"  > need: {expected_lines[min_len]}")

        # Roundtrip tests for each mode
        for crlf in (False, True):
            mode_label = "CRLF" if crlf else "LF"
            label = f"{file_path} ~ {mode_label} ~ roundtrip"
            newline = "\r\n" if crlf else "\n"

            try:
                # Normalize content for this mode
                content = raw_content.replace("\r\n", "\n")
                if crlf:
                    content = content.replace("\n", "\r\n")

                # Parse original
                script1 = Loreline.parse(content, file_path, handle_file)
                if not script1:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    print("  Error: Failed to parse original script")
                    continue

                # Structural check: print -> parse -> print must be stable
                print1 = Loreline.print(script1, "  ", newline)
                script2 = Loreline.parse(print1, file_path, handle_file)
                if not script2:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    print("  Error: Failed to parse printed script")
                    continue
                print2 = Loreline.print(script2, "  ", newline)

                if print1 != print2:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    lines1 = print1.replace("\r\n", "\n").split("\n")
                    lines2 = print2.replace("\r\n", "\n").split("\n")
                    ml = min(len(lines1), len(lines2))
                    for i in range(ml):
                        if lines1[i] != lines2[i]:
                            print(f"  > Printer output not idempotent at line {i + 1}")
                            print(f"  >  print1: {lines1[i]}")
                            print(f"  >  print2: {lines2[i]}")
                            break
                    if len(lines1) != len(lines2):
                        print(f"  > Line count differs: print1={len(lines1)}, print2={len(lines2)}")
                    continue

                # Behavioral check: run each test item on the printed content
                all_passed = True
                first_error = None
                first_expected = None
                first_actual = None

                for item in test_items:
                    passed, actual, expected_str, error = run_test(
                        file_path, print1, item, crlf
                    )
                    if not passed:
                        all_passed = False
                        if first_error is None:
                            first_error = error
                            first_expected = expected_str
                            first_actual = actual

                if all_passed:
                    pass_count += 1
                    print(f"\033[1m\033[32mPASS\033[0m - \033[90m{label}\033[0m")
                else:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    if first_error:
                        print(f"  Error: {first_error}")
                    if first_expected and first_actual:
                        el = first_expected.replace("\r\n", "\n").strip().split("\n")
                        al = first_actual.replace("\r\n", "\n").strip().split("\n")
                        ml = min(len(el), len(al))
                        for i in range(ml):
                            if el[i] != al[i]:
                                print(f"  > Unexpected output at line {i + 1}")
                                print(f"  >  got: {al[i]}")
                                print(f"  > need: {el[i]}")
                                break

            except Exception as e:
                fail_count += 1
                print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                print(f"  Error: {e}")

        # JSON roundtrip test
        for crlf in [False, True]:
            mode_label = "CRLF" if crlf else "LF"
            json_label = f"{file_path} ~ {mode_label} ~ json-roundtrip"
            try:
                content = raw_content.replace("\r\n", "\n")
                if crlf:
                    content = content.replace("\n", "\r\n")
                script = Loreline.parse(content, file_path, handle_file)
                if not script:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{json_label}\033[0m")
                    print("  Error: Failed to parse script")
                else:
                    json1 = script.to_json()
                    script2 = Script.from_json(json1)
                    json2 = script2.to_json()

                    if json1 == json2:
                        pass_count += 1
                        print(f"\033[1m\033[32mPASS\033[0m - \033[90m{json_label}\033[0m")
                    else:
                        fail_count += 1
                        print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{json_label}\033[0m")
                        print("  > JSON mismatch after roundtrip")
            except Exception as e:
                fail_count += 1
                print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{json_label}\033[0m")
                print(f"  Error: {e}")

        if fail_count > fail_before:
            file_fail_count += 1

    run_spawn_test()
    run_seed_random_test()

    total = pass_count + fail_count
    print()
    if fail_count == 0:
        print(f"\033[1m\033[32m  All {total} tests passed ({file_count} files)\033[0m")
    else:
        print(f"\033[1m\033[31m  {fail_count} of {total} tests failed ({file_fail_count} of {file_count} files)\033[0m")
        sys.exit(1)


# Child interpreters: same scenario in every binding runner. A child spawned from the
# root shares its state, gets host functions bound to itself, and both playheads are
# saved from any interpreter then continued after a restore with resume_spawn().
SPAWN_SCRIPT = "\n".join([
    "state",
    "  gold: 0",
    "",
    "beat Main",
    "  gold = gold + 1",
    "",
    "  Main gold $gold",
    "",
    "  Main where $current_beat() host $who()",
    "",
    "beat Side",
    "  new state",
    "    local: 5",
    "",
    "  gold = gold + 10",
    "",
    "  Side gold $gold local $local",
    "",
    "  Side where $current_beat() host $who()",
    "",
])

SPAWN_EXPECTED = [
    "root: Main gold 1",
    "npc: Side gold 11 local 5",
    "root: Main where Main host root",
    "root: Main where Main host root",
    "npc: Side gold 11 local 5",
    "npc: Side where Side host npc",
]


# The random generator is saved, and seed_random() reseeds it from the host: same
# scenario in every binding runner. After a restore at the first line, reseeding with
# the seed of the script makes the second line draw what the first one drew.
RANDOM_SCRIPT = "\n".join([
    "beat Main",
    "  seed_random(7)",
    "  First $random(1, 1000000000)",
    "",
    "  Second $random(1, 1000000000)",
    "",
])


def run_seed_random_test():
    global pass_count, fail_count
    label = "random: seedRandom after restore"
    try:
        log = []
        pending = []

        def dialogue(interp, character, text, tags, advance):
            log.append(text)
            pending.append(advance)

        script = Loreline.parse(RANDOM_SCRIPT)
        root = Loreline.play(script, dialogue, lambda i, o, s: None, lambda i: None)
        save_data = root.save()

        restored = Loreline.resume(script, dialogue, lambda i, o, s: None, lambda i: None, save_data)
        restored.seed_random(7)
        pending[-1]()

        first = log[0].split(" ")[1]
        second = log[2].split(" ")[1] if len(log) > 2 else ""
        if second != first:
            raise Exception(f"expected {first} after reseeding, got {' / '.join(log)}")

        pass_count += 1
        print(f"\033[1m\033[32mPASS\033[0m - \033[90m{label}\033[0m")
    except Exception as e:
        fail_count += 1
        print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
        print(f"  Error: {e}")


def run_spawn_test():
    global pass_count, fail_count
    label = "spawn: shared state, bound functions, save and resumeSpawn"
    try:
        log = []
        pending = {}

        def name_of(interp):
            return interp.key if interp.key is not None else "root"

        def dialogue(interp, character, text, tags, advance):
            log.append(f"{name_of(interp)}: {character + ': ' if character is not None else ''}{text}")
            pending[name_of(interp)] = advance

        def choice(interp, options, select):
            pass

        def finish(interp):
            pass

        def next_dialogue(name):
            cb = pending.pop(name, None)
            if cb is None:
                raise Exception(f"No pending dialogue for {name}")
            cb()

        functions = {"who": lambda interp, args: name_of(interp)}

        script = Loreline.parse(SPAWN_SCRIPT)
        root = Loreline.play(script, dialogue, choice, finish, functions=functions)
        npc = root.spawn("npc", dialogue, choice, finish)
        npc.start("Side")
        next_dialogue("root")

        checks = []
        if npc.key != "npc":
            checks.append(f"child key: {npc.key}")
        if root.key is not None:
            checks.append(f"root key: {root.key}")
        if npc.is_root() or not root.is_root():
            checks.append("is_root")
        save_data = npc.save()
        if len(save_data.children) != 1 or len(root.save().children) != 1:
            checks.append("save from child does not include both playheads")

        pending.clear()
        restored = Loreline.resume(script, dialogue, choice, finish, save_data, functions=functions)
        keys = restored.resumable_spawn_keys()
        if keys != ["npc"]:
            checks.append(f"resumable_spawn_keys: {keys}")
        restored.resume_spawn("npc", dialogue, choice, finish).resume()
        next_dialogue("npc")

        if log != SPAWN_EXPECTED:
            checks.append("log:\n    " + "\n    ".join(log))
        if checks:
            raise Exception("; ".join(checks))

        pass_count += 1
        print(f"\033[1m\033[32mPASS\033[0m - \033[90m{label}\033[0m")
    except Exception as e:
        fail_count += 1
        print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
        print(f"  Error: {e}")


if __name__ == "__main__":
    main()
