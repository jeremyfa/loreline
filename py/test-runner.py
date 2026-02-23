#!/usr/bin/env python3
"""Loreline Python test runner.

Follows the same test protocol as the JS, C#, and C++ test runners:
  - Collects .lor files from the given directory
  - Extracts <test> YAML blocks from /* */ comments
  - Runs each test in LF and CRLF modes
  - Runs roundtrip (parse -> print -> parse -> print) stability checks
  - Reports pass/fail counts
"""

import os
import re
import sys

# Ensure the py/ package is importable when run from the repo root
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from loreline._core import loreline_Loreline, loreline_Interpreter, _hx_AnonObject  # noqa: E402

pass_count = 0
fail_count = 0


# ── Helpers ──────────────────────────────────────────────────────────────

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
    """Replicate TestRunner.insertTagsInText — insert tag markers into text."""
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
            # Empty line — could be part of block or end of it
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


# ── Test runner ──────────────────────────────────────────────────────────

def run_test(file_path, content, test_item, crlf):
    """Run a single test case. Returns (passed, actual, expected, error)."""
    # Normalize line endings
    if crlf:
        content = content.replace("\r\n", "\n").replace("\n", "\r\n")
    else:
        content = content.replace("\r\n", "\n")

    choices = list(test_item.get("choices", []) or [])
    beat_name = test_item.get("beat") or None
    save_at_choice = test_item.get("saveAtChoice", -1)
    if save_at_choice is None:
        save_at_choice = -1
    save_at_dialogue = test_item.get("saveAtDialogue", -1)
    if save_at_dialogue is None:
        save_at_dialogue = -1
    expected = test_item["expected"]
    output = [""]  # Use list for mutability in closures
    choice_count = [0]
    dialogue_count = [0]
    parsed_script = [None]
    result = [None]  # (passed, actual, expected, error)

    # Build options
    options = None
    translation_val = test_item.get("translation")
    if translation_val:
        lang = translation_val
        base_path = file_path[: -4]  # strip .lor
        translation_path = base_path + "." + lang + ".lor"
        with open(translation_path, "r", encoding="utf-8") as f:
            translation_content = f.read()
        if crlf:
            translation_content = translation_content.replace("\r\n", "\n").replace("\n", "\r\n")
        else:
            translation_content = translation_content.replace("\r\n", "\n")
        translation_script = loreline_Loreline.parse(
            translation_content, translation_path, handle_file
        )
        if translation_script:
            translations = loreline_Loreline.extractTranslations(translation_script)
            options = _hx_AnonObject({"translations": translations})

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

    def on_dialogue(interp, character, text, tags, advance):
        multiline = "\n" in text
        if tags is None:
            tags = []
        if character is not None:
            char_name = interp.getCharacterField(character, "name")
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

        # Save/restore test at dialogue
        if save_at_dialogue >= 0 and dialogue_count[0] == save_at_dialogue:
            dialogue_count[0] += 1
            save_data = interp.save()

            if restore_input is not None:
                restore_script = loreline_Loreline.parse(
                    restore_input, file_path, handle_file
                )
                if restore_script:
                    loreline_Loreline.resume(
                        restore_script, on_dialogue, on_choice, on_finish,
                        save_data, None, options
                    )
                else:
                    result[0] = (False, output[0], expected, "Error parsing restoreInput script")
            else:
                loreline_Loreline.resume(
                    parsed_script[0], on_dialogue, on_choice, on_finish,
                    save_data, None, options
                )
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

        # Save/restore test
        if save_at_choice >= 0 and choice_count[0] == save_at_choice:
            choice_count[0] += 1
            save_data = interp.save()

            if restore_input is not None:
                restore_script = loreline_Loreline.parse(
                    restore_input, file_path, handle_file
                )
                if restore_script:
                    loreline_Loreline.resume(
                        restore_script, on_dialogue, on_choice, on_finish,
                        save_data, None, options
                    )
                else:
                    result[0] = (False, output[0], expected, "Error parsing restoreInput script")
            else:
                loreline_Loreline.resume(
                    parsed_script[0], on_dialogue, on_choice, on_finish,
                    save_data, None, options
                )
            return

        choice_count[0] += 1

        if not choices:
            on_finish(interp)
        else:
            index = choices.pop(0)
            select(index)

    try:
        script = loreline_Loreline.parse(content, file_path, handle_file)
        if script:
            parsed_script[0] = script
            loreline_Loreline.play(
                script, on_dialogue, on_choice, on_finish, beat_name, options
            )
        else:
            result[0] = (False, output[0], expected, "Error parsing script")
    except Exception as e:
        result[0] = (False, output[0], expected, str(e))

    if result[0] is None:
        result[0] = (False, output[0], expected, "Test did not produce a result")

    return result[0]


# ── Main ─────────────────────────────────────────────────────────────────

def main():
    global pass_count, fail_count

    if len(sys.argv) < 2:
        print("Usage: python3 py/test-runner.py <test-directory>", file=sys.stderr)
        sys.exit(1)

    test_dir = sys.argv[1]
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
                script1 = loreline_Loreline.parse(content, file_path, handle_file)
                if not script1:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    print("  Error: Failed to parse original script")
                    continue

                # Structural check: print -> parse -> print must be stable
                print1 = loreline_Loreline.print(script1, "  ", newline)
                script2 = loreline_Loreline.parse(print1, file_path, handle_file)
                if not script2:
                    fail_count += 1
                    print(f"\033[1m\033[31mFAIL\033[0m - \033[90m{label}\033[0m")
                    print("  Error: Failed to parse printed script")
                    continue
                print2 = loreline_Loreline.print(script2, "  ", newline)

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

    total = pass_count + fail_count
    print()
    if fail_count == 0:
        print(f"\033[1m\033[32m  All {total} tests passed\033[0m")
    else:
        print(f"\033[1m\033[31m  {fail_count} of {total} tests failed\033[0m")
        sys.exit(1)


if __name__ == "__main__":
    main()
