extends Node

# Sequential web-export smoke test. Replicates the logic of test_saverestore.gd
# and test_async.gd in one scene so both can be exercised through the WASM +
# JS-bridge code path during a single page load. Prints ALL_WEB_TESTS_PASSED
# on success, TEST FAILED: <reason> on failure, then quits.

var loreline: Loreline = Loreline.shared()


func _ready() -> void:
	var ok_saverestore := await _run_saverestore()
	if not ok_saverestore:
		_report(false, "saverestore phase failed")
		return

	var ok_async := await _run_async()
	if not ok_async:
		_report(false, "async phase failed")
		return

	var ok_fields := await _run_fields()
	if not ok_fields:
		_report(false, "fields phase failed: " + _fl_fail_reason)
		return

	_report(true, "")


func _report(passed: bool, detail: String) -> void:
	if passed:
		print("ALL_WEB_TESTS_PASSED")
	else:
		print("TEST FAILED: ", detail)
	# Auto-quit headless/exported runs. Editor runs keep the window open.
	if not OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		get_tree().call_deferred("quit", 0 if passed else 1)


# ---------------------------------------------------------------------------
# Save / restore phase
# ---------------------------------------------------------------------------

var _sr_script: LorelineScript
var _sr_saved: String = ""
var _sr_count: int = 0
var _sr_phase: String = "first_run"
var _sr_first_total: int = 0
var _sr_done: bool = false
var _sr_ok: bool = false


func _run_saverestore() -> bool:
	_sr_script = await loreline.parse("res://story/TestSaveRestore.lor")
	if _sr_script == null:
		printerr("Failed to parse TestSaveRestore.lor")
		return false

	loreline.play(_sr_script, _sr_dialogue, _sr_choice, _sr_finished)

	while not _sr_done:
		await get_tree().process_frame

	return _sr_ok


