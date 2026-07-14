extends SceneTree

# Loads every generated GDScript file and reports scripts that fail to
# parse or compile. Run headless after an --import pass:
#   godot --headless --path . --script res://load_all.gd

func _initialize() -> void:
	var dir := DirAccess.open("res://core")
	if dir == null:
		print("LOAD_ALL_FAILED: cannot open res://core")
		quit(1)
		return
	var failures := 0
	var count := 0
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".gd"):
			count += 1
			var script = load("res://core/" + file)
			if script == null or not script.can_instantiate():
				failures += 1
				print("SCRIPT_ERROR: ", file)
		file = dir.get_next()
	dir.list_dir_end()
	if failures == 0:
		print("LOAD_ALL_OK: ", count, " scripts")
		quit(0)
	else:
		print("LOAD_ALL_FAILED: ", failures, " of ", count)
		quit(1)
