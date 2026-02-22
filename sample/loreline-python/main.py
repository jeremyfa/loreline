#!/usr/bin/env python3
"""
Loreline Python Sample — CoffeeShop

Interactive console app that runs the CoffeeShop story.

Usage:
    python3 main.py
"""

import os
import sys

from loreline import Loreline, Script, Interpreter, ChoiceOption


def read_file(path: str) -> str:
    """Read a file and return its contents, or empty string on error."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def handle_file(path: str, provide):
    """Load an imported file (e.g. characters.lor)."""
    content = read_file(path)
    provide(content)


def handle_dialogue(interp: Interpreter, character, text: str, tags, advance):
    """Display dialogue or narrative text."""
    # Indent continuation lines for multiline text
    formatted = text.replace("\n", "\n   ")

    if character is not None:
        # Dialogue — resolve display name
        name = interp.get_character_field(character, "name")
        display_name = name if name else character
        print(f" {display_name}: {formatted}")
    else:
        # Narrative text
        print(f" {formatted}")

    advance()


def handle_choice(interp: Interpreter, options: list, select):
    """Prompt the user to pick a choice."""
    print()
    enabled_indices = []
    for i, opt in enumerate(options):
        if opt.enabled:
            enabled_indices.append(i)
            print(f"  [{len(enabled_indices)}] {opt.text}")
        else:
            print(f"  [-] {opt.text} (unavailable)")

    while True:
        try:
            raw = input("\n> ").strip()
            choice = int(raw)
            if 1 <= choice <= len(enabled_indices):
                select(enabled_indices[choice - 1])
                return
        except (ValueError, EOFError):
            pass
        print("  Please enter a valid choice number.")


def handle_finish(interp: Interpreter):
    """Called when the story ends."""
    print("\n--- End of story ---")


def main():
    story_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "story")
    story_path = os.path.join(story_dir, "CoffeeShop.lor")

    source = read_file(story_path)
    if not source:
        print(f"Error: could not read {story_path}", file=sys.stderr)
        sys.exit(1)

    script = Loreline.parse(source, story_path, handle_file)
    if script is None:
        print("Error: failed to parse script", file=sys.stderr)
        sys.exit(1)

    print("=== CoffeeShop ===\n")
    Loreline.play(script, handle_dialogue, handle_choice, handle_finish)


if __name__ == "__main__":
    main()