func _sr_dialogue(interp: LorelineInterpreter, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	_sr_count += 1
	print("[", _sr_phase, "] DIALOGUE ", _sr_count, ": ", text)

	if _sr_phase == "first_run" and _sr_count == 2:
		_sr_saved = interp.save_state()
		print("[", _sr_phase, "] captured save data (", _sr_saved.length(), " bytes)")

	advance.call()


func _sr_choice(_interp: LorelineInterpreter, _options: Array, _select: Callable) -> void:
	pass


func _sr_finished(_interp: LorelineInterpreter) -> void:
	print("[", _sr_phase, "] FINISHED (total dialogues: ", _sr_count, ")")

	if _sr_phase == "first_run":
		_sr_first_total = _sr_count
		if _sr_first_total != 3:
			_sr_ok = false
			_sr_done = true
			return

		_sr_phase = "resumed"
		_sr_count = 0
		var resumed := loreline.resume(_sr_script, _sr_dialogue, _sr_choice, _sr_finished, _sr_saved)
		if resumed == null:
			printerr("resume() returned null")
			_sr_ok = false
			_sr_done = true
	elif _sr_phase == "resumed":
		_sr_ok = _sr_count == 2
		_sr_done = true


# ---------------------------------------------------------------------------
# Async phase
# ---------------------------------------------------------------------------

var _as_done: bool = false
var _as_ok: bool = false
var _as_got_finished: bool = false
var _as_got_score_dialogue: bool = false


func _run_async() -> bool:
	var options := LorelineOptions.new()
	options.set_async_function("fetchScore", _as_fetch_score)

	var script = await loreline.parse("res://story/TestAsync.lor")
	if script == null:
		printerr("Failed to parse TestAsync.lor")
		return false

	loreline.play(script, _as_dialogue, _as_choice, _as_finished, "", options)

	while not _as_done:
		await get_tree().process_frame

	return _as_ok


func _as_fetch_score(interp: LorelineInterpreter, _args: Array, resolve: Callable) -> void:
	print("[async] fetchScore called, waiting 2s")
	await get_tree().create_timer(2.0).timeout
	interp.set_top_level_state_field("score", 42)
	print("[async] fetchScore resolving")
	resolve.call()


func _as_dialogue(_interp, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	print("DIALOGUE: ", text)
	if text.find("Your score is 42") != -1:
		_as_got_score_dialogue = true
	advance.call()


func _as_choice(_interp, _options: Array, _select: Callable) -> void:
	pass


func _as_finished(_interp) -> void:
	print("FINISHED")
	_as_got_finished = true
	_as_ok = _as_got_score_dialogue and _as_got_finished
	_as_done = true


# ---------------------------------------------------------------------------
# Container fields phase (replicates test_fields.gd)
# ---------------------------------------------------------------------------

var _fl_done: bool = false
var _fl_ok: bool = false
var _fl_dialogue_count: int = 0
var _fl_report_arg = null
var _fl_failed: bool = false
var _fl_fail_reason: String = ""


func _run_fields() -> bool:
	var options := LorelineOptions.new()
	options.set_function("getConfig", _fl_get_config)
	options.set_function("sendReport", _fl_send_report)
	options.set_async_function("fetchBonus", _fl_fetch_bonus)

	var script = await loreline.parse("res://story/TestFields.lor")
	if script == null:
		printerr("Failed to parse TestFields.lor")
		_fl_fail_reason = "parse failed"
		return false

	loreline.play(script, _fl_dialogue, _fl_choice, _fl_finished, "", options)

	while not _fl_done:
		await get_tree().process_frame

	return _fl_ok


func _fl_fail(reason: String) -> void:
	if not _fl_failed:
		_fl_failed = true
		_fl_fail_reason = reason


func _fl_get_config(_interp: LorelineInterpreter, _args: Array):
	return {"volume": 5, "tags": ["a", "b"]}


func _fl_send_report(_interp: LorelineInterpreter, args: Array):
	if args.size() > 0:
		_fl_report_arg = args[0]
	return null


func _fl_fetch_bonus(interp: LorelineInterpreter, args: Array, resolve: Callable) -> void:
	await get_tree().process_frame
	# Container arguments must survive the async custom function path
	if args.size() != 2 or typeof(args[0]) != TYPE_ARRAY or args[0].size() != 2 or args[0][0] != "sword":
		_fl_fail("async function array argument did not arrive, got: " + str(args))
	elif typeof(args[1]) != TYPE_DICTIONARY or args[1].get("name") != "Ana" or int(args[1].get("level")) != 3:
		_fl_fail("async function dictionary argument did not arrive, got: " + str(args))
	else:
		interp.set_state_field("bonus", {"granted": ["cape"], "count": 1})
	resolve.call()


func _fl_check_initial_state(interp: LorelineInterpreter) -> void:
	# Script-declared array
	var inventory = interp.get_state_field("inventory")
	if typeof(inventory) != TYPE_ARRAY or inventory.size() != 2 or inventory[0] != "sword" or inventory[1] != "shield":
		_fl_fail("inventory did not read as expected array, got: " + str(inventory))
		return

	# Script-declared object
	var profile = interp.get_state_field("profile")
	if typeof(profile) != TYPE_DICTIONARY or profile.get("name") != "Ana" or int(profile.get("level")) != 3:
		_fl_fail("profile did not read as expected dictionary, got: " + str(profile))
		return

	# Host-built nested container round-trip
	var payload := {"items": ["potion", 42], "active": true}
	interp.set_state_field("payload", payload)
	var back = interp.get_state_field("payload")
	if typeof(back) != TYPE_DICTIONARY or typeof(back.get("items")) != TYPE_ARRAY or back["items"].size() != 2 or back["items"][0] != "potion" or int(back["items"][1]) != 42 or back.get("active") != true:
		_fl_fail("payload did not round-trip, got: " + str(back))
		return

	# Deep-copy snapshot semantics: mutating a returned copy must not leak
	back["active"] = false
	back["items"].append("extra")
	var fresh = interp.get_state_field("payload")
	if fresh.get("active") != true or fresh["items"].size() != 2:
		_fl_fail("mutating a returned copy leaked into interpreter state, got: " + str(fresh))
		return

	# Character field containers
	interp.set_character_field("ana", "traits", ["bold", "curious"])
	var traits = interp.get_character_field("ana", "traits")
	if typeof(traits) != TYPE_ARRAY or traits.size() != 2 or traits[0] != "bold" or traits[1] != "curious":
		_fl_fail("character traits did not round-trip, got: " + str(traits))
		return

	# Beat references cross as marker dictionaries (the save data shape),
	# recognizable and accepted back by the runtime
	var beat_ref = interp.get_state_field("beatRef")
	if typeof(beat_ref) != TYPE_DICTIONARY or beat_ref.get("type") != "$beatRef":
		_fl_fail("beat reference did not read as a marker dictionary, got: " + str(beat_ref))
		return
	# Hand the marker back: the runtime must restore a live reference
	interp.set_state_field("beatRefBack", beat_ref)
	var beat_back = interp.get_state_field("beatRefBack")
	if typeof(beat_back) != TYPE_DICTIONARY or beat_back.get("type") != "$beatRef":
		_fl_fail("beat reference marker did not round-trip, got: " + str(beat_back))
		return


func _fl_check_function_results(interp: LorelineInterpreter) -> void:
	# Dictionary returned by a custom function, stored in script state
	var config = interp.get_state_field("config")
	if typeof(config) != TYPE_DICTIONARY or int(config.get("volume")) != 5:
		_fl_fail("custom function dictionary return did not round-trip, got: " + str(config))
		return
	var tags = config.get("tags")
	if typeof(tags) != TYPE_ARRAY or tags.size() != 2 or tags[0] != "a" or tags[1] != "b":
		_fl_fail("nested array in custom function return did not round-trip, got: " + str(tags))
		return

	# Dictionary passed as a custom function argument
	if typeof(_fl_report_arg) != TYPE_DICTIONARY or _fl_report_arg.get("name") != "Ana" or int(_fl_report_arg.get("level")) != 3:
		_fl_fail("custom function dictionary argument did not arrive, got: " + str(_fl_report_arg))
		return


func _fl_check_async_results(interp: LorelineInterpreter) -> void:
	# Container written from inside the async function while the script was paused
	var bonus = interp.get_state_field("bonus")
	if typeof(bonus) != TYPE_DICTIONARY or int(bonus.get("count")) != 1 or typeof(bonus.get("granted")) != TYPE_ARRAY or bonus["granted"].size() != 1 or bonus["granted"][0] != "cape":
		_fl_fail("bonus set during async function did not round-trip, got: " + str(bonus))
		return


func _fl_dialogue(interp: LorelineInterpreter, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	_fl_dialogue_count += 1
	print("[fields] DIALOGUE ", _fl_dialogue_count, ": ", text)
	if _fl_dialogue_count == 1:
		_fl_check_initial_state(interp)
	elif _fl_dialogue_count == 2:
		_fl_check_function_results(interp)
	elif _fl_dialogue_count == 3:
		_fl_check_async_results(interp)
	advance.call()


func _fl_choice(_interp, _options: Array, _select: Callable) -> void:
	pass


func _fl_finished(_interp) -> void:
	print("[fields] FINISHED")
	_fl_ok = not _fl_failed
	_fl_done = true
