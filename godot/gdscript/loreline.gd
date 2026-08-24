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

## Interpreters retained while playback is running toward the next host
## callback. Mirrors the native runtime's inflight retainer: an interpreter
## stays alive exactly as long as the host holds a reference to it, or a
## callback is still owed to the host. Once neither is true it is collected,
## so an abandoned run frees itself without stop() or a finish.
##
## Armed whenever the host hands control back (play/resume/start/advance/
## select, and resolving an async function), released at the start of the
## matching callback delivery. Dictionary rather than Array so arming is
## idempotent and O(1); the keys are what holds the strong references.
var _inflight: Dictionary = {}


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
	if _report_error("update"):
		# A run aborted somewhere in the pump. Nothing is owed to the host any
		# more, so stop retaining whatever was mid-flight.
		_release_all_inflight()
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
			# Deferred starts run the story synchronously and report their own
			# errors; this only catches anything they left behind, so the flag
			# never survives the frame it was raised in.
			_report_error("deferred action")


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
	# Pass a callback: that is the runtime's non-throwing contract (errors
	# arrive as a null script instead of an exception), and it is also what
	# makes an asynchronous file_handler work, since the result is only known
	# once the imports have resolved.
	var answered := [false]
	_Loreline_Loreline.parse(
		actual_source,
		actual_path if actual_path != "" else null,
		handle,
		func(script_core):
			answered[0] = true
			_queue_emit(result, LorelineScript.new(script_core) if script_core != null else null)
	)
	# Safety net for an unexpected throw: consume it so it cannot poison every
	# later call, and answer the caller rather than leaving them awaiting.
	if _report_error("parse") and not answered[0]:
		_queue_emit(result, null)
	return result.completed


## Loads translations for a locale (e.g. "fr") relative to the script.
## Returns a Signal resolving to a LorelineTranslations (or null).
func load_locale(locale: String, script: LorelineScript, file_path: String = "", file_handler: Callable = Callable()) -> Signal:
	var result := LorelineLoadLocaleResult.new()
	var handle = _make_file_handler(file_handler)
	var answered := [false]
	_Loreline_Loreline.loadLocale(
		locale,
		script._script if script != null else null,
		file_path if file_path != "" else null,
		handle,
		func(translations):
			answered[0] = true
			_queue_emit(result, LorelineTranslations.new(translations) if translations != null else null)
	)
	if _report_error("load_locale") and not answered[0]:
		_queue_emit(result, null)
	return result.completed


## Enables or disables a runtime translation file format
## ("po", "xliff", "csv").
func translation_format(name: String, enabled: bool) -> void:
	_Loreline_Loreline.translationFormat(name, enabled)
	_report_error("translation_format")


## Runs a script, connecting the provided Callables to the interpreter's
## dialogue/choice/finished signals.
func play(script: LorelineScript, on_dialogue: Callable = Callable(), on_choice: Callable = Callable(), on_finished: Callable = Callable(), beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	var interp: LorelineInterpreter = LorelineInterpreter._play(script._script, beat_name, options)
	_report_error("play")
	_wire(interp, on_dialogue, on_choice, on_finished)
	return interp


## Resumes a script from save data, connecting the provided Callables.
func resume(script: LorelineScript, on_dialogue: Callable, on_choice: Callable, on_finished: Callable, save_data: String = "", beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	var interp: LorelineInterpreter = LorelineInterpreter._resume(script._script, save_data, beat_name, options)
	_report_error("resume")
	_wire(interp, on_dialogue, on_choice, on_finished)
	return interp


func _wire(interp: LorelineInterpreter, on_dialogue: Callable, on_choice: Callable, on_finished: Callable) -> void:
	if on_dialogue.is_valid():
		interp.dialogue.connect(on_dialogue)
	if on_choice.is_valid():
		interp.choice.connect(on_choice)
	if on_finished.is_valid():
		interp.finished.connect(on_finished)


## Consumes a pending exception left by the compiled runtime, returning its
## value or null when there was none.
##
## The GDScript runtime lowers Haxe `throw` to a global pending flag instead of
## unwinding: compiled code sets it and returns a default value, and every
## later call checks the flag and short-circuits. Nothing in the runtime clears
## it once it escapes to a caller, so this addon has to consume it at each of
## its entry points. Missing one leaves the flag set and every subsequent call
## into Loreline silently does nothing (a failed parse used to kill every parse
## after it for the lifetime of the process).
static func _take_error():
	return _Loreline_HxExc.take()


## True when the runtime left an exception pending, without consuming it. Lets a
## caller notice that the call it just made aborted, and leave the reporting to
## whichever boundary owns it.
static func _pending() -> bool:
	return _Loreline_HxExc.pending()


## Consumes a pending exception and reports it as an error, returning true when
## one was pending (so callers can bail out).
static func _report_error(what: String) -> bool:
	var err = _take_error()
	if err == null:
		return false
	# Loreline errors carry a message and a source position; str() on the object
	# would only print an instance id, which tells a user nothing.
	var text := ""
	if err is Object and err.has_method("toString"):
		text = str(err.toString())
		# toString() can itself throw; that must not re-arm the flag we just
		# cleared, nor hide the original error.
		if _Loreline_HxExc.take() != null or text == "":
			text = "<no message>"
	else:
		text = str(err)
	push_error("Loreline: " + what + " failed: " + text)
	return true


## Resolves a core interpreter back to its public wrapper. The core stores a
## WeakRef (see LorelineInterpreter._play), so this returns null once the
## wrapper has been collected.
static func _wrapper_of(core_interp):
	if core_interp == null or core_interp.wrapper == null:
		return null
	return core_interp.wrapper.get_ref()


## Retains `interp` until the next callback delivery. Only ever called from a
## point where the caller still holds a live reference, so the handover
## overlaps and can never resurrect a collected interpreter. No-op if already
## armed: one armed retainer already covers the run up to the next delivery.
func _retain_inflight(interp) -> void:
	if interp != null and not _inflight.has(interp):
		_inflight[interp] = true


## Drops every armed retainer. Used when an error escapes the runtime pump,
## where there is no way to tell which run aborted: a story error inside a
## wait() continuation surfaces from update() with nothing identifying it. This
## is safe because a healthy run is only ever armed across a frame boundary
## while waiting for its deferred start or for an async resolve, and both of
## those paths report and release their own interpreter themselves.
func _release_all_inflight() -> void:
	_inflight.clear()


## Releases the retainer taken by _retain_inflight. Called at the start of each
## callback delivery, before the handler runs, so a handler that re-enters
## synchronously (advancing from inside the callback) arms a fresh window.
func _release_inflight(interp) -> void:
	if interp != null:
		_inflight.erase(interp)


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
