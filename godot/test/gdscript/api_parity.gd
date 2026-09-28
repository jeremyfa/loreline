extends SceneTree

# Headless entry point of the API checks (api_parity_checks.gd), for the
# GDScript and native backends. Prints API_PARITY_OK on success,
# API_PARITY_FAILED: <reason> otherwise.


func _initialize() -> void:
	_run()


func _run() -> void:
	var reason: String = await preload("res://api_parity_checks.gd").new().run(self)
	if reason == "":
		print("API_PARITY_OK")
	else:
		print("API_PARITY_FAILED: ", reason)
	quit(0 if reason == "" else 1)
