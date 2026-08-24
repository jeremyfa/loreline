class_name LorelineInterpreter
extends RefCounted

## Wraps a running Loreline interpreter (pure-GDScript runtime). Mirrors
## the native GDExtension API: same signals, methods and Callable
## conventions, so the two backends are interchangeable.

signal dialogue(interpreter, character: String, text: String, tags: Array, advance: Callable)
signal choice(interpreter, options: Array, select: Callable)
signal finished(interpreter)

var _interp = null
## The core's own continuation for the pending dialogue/choice. Deliberately
## NOT the Callable handed to the host: that one captures `self` (which is how
## holding it keeps this interpreter alive), so storing it here would make this
## object reference itself and never be collected.
var _pending_advance: Callable = Callable()
var _pending_select: Callable = Callable()


## Builds the core-facing callbacks. They hold only a weak reference, so the
## core can outlive this wrapper (a pending wait() timer, say) without either
## keeping it alive or calling into a freed instance.
static func _core_callbacks(wrapper: LorelineInterpreter) -> Array:
	var weak := weakref(wrapper)
	return [
		func(core, character, text, tags, advance):
			var w = weak.get_ref()
			if w != null:
				w._on_core_dialogue(core, character, text, tags, advance),
		func(core, options, select):
			var w = weak.get_ref()
			if w != null:
				w._on_core_choice(core, options, select),
		func(core):
			var w = weak.get_ref()
			if w != null:
				w._on_core_finished(core),
	]


## Internal: creates a run and returns the wrapper. Execution starts on
## the next process frame, so callers can connect to the signals first
## (matching the native extension's deferred callback mode).
static func _play(script_core, beat_name: String, options: LorelineOptions):
	var wrapper := LorelineInterpreter.new()
	var core_options = options._build_core_options() if options != null else null
	var cbs := _core_callbacks(wrapper)
	wrapper._interp = _Loreline_Interpreter.new(
		script_core, cbs[0], cbs[1], cbs[2], core_options
	)
	# Weak on purpose: the core is owned by this wrapper, and a strong
	# back-reference would make the pair immortal. LorelineOptions reads it
	# back through Loreline._wrapper_of().
	wrapper._interp.wrapper = weakref(wrapper)
	var start_beat = beat_name if beat_name != "" else null
	# Playback is about to run toward its first callback: retain across that
	# window even if the host drops the value we return.
	Loreline.shared()._retain_inflight(wrapper)
	Loreline.shared()._queue_action(func():
		wrapper._interp.start(start_beat)
		wrapper._settle("play"))
	return wrapper


## Internal: creates a resumed run and returns the wrapper. Execution
## resumes on the next process frame (see _play).
static func _resume(script_core, save_data: String, beat_name: String, options: LorelineOptions):
	var wrapper := LorelineInterpreter.new()
	var core_options = options._build_core_options() if options != null else null
	var parsed_save = _Loreline_loreline_Json.parse(save_data) if save_data != "" else null
	var cbs := _core_callbacks(wrapper)
	wrapper._interp = _Loreline_Interpreter.new(
		script_core, cbs[0], cbs[1], cbs[2], core_options
	)
	wrapper._interp.wrapper = weakref(wrapper)
	var start_beat = beat_name if beat_name != "" else null
	Loreline.shared()._retain_inflight(wrapper)
	Loreline.shared()._queue_action(func():
		if parsed_save != null:
			wrapper._interp.restore(parsed_save)
		if start_beat != null:
			wrapper._interp.start(start_beat)
		else:
			wrapper._interp.resume()
		wrapper._settle("resume"))
	return wrapper


func _on_core_dialogue(_core, character, text, tags, advance) -> void:
	# Delivery reached the host: drop the inflight retainer. From here the run
	# is held by whatever the host keeps, `advance_cb` included.
	Loreline.shared()._release_inflight(self)
	var me := self
	# Capturing `me` is what makes holding this Callable keep the interpreter
	# alive, matching the native backend.
	var advance_cb := func():
		me._do_advance()
	_pending_advance = advance
	_pending_select = Callable()
	var godot_tags := []
	if tags != null:
		for tag in tags:
			godot_tags.append({
				"value": tag.value if tag.value != null else "",
				"offset": tag.offset,
				"closing": tag.closing
			})
	dialogue.emit(self, character if character != null else "", text if text != null else "", godot_tags, advance_cb)


