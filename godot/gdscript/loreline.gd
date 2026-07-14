class_name Loreline
extends Node

## Public entry point of the pure-GDScript Loreline runtime. Mirrors the
## native GDExtension API exactly, so projects can switch between the two
## backends without code changes (only one addon may be installed at a
## time, since both register the same class names).

static var _singleton: Loreline = null

## Deferred completion emits: parse()/load_locale() results are emitted on
## the next process frame so `await` has connected before the signal fires.
var _pending_emits: Array = []

## Interpreters kept alive while running (released when finished).
var _active_interpreters: Array = []


static func shared() -> Loreline:
	if _singleton != null:
		return _singleton
	_singleton = Loreline.new()
	_singleton.set_name("Loreline")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.get_root() != null:
		tree.get_root().add_child(_singleton)
	_singleton.set_process(true)
	return _singleton


## Deferred actions (interpreter starts/resumes) run one frame later so
## signal connections made right after play()/resume() are in place.
var _pending_actions: Array = []


func _process(delta: float) -> void:
	# Pump the runtime (timers used by wait() and similar built-ins).
	_Loreline_Loreline.update(delta)
	if _pending_emits.size() > 0:
		var emits: Array = _pending_emits
		_pending_emits = []
		for e in emits:
			e["result"].completed.emit(e["value"])
	if _pending_actions.size() > 0:
		var actions: Array = _pending_actions
		_pending_actions = []
		for action in actions:
			action.call()


func _queue_action(action: Callable) -> void:
	_pending_actions.append(action)


## Parses Loreline source (or a res:// / user:// path) into a script.
## Returns a Signal: `var script = await loreline.parse(...)`.
## file_handler, if provided, is called as (path, provide) and must call
## provide.call(content_or_null).
func parse(source: String, file_path: String = "", file_handler: Callable = Callable()) -> Signal:
	var result := LorelineParseResult.new()

	var actual_source := source
	var actual_path := file_path
	if actual_path == "" and (source.begins_with("res://") or source.begins_with("user://")):
		actual_path = source
		actual_source = FileAccess.get_file_as_string(source)

	var handle = _make_file_handler(file_handler)
	var script_core = _Loreline_Loreline.parse(
		actual_source,
		actual_path if actual_path != "" else null,
		handle,
		null
	)
	var wrapped = LorelineScript.new(script_core) if script_core != null else null
	_queue_emit(result, wrapped)
	return result.completed


## Loads translations for a locale (e.g. "fr") relative to the script.
## Returns a Signal resolving to a LorelineTranslations (or null).
func load_locale(locale: String, script: LorelineScript, file_path: String = "", file_handler: Callable = Callable()) -> Signal:
	var result := LorelineLoadLocaleResult.new()
	var handle = _make_file_handler(file_handler)
	var translations = _Loreline_Loreline.loadLocale(
		locale,
		script._script if script != null else null,
		file_path if file_path != "" else null,
		handle,
		null
	)
	var wrapped = LorelineTranslations.new(translations) if translations != null else null
	_queue_emit(result, wrapped)
	return result.completed


## Enables or disables a runtime translation file format
## ("po", "xliff", "csv").
func translation_format(name: String, enabled: bool) -> void:
	_Loreline_Loreline.translationFormat(name, enabled)


## Runs a script, connecting the provided Callables to the interpreter's
## dialogue/choice/finished signals.
func play(script: LorelineScript, on_dialogue: Callable = Callable(), on_choice: Callable = Callable(), on_finished: Callable = Callable(), beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	var interp: LorelineInterpreter = LorelineInterpreter._play(script._script, beat_name, options)
	_wire(interp, on_dialogue, on_choice, on_finished)
	return interp


## Resumes a script from save data, connecting the provided Callables.
func resume(script: LorelineScript, on_dialogue: Callable, on_choice: Callable, on_finished: Callable, save_data: String = "", beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	var interp: LorelineInterpreter = LorelineInterpreter._resume(script._script, save_data, beat_name, options)
	_wire(interp, on_dialogue, on_choice, on_finished)
	return interp


func _wire(interp: LorelineInterpreter, on_dialogue: Callable, on_choice: Callable, on_finished: Callable) -> void:
	if on_dialogue.is_valid():
		interp.dialogue.connect(on_dialogue)
	if on_choice.is_valid():
		interp.choice.connect(on_choice)
	if on_finished.is_valid():
		interp.finished.connect(on_finished)
	_active_interpreters.append(interp)


func _release_active(interp: LorelineInterpreter) -> void:
	_active_interpreters.erase(interp)


func _queue_emit(result, value) -> void:
	_pending_emits.append({ "result": result, "value": value })


func _make_file_handler(file_handler: Callable):
	if file_handler.is_valid():
		return func(path: String, cb):
			# `cb` accepts the file content or null; it doubles as the
			# `provide` Callable of the public file handler contract.
			file_handler.call(path, cb)
	return func(path: String, cb):
		if FileAccess.file_exists(path):
			cb.call(FileAccess.get_file_as_string(path))
		else:
			cb.call(null)
