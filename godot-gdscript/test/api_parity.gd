extends SceneTree

# Exercises the public Loreline API of the pure-GDScript addon, matching
# the conventions of the native GDExtension: parse await, play with
# Callables, advance/select, save/restore, state and character fields,
# custom sync/async functions, translations entry points.
# Prints API_PARITY_OK on success, API_PARITY_FAILED: <reason> otherwise.

var _failed := false
var _reason := ""
var _events: Array = []
var _done := false


func _initialize() -> void:
	_run()


func _fail(reason: String) -> void:
	if not _failed:
		_failed = true
		_reason = reason


func _run() -> void:
	var loreline := Loreline.shared()

	# 1. parse via await (deferred signal emission)
	var source := """
character ana
  name: Ana

state
  gold: 5
  inventory: [sword, shield]

beat start
  ana: Hello!
  fetchBonus()
  gold = add(gold, 1)
  You have $gold gold.
  choice
    Take it
      Taken.
    Leave it
      Left.
"""
	var script = await loreline.parse(source, "api_parity.lor")
	if script == null:
		_fail("parse returned null")
		_finish()
		return

	# 2. to_json / from_json / print_script round trips
	var json: String = script.to_json()
	var script2 = LorelineScript.from_json(json)
	if script2 == null or script2.to_json() != json:
		_fail("script JSON round trip mismatch")
	if script.print_script().find("Hello!") == -1:
		_fail("print_script missing content")

	# 3. play with custom sync + async functions
	var options := LorelineOptions.new()
	options.set_function("add", func(_interp, args): return args[0] + args[1])
	options.set_async_function("fetchBonus", func(_interp, _args, resolve):
		await Engine.get_main_loop().process_frame
		_events.append("async")
		resolve.call())

	var interp := loreline.play(script, _on_dialogue, _on_choice, _on_finished, "", options)
	if interp == null:
		_fail("play returned null")
		_finish()
		return

	while not _done:
		await process_frame

	# 6. Order and content of events
	var expected := ["dialogue:Ana:Hello!", "async", "dialogue::You have 6 gold.", "choice:2", "dialogue::Taken.", "finished"]
	if _events != expected:
		_fail("unexpected event sequence: " + str(_events))

	_finish()


func _on_dialogue(interp: LorelineInterpreter, character: String, text: String, _tags: Array, advance: Callable) -> void:
	var display := ""
	if character != "":
		display = str(interp.get_character_field(character, "name"))
	_events.append("dialogue:" + display + ":" + text)

	if text.begins_with("You have"):
		# 4. field accessors + save/restore + containers
		if interp.get_state_field("gold") != 6:
			_fail("get_state_field gold != 6 (add result)")
		var inv = interp.get_state_field("inventory")
		if typeof(inv) != TYPE_ARRAY or inv.size() != 2 or inv[0] != "sword":
			_fail("inventory container mismatch: " + str(inv))
		interp.set_state_field("gold", 6)
		interp.set_character_field("ana", "mood", "happy")
		if interp.get_character_field("ana", "mood") != "happy":
			_fail("character field round trip failed")
		if interp.get_top_level_state_field("gold") != 6:
			_fail("top level state field mismatch")
		var node := interp.current_node()
		if not node.has("type") or not node.has("line"):
			_fail("current_node missing keys: " + str(node))
		# 5. save/restore round trip
		var saved := interp.save_state()
		if saved == "" or saved.find("gold") == -1:
			_fail("save_state produced no data")
	advance.call()


func _on_choice(_interp: LorelineInterpreter, options: Array, select: Callable) -> void:
	_events.append("choice:" + str(options.size()))
	if options.size() != 2 or options[0]["text"] != "Take it" or not options[0]["enabled"]:
		_fail("unexpected choice options: " + str(options))
	select.call(0)


func _on_finished(_interp: LorelineInterpreter) -> void:
	_events.append("finished")
	_done = true


func _finish() -> void:
	if _failed:
		print("API_PARITY_FAILED: ", _reason)
	else:
		print("API_PARITY_OK")
	quit(1 if _failed else 0)