func _on_core_choice(_core, options, select) -> void:
	Loreline.shared()._release_inflight(self)
	var me := self
	var select_cb := func(index = 0):
		me._do_select(int(index))
	_pending_select = select
	_pending_advance = Callable()
	var godot_options := []
	if options != null:
		for option in options:
			var tags := []
			if option.tags != null:
				for tag in option.tags:
					tags.append({
						"value": tag.value if tag.value != null else "",
						"offset": tag.offset,
						"closing": tag.closing
					})
			godot_options.append({
				"text": option.text if option.text != null else "",
				"enabled": option.enabled,
				"tags": tags
			})
	choice.emit(self, godot_options, select_cb)


func _on_core_finished(_core) -> void:
	# Final delivery: release the retainer so a run the host no longer
	# references is collected right after this callback.
	Loreline.shared()._release_inflight(self)
	_pending_advance = Callable()
	_pending_select = Callable()
	finished.emit(self)


## Called right after handing control back to the core. If the story aborted,
## report it here rather than a frame later, and drop this run's retainer: no
## delivery is coming, so nothing is owed and the run must not be kept alive.
func _settle(what: String) -> void:
	if Loreline._pending():
		Loreline._report_error(what)
		Loreline.shared()._release_inflight(self)


## Hands control back to the core for the pending dialogue. Retains across the
## gap first, while the caller demonstrably still holds this object, so the run
## survives even if that was the host's last reference.
func _do_advance() -> void:
	if _interp == null or not _pending_advance.is_valid():
		return
	var cb := _pending_advance
	_pending_advance = Callable()
	Loreline.shared()._retain_inflight(self)
	cb.call()
	_settle("advance")


func _do_select(index: int) -> void:
	if _interp == null or not _pending_select.is_valid():
		return
	var cb := _pending_select
	_pending_select = Callable()
	Loreline.shared()._retain_inflight(self)
	cb.call(index)
	_settle("select")


## Advances past the current dialogue (same as calling the `advance`
## Callable received with the dialogue signal).
func advance() -> void:
	_do_advance()


## Selects a choice option by index (same as calling the `select`
## Callable received with the choice signal).
func select(index: int) -> void:
	_do_select(index)


## Starts (or restarts) execution from the given beat.
func start(beat_name: String = "") -> void:
	if _interp != null:
		Loreline.shared()._retain_inflight(self)
		_interp.start(beat_name if beat_name != "" else null)
		_settle("start")


## Returns the full interpreter state serialized as a JSON string.
func save_state() -> String:
	if _interp == null:
		return ""
	return _Loreline_loreline_Json.stringify(_interp.save(), false)


## Restores interpreter state from a save_state() JSON string.
func restore_state(data: String) -> void:
	if _interp != null and data != "":
		_interp.restore(_Loreline_loreline_Json.parse(data))
		_settle("restore_state")


func get_character_field(character: String, field: String):
	return _interp.getCharacterField(character, field) if _interp != null else null


func set_character_field(character: String, field: String, value) -> void:
	if _interp != null:
		_interp.setCharacterField(character, field, value)


func get_state_field(field: String):
	return _interp.getStateField(field) if _interp != null else null


func set_state_field(field: String, value) -> void:
	if _interp != null:
		_interp.setStateField(field, value)


func get_top_level_state_field(field: String):
	return _interp.getTopLevelStateField(field) if _interp != null else null


func set_top_level_state_field(field: String, value) -> void:
	if _interp != null:
		_interp.setTopLevelStateField(field, value)


## Information about the node currently being evaluated.
func current_node() -> Dictionary:
	if _interp == null:
		return {}
	var node = _interp.currentNode()
	if node == null:
		return {}
	return {
		"type": node.type(),
		"line": node.pos.line,
		"column": node.pos.column,
		"offset": node.pos.offset,
		"length": node.pos.length
	}
