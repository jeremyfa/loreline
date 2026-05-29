extends Node

# GC regression test: keep ticking after FINISHED so libLoreline's
# delta-accumulating Loreline_update_hx forces a hxcpp GC every 15s.
# Each Loreline async-function call used to leak one root in the resolve
# struct (Loreline_resolveAsync / Loreline_cancelAsync removed the
# registration on a local variable instead of the struct field), so the
# very first forced collect after FINISHED would walk freed memory and
# abort in GlobalAllocator::MarkAll.
#
# Survival contract: parse + play + a registered async fn + idle long
# enough to cross at least two 15s GC cycles. If the bug regresses, Godot
# crashes well before the GC_REGRESSION_OK marker is printed and the
# runner script's marker check fails. If the fix holds, the scene prints
# GC_REGRESSION_OK and exits cleanly.
#
# Wall-clock budget below: ~35s of post-FINISHED idle. The runner's
# RUN_TIMEOUT must be > that.

const SURVIVE_SECONDS_AFTER_FINISHED := 35.0

var loreline: Loreline = Loreline.shared()
var finished_at_msec: int = 0


func _ready() -> void:
	var options := LorelineOptions.new()
	options.set_async_function("fetchScore", _fetch_score)

	var script = await loreline.parse("res://story/TestAsync.lor")
	if script == null:
		printerr("Failed to parse TestAsync.lor")
		_quit(1)
		return

	loreline.play(script, _on_dialogue, _on_choice, _on_finished, "", options)


func _process(_delta: float) -> void:
	if finished_at_msec == 0:
		return
	var elapsed_msec := Time.get_ticks_msec() - finished_at_msec
	if elapsed_msec >= int(SURVIVE_SECONDS_AFTER_FINISHED * 1000):
		print("GC_REGRESSION_OK (survived ", elapsed_msec, "ms after FINISHED)")
		_quit(0)


func _fetch_score(interp: LorelineInterpreter, _args: Array, resolve: Callable) -> void:
	print("[async] fetchScore called, waiting 2s")
	await get_tree().create_timer(2.0).timeout
	interp.set_top_level_state_field("score", 42)
	print("[async] fetchScore resolving")
	resolve.call()


func _on_dialogue(_interp, _character: String, text: String, _tags: Array, advance: Callable) -> void:
	print("DIALOGUE: ", text)
	advance.call()


func _on_choice(_interp, _options: Array, _select: Callable) -> void:
	pass


func _on_finished(_interp) -> void:
	print("FINISHED")
	finished_at_msec = Time.get_ticks_msec()


func _quit(code: int) -> void:
	# Auto-quit headless/exported runs. Editor runs keep the window open.
	if not OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		get_tree().call_deferred("quit", code)
