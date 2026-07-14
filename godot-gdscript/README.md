# Loreline for Godot (pure GDScript)

This is the pure-GDScript distribution of the Loreline runtime: the whole
Haxe runtime is compiled to GDScript with [Reflaxe](https://github.com/SomeRanDev/reflaxe)
and a [fork of Reflaxe/GDScript](https://github.com/jeremyfa/reflaxe.GDScript),
then wrapped by a thin hand-written addon that exposes the exact same public
API as the native Loreline GDExtension.

Because it is plain GDScript, it runs on every Godot export target,
including platforms where no native Loreline binaries are available
(consoles among others). The native GDExtension remains the recommended
option where its binaries exist, as it is faster.

## Which one should I use?

- Desktop, mobile, web: the native GDExtension (`addons/loreline`).
- Everything else, or if you prefer zero native dependencies: this addon
  (`addons/loreline_gd`).

Both register the same class names (`Loreline`, `LorelineScript`,
`LorelineInterpreter`, `LorelineOptions`, `LorelineTranslations`), so a
project installs ONE of the two, never both, and game code is identical:

```gdscript
var loreline: Loreline = Loreline.shared()

func _ready() -> void:
    var script = await loreline.parse("res://story/MyStory.lor")
    loreline.play(script, _on_dialogue, _on_choice, _on_finished)

func _on_dialogue(interp: LorelineInterpreter, character: String, text: String, tags: Array, advance: Callable) -> void:
    print(character, ": ", text)
    advance.call()

func _on_choice(interp: LorelineInterpreter, options: Array, select: Callable) -> void:
    select.call(0)

func _on_finished(interp: LorelineInterpreter) -> void:
    print("Finished")
```

## Layout

- `addons/loreline_gd/` - the addon: hand-written API wrappers plus the
  generated runtime in `addons/loreline_gd/core/` (built by
  `node ./setup --gdscript` from the repository root).
- `test/` - headless test project: `run_tests.gd` executes the full `.lor`
  test suite through the compiled runtime, `api_parity.gd` exercises the
  public API surface. Run both with `node ./setup --gdscript-test`
  (set `GODOT_BIN` if Godot is not on your PATH).

## Building from source

```
git submodule update --init git/reflaxe git/reflaxe.GDScript
node ./setup --gdscript        # compiles the runtime to GDScript
node ./setup --gdscript-test   # runs the full test suite headlessly
```
