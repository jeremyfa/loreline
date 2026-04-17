extends Node

var loreline: Loreline = Loreline.shared()


func _ready() -> void:
	var options := LorelineOptions.new()
	options.set_async_function("fetchScore", _fetch_score)

	var script := loreline.parse("res://story/TestAsync.lor")
	if script == null:
		printerr("Failed to parse TestAsync.lor")
		return

	loreline.play(script, _on_dialogue, _on_choice, _on_finished, "", options)


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
