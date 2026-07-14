class_name LorelineInterpreter
extends RefCounted

## Wraps a running Loreline interpreter (pure-GDScript runtime). Mirrors
## the native GDExtension API: same signals, methods and Callable
## conventions, so the two backends are interchangeable.

signal dialogue(interpreter, character: String, text: String, tags: Array, advance: Callable)
signal choice(interpreter, options: Array, select: Callable)
signal finished(interpreter)

var _interp = null
var _pending_advance: Callable = Callable()
var _pending_select: Callable = Callable()


## Internal: creates a run and returns the wrapper. Execution starts on
## the next process frame, so callers can connect to the signals first
## (matching the native extension's deferred callback mode).
static func _play(script_core, beat_name: String, options: LorelineOptions):
	var wrapper := LorelineInterpreter.new()
	var core_options = options._build_core_options() if options != null else null
	wrapper._interp = _Loreline_Interpreter.new(
		script_core,
		wrapper._on_core_dialogue,
		wrapper._on_core_choice,
		wrapper._on_core_finished,
		core_options
	)
	wrapper._interp.wrapper = wrapper
	var start_beat = beat_name if beat_name != "" else null
	Loreline.shared()._queue_action(func():
		wrapper._interp.start(start_beat))
	return wrapper


## Internal: creates a resumed run and returns the wrapper. Execution
## resumes on the next process frame (see _play).
static func _resume(script_core, save_data: String, beat_name: String, options: LorelineOptions):
	var wrapper := LorelineInterpreter.new()
	var core_options = options._build_core_options() if options != null else null
	var parsed_save = _Loreline_loreline_Json.parse(save_data) if save_data != "" else null
	wrapper._interp = _Loreline_Interpreter.new(
		script_core,
		wrapper._on_core_dialogue,
		wrapper._on_core_choice,
		wrapper._on_core_finished,
		core_options
	)
	wrapper._interp.wrapper = wrapper
	var start_beat = beat_name if beat_name != "" else null
	Loreline.shared()._queue_action(func():
		if parsed_save != null:
			wrapper._interp.restore(parsed_save)
		if start_beat != null:
			wrapper._interp.start(start_beat)
		else:
			wrapper._interp.resume())
	return wrapper


func _on_core_dialogue(_core, character, text, tags, advance) -> void:
	var me := self
	var advance_cb := func():
		# Capturing `me` keeps the interpreter alive across async pauses.
		if me._interp != null:
			advance.call()
	_pending_advance = advance_cb
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
	var me := self
	var select_cb := func(index = 0):
		if me._interp != null:
			select.call(int(index))
	_pending_select = select_cb
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
	finished.emit(self)
	if Loreline._singleton != null:
		Loreline._singleton._release_active(self)


## Advances past the current dialogue (same as calling the `advance`
## Callable received with the dialogue signal).
func advance() -> void:
	if _pending_advance.is_valid():
		var cb := _pending_advance
		_pending_advance = Callable()
		cb.call()


## Selects a choice option by index (same as calling the `select`
## Callable received with the choice signal).
func select(index: int) -> void:
	if _pending_select.is_valid():
		var cb := _pending_select
		_pending_select = Callable()
		cb.call(index)


## Starts (or restarts) execution from the given beat.
func start(beat_name: String = "") -> void:
	if _interp != null:
		_interp.start(beat_name if beat_name != "" else null)


## Returns the full interpreter state serialized as a JSON string.
func save_state() -> String:
	if _interp == null:
		return ""
	return _Loreline_loreline_Json.stringify(_interp.save(), false)


## Restores interpreter state from a save_state() JSON string.
func restore_state(data: String) -> void:
	if _interp != null and data != "":
		_interp.restore(_Loreline_loreline_Json.parse(data))


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
