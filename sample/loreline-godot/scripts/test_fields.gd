extends Node

# Container field smoke test: exercises Array and Dictionary values through
# get/set_state_field and get/set_character_field, plus custom function
# arguments and return values. Prints TEST PASSED on success, or
# TEST FAILED: <reason> on the first failing check.

var loreline: Loreline = Loreline.shared()

var _dialogue_count: int = 0
var _report_arg = null
var _failed: bool = false
var _fail_reason: String = ""


func _ready() -> void:
	var options := LorelineOptions.new()
	options.set_function("getConfig", _get_config)
	options.set_function("sendReport", _send_report)
	options.set_async_function("fetchBonus", _fetch_bonus)

	var script = await loreline.parse("res://story/TestFields.lor")
	if script == null:
		_fail("Failed to parse TestFields.lor")
		_finish_run()
		return

	loreline.play(script, _on_dialogue, _on_choice, _on_finished, "", options)


func _fail(reason: String) -> void:
	if not _failed:
		_failed = true
		_fail_reason = reason


func _get_config(_interp: LorelineInterpreter, _args: Array):
	return {"volume": 5, "tags": ["a", "b"]}


func _send_report(_interp: LorelineInterpreter, args: Array):
	if args.size() > 0:
		_report_arg = args[0]
	return null


func _fetch_bonus(interp: LorelineInterpreter, args: Array, resolve: Callable) -> void:
	await get_tree().process_frame
	# Container arguments must survive the async custom function path
	if args.size() != 2 or typeof(args[0]) != TYPE_ARRAY or args[0].size() != 2 or args[0][0] != "sword":
		_fail("async function array argument did not arrive, got: " + str(args))
	elif typeof(args[1]) != TYPE_DICTIONARY or args[1].get("name") != "Ana" or int(args[1].get("level")) != 3:
		_fail("async function dictionary argument did not arrive, got: " + str(args))
	else:
		interp.set_state_field("bonus", {"granted": ["cape"], "count": 1})
	resolve.call()


func _check_initial_state(interp: LorelineInterpreter) -> void:
	# Script-declared array
	var inventory = interp.get_state_field("inventory")
	if typeof(inventory) != TYPE_ARRAY or inventory.size() != 2 or inventory[0] != "sword" or inventory[1] != "shield":
		_fail("inventory did not read as expected array, got: " + str(inventory))
		return

	# Script-declared object
	var profile = interp.get_state_field("profile")
	if typeof(profile) != TYPE_DICTIONARY or profile.get("name") != "Ana" or int(profile.get("level")) != 3:
		_fail("profile did not read as expected dictionary, got: " + str(profile))
		return

	# Host-built nested container round-trip
	var payload := {"items": ["potion", 42], "active": true}
	interp.set_state_field("payload", payload)
	var back = interp.get_state_field("payload")
	if typeof(back) != TYPE_DICTIONARY or typeof(back.get("items")) != TYPE_ARRAY or back["items"].size() != 2 or back["items"][0] != "potion" or int(back["items"][1]) != 42 or back.get("active") != true:
		_fail("payload did not round-trip, got: " + str(back))
		return

	# Deep-copy snapshot semantics: mutating a returned copy must not leak
	back["active"] = false
	back["items"].append("extra")
	var fresh = interp.get_state_field("payload")
	if fresh.get("active") != true or fresh["items"].size() != 2:
		_fail("mutating a returned copy leaked into interpreter state, got: " + str(fresh))
		return

	# Character field containers
	interp.set_character_field("ana", "traits", ["bold", "curious"])
	var traits = interp.get_character_field("ana", "traits")
	if typeof(traits) != TYPE_ARRAY or traits.size() != 2 or traits[0] != "bold" or traits[1] != "curious":
		_fail("character traits did not round-trip, got: " + str(traits))
		return

	# Beat references cross as marker dictionaries (the save data shape),
	# recognizable and accepted back by the runtime
	var beat_ref = interp.get_state_field("beatRef")
	if typeof(beat_ref) != TYPE_DICTIONARY or beat_ref.get("type") != "$beatRef":
		_fail("beat reference did not read as a marker dictionary, got: " + str(beat_ref))
		return
	# Hand the marker back: the runtime must restore a live reference
	interp.set_state_field("beatRefBack", beat_ref)
	var beat_back = interp.get_state_field("beatRefBack")
	if typeof(beat_back) != TYPE_DICTIONARY or beat_back.get("type") != "$beatRef":
		_fail("beat reference marker did not round-trip, got: " + str(beat_back))
		return


func _check_function_results(interp: LorelineInterpreter) -> void:
	# Dictionary returned by a custom function, stored in script state
	var config = interp.get_state_field("config")
	if typeof(config) != TYPE_DICTIONARY or int(config.get("volume")) != 5:
		_fail("custom function dictionary return did not round-trip, got: " + str(config))
		return
	var tags = config.get("tags")
	if typeof(tags) != TYPE_ARRAY or tags.size() != 2 or tags[0] != "a" or tags[1] != "b":
		_fail("nested array in custom function return did not round-trip, got: " + str(tags))
		return

	# Dictionary passed as a custom function argument
	if typeof(_report_arg) != TYPE_DICTIONARY or _report_arg.get("name") != "Ana" or int(_report_arg.get("level")) != 3:
		_fail("custom function dictionary argument did not arrive, got: " + str(_report_arg))
		return


func _check_async_results(interp: LorelineInterpreter) -> void:
	# Container written from inside the async function while the script was paused
	var bonus = interp.get_state_field("bonus")
	if typeof(bonus) != TYPE_DICTIONARY or int(bonus.get("count")) != 1 or typeof(bonus.get("granted")) != TYPE_ARRAY or bonus["granted"].size() != 1 or bonus["granted"][0] != "cape":
		_fail("bonus set during async function did not round-trip, got: " + str(bonus))
		return


func _on_dialogue(interp: LorelineInterpreter, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	_dialogue_count += 1
	print("DIALOGUE ", _dialogue_count, ": ", text)
	if _dialogue_count == 1:
		_check_initial_state(interp)
	elif _dialogue_count == 2:
		_check_function_results(interp)
	elif _dialogue_count == 3:
		_check_async_results(interp)
	advance.call()


func _on_choice(_interp, _options: Array, _select: Callable) -> void:
	pass


func _on_finished(_interp) -> void:
	_finish_run()


func _finish_run() -> void:
	if _failed:
		print("TEST FAILED: ", _fail_reason)
	else:
		print("TEST PASSED")
	# Auto-quit headless/exported runs. Editor runs keep the window open.
	if not OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		get_tree().call_deferred("quit", 1 if _failed else 0)
