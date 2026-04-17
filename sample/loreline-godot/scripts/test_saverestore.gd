extends Node

var loreline: Loreline = Loreline.shared()
var lor_script: LorelineScript
var saved_data: String = ""
var dialogue_count: int = 0
var phase: String = "first_run"  # "first_run" → "resumed" → "done"


func _ready() -> void:
	lor_script = loreline.parse("res://story/TestSaveRestore.lor")
	if lor_script == null:
		printerr("Failed to parse TestSaveRestore.lor")
		return

	loreline.play(lor_script, _on_dialogue, _on_choice, _on_finished)


func _on_dialogue(interp: LorelineInterpreter, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	dialogue_count += 1
	print("[", phase, "] DIALOGUE ", dialogue_count, ": ", text)

	# On the second dialogue of the first run, snapshot the state.
	if phase == "first_run" and dialogue_count == 2:
		saved_data = interp.save_state()
		print("[", phase, "] captured save data (", saved_data.length(), " bytes)")

	advance.call()


func _on_choice(_interp: LorelineInterpreter, _options: Array, _select: Callable) -> void:
	pass


func _on_finished(_interp: LorelineInterpreter) -> void:
	print("[", phase, "] FINISHED (total dialogues: ", dialogue_count, ")")

	if phase == "first_run":
		# First run delivered 3 dialogues; save captured at dialogue 2.
		var first_run_total := dialogue_count
		var first_run_ok := first_run_total == 3

		phase = "resumed"
		dialogue_count = 0

		# Create a fresh interpreter from the save. The Haxe save semantics
		# mean the saved dialogue (dialogue 2) is re-fired on resume, then
		# execution continues from there (dialogue 3 → finish).
		var resumed := loreline.resume(lor_script, _on_dialogue, _on_choice, _on_finished, saved_data)
		if resumed == null:
			printerr("resume() returned null")
			_report(false, "resume returned null")
			return

		# Expected: 2 dialogues on resume (dialogue 2 replay + dialogue 3).
		# Wait for FINISHED to evaluate.
		if not first_run_ok:
			_report(false, "first run had " + str(first_run_total) + " dialogues, expected 3")
	elif phase == "resumed":
		var resumed_ok := dialogue_count == 2
		phase = "done"
		_report(resumed_ok, "resumed run had " + str(dialogue_count) + " dialogues (expected 2)")


func _report(passed: bool, detail: String) -> void:
	if passed:
		print("TEST PASSED")
	else:
		print("TEST FAILED: ", detail)
