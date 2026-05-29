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
