"""Loreline - interactive fiction scripting language."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, List, Optional

from . import _core


# ── Types ────────────────────────────────────────────────────────────────

@dataclass
class TextTag:
    """A tag embedded in text content, used for styling or other purposes."""

    value: str
    """The value or name of the tag."""

    offset: int
    """The offset in the text where this tag appears."""

    closing: bool
    """Whether this is a closing tag."""


@dataclass
class ChoiceOption:
    """A choice option presented to the user."""

    text: str
    """The text of the choice option."""

    tags: List[TextTag]
    """Any tags associated with the choice text."""

    enabled: bool
    """Whether this choice option is currently enabled."""


# ── Type aliases for callbacks ───────────────────────────────────────────

DialogueHandler = Callable[["Interpreter", Optional[str], str, List[TextTag], Callable[[], None]], None]
"""Called when dialogue text should be displayed.

Args:
    interpreter: The interpreter instance.
    character: The character speaking (None for narrator text).
    text: The text content to display.
    tags: Any tags in the text.
    advance: Function to call when the text has been displayed.
"""

ChoiceHandler = Callable[["Interpreter", List[ChoiceOption], Callable[[int], None]], None]
"""Called when the player needs to make a choice.

Args:
    interpreter: The interpreter instance.
    options: The available choice options.
    select: Function to call with the index of the selected choice.
"""

FinishHandler = Callable[["Interpreter"], None]
"""Called when script execution completes.

Args:
    interpreter: The interpreter instance.
"""

ImportsFileHandler = Callable[[str, Callable[[str], None]], None]
"""Called to load an imported file.

Args:
    path: The path of the file to load.
    callback: Function to call with the loaded file content.
"""


# ── Internal helpers ─────────────────────────────────────────────────────

def _wrap_tag(tag: _core.loreline_TextTag) -> TextTag:
    """Convert an internal TextTag to the public type."""
    return TextTag(value=tag.value, offset=tag.offset, closing=tag.closing)


def _wrap_tags(tags: list) -> List[TextTag]:
    """Convert a list of internal TextTags to public types."""
    if tags is None:
        return []
    return [_wrap_tag(t) for t in tags]


def _wrap_option(opt: _core.loreline_ChoiceOption) -> ChoiceOption:
    """Convert an internal ChoiceOption to the public type."""
    return ChoiceOption(
        text=opt.text,
        tags=_wrap_tags(opt.tags),
        enabled=opt.enabled,
    )


def _make_dialogue_bridge(handle_dialogue: DialogueHandler) -> Callable:
    """Wrap a public DialogueHandler to bridge internal types."""
    def bridge(interp, character, text, tags, advance):
        wrapper = Interpreter(interp)
        handle_dialogue(wrapper, character, text, _wrap_tags(tags), advance)
    return bridge


def _make_choice_bridge(handle_choice: ChoiceHandler) -> Callable:
    """Wrap a public ChoiceHandler to bridge internal types."""
    def bridge(interp, options, select):
        wrapper = Interpreter(interp)
        wrapped_options = [_wrap_option(o) for o in options]
        handle_choice(wrapper, wrapped_options, select)
    return bridge


def _make_finish_bridge(handle_finish: FinishHandler) -> Callable:
    """Wrap a public FinishHandler to bridge internal types."""
    def bridge(interp):
        wrapper = Interpreter(interp)
        handle_finish(wrapper)
    return bridge


# ── Script ───────────────────────────────────────────────────────────────

class Script:
    """A parsed Loreline script AST.

    Obtain via ``Loreline.parse()``. Pass to ``Loreline.play()`` or
    ``Loreline.resume()`` to execute.
    """

    def __init__(self, _internal: Any) -> None:
        self._internal = _internal


# ── Interpreter ──────────────────────────────────────────────────────────

class Interpreter:
    """A running Loreline script interpreter.

    Provides methods to save/restore state and access character data.
    """

    def __init__(self, _internal: Any) -> None:
        self._internal = _internal

    def save(self) -> Any:
        """Save the current interpreter state.

        Returns an opaque save-data object that can be passed to
        ``Loreline.resume()`` or ``Interpreter.restore()`` later.
        """
        return self._internal.save()

    def restore(self, save_data: Any) -> None:
        """Restore the interpreter to a previously saved state.

        Args:
            save_data: The opaque save-data object from ``save()``.
        """
        self._internal.restore(save_data)

    def resume(self) -> None:
        """Resume execution after restoring state."""
        self._internal.resume()

    def start(self, beat_name: Optional[str] = None) -> None:
        """Start or restart execution from a specific beat.

        Args:
            beat_name: Name of the beat to start from. If None, starts
                       from the first beat.
        """
        self._internal.start(beat_name)

    def get_character(self, name: str) -> Any:
        """Get a character's fields by name.

        Args:
            name: The character identifier.

        Returns:
            The character's fields object, or None if not found.
        """
        return self._internal.getCharacter(name)

    def get_character_field(self, character: str, field: str) -> Any:
        """Get a specific field of a character.

        Args:
            character: The character identifier.
            field: The field name to retrieve.

        Returns:
            The field value, or None if not found.
        """
        return self._internal.getCharacterField(character, field)

    def set_character_field(self, character: str, field: str, value: Any) -> None:
        """Set a specific field of a character.

        Args:
            character: The character identifier.
            field: The field name to set.
            value: The value to assign.
        """
        self._internal.setCharacterField(character, field, value)


# ── Loreline (main API) ─────────────────────────────────────────────────

class Loreline:
    """Main public API for the Loreline interactive fiction runtime.

    All methods are static. Typical usage::

        script = Loreline.parse(source)
        interp = Loreline.play(script, on_dialogue, on_choice, on_finish)
    """

    @staticmethod
    def parse(
        source: str,
        file_path: Optional[str] = None,
        handle_file: Optional[ImportsFileHandler] = None,
        callback: Optional[Callable[[Script], None]] = None,
    ) -> Optional[Script]:
        """Parse a Loreline script string into a Script AST.

        Args:
            source: The ``.lor`` script content.
            file_path: Optional file path for resolving imports.
                       Requires ``handle_file`` to also be provided.
            handle_file: Optional handler to load imported files.
            callback: Optional callback receiving the parsed Script.
                      Useful when ``handle_file`` resolves asynchronously.

        Returns:
            The parsed Script, or None if loaded asynchronously.

        Raises:
            Exception: If the script contains syntax errors.
        """
        wrapped_callback = None
        if callback is not None:
            def wrapped_callback(internal_script):
                callback(Script(internal_script))

        result = _core.loreline_Loreline.parse(
            source, file_path, handle_file, wrapped_callback,
        )
        if result is not None:
            return Script(result)
        return None

    @staticmethod
    def play(
        script: Script,
        handle_dialogue: DialogueHandler,
        handle_choice: ChoiceHandler,
        handle_finish: FinishHandler,
        beat_name: Optional[str] = None,
        functions: Optional[dict] = None,
        strict_access: bool = False,
        translations: Any = None,
    ) -> Interpreter:
        """Start playing a parsed script.

        Args:
            script: A parsed Script from ``parse()``.
            handle_dialogue: Called when dialogue text should be displayed.
            handle_choice: Called when the player must make a choice.
            handle_finish: Called when script execution completes.
            beat_name: Optional beat to start from (default: first beat).
            functions: Optional dict of ``{name: callable}`` custom functions.
            strict_access: If True, accessing undefined variables raises an error.
            translations: Optional translations map from ``extract_translations()``.

        Returns:
            The running Interpreter instance.
        """
        options = _core._hx_AnonObject({
            "functions": functions,
            "strictAccess": strict_access,
            "translations": translations,
        })

        internal = _core.loreline_Loreline.play(
            script._internal,
            _make_dialogue_bridge(handle_dialogue),
            _make_choice_bridge(handle_choice),
            _make_finish_bridge(handle_finish),
            beat_name,
            options,
        )
        return Interpreter(internal)

    @staticmethod
    def resume(
        script: Script,
        handle_dialogue: DialogueHandler,
        handle_choice: ChoiceHandler,
        handle_finish: FinishHandler,
        save_data: Any,
        beat_name: Optional[str] = None,
        functions: Optional[dict] = None,
        strict_access: bool = False,
        translations: Any = None,
    ) -> Interpreter:
        """Resume a script from saved state.

        Args:
            script: A parsed Script from ``parse()``.
            handle_dialogue: Called when dialogue text should be displayed.
            handle_choice: Called when the player must make a choice.
            handle_finish: Called when script execution completes.
            save_data: The opaque save-data object from ``Interpreter.save()``.
            beat_name: Optional beat name to override resume point.
            functions: Optional dict of custom functions.
            strict_access: If True, accessing undefined variables raises an error.
            translations: Optional translations map from ``extract_translations()``.

        Returns:
            The running Interpreter instance.
        """
        options = _core._hx_AnonObject({
            "functions": functions,
            "strictAccess": strict_access,
            "translations": translations,
        })

        internal = _core.loreline_Loreline.resume(
            script._internal,
            _make_dialogue_bridge(handle_dialogue),
            _make_choice_bridge(handle_choice),
            _make_finish_bridge(handle_finish),
            save_data,
            beat_name,
            options,
        )
        return Interpreter(internal)

    @staticmethod
    def extract_translations(script: Script) -> Any:
        """Extract translations from a parsed translation script.

        Args:
            script: A parsed translation script (``.XX.lor`` file).

        Returns:
            A translations object to pass as the ``translations`` argument
            to ``play()`` or ``resume()``.
        """
        return _core.loreline_Loreline.extractTranslations(script._internal)

    @staticmethod
    def print(script: Script, indent: str = "  ", newline: str = "\n") -> str:
        """Print a parsed script back into Loreline source code.

        Args:
            script: A parsed Script from ``parse()``.
            indent: The indentation string (default: two spaces).
            newline: The newline string (default: ``"\\n"``).

        Returns:
            The printed source code.
        """
        return _core.loreline_Loreline.print(script._internal, indent, newline)
