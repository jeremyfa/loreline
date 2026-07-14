extends SceneTree

# Runs the full Loreline .lor test suite against the GDScript-compiled
# runtime, following the same protocol as the other target runners.
#
# Usage (after an --import pass):
#   godot --headless --path godot/gdscript-test --script res://run_tests.gd -- <test-dir> [file-filter]
#
# <test-dir> is resolved against the project directory; defaults to ../../test.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir_arg: String = args[0] if args.size() > 0 else "../../test"
	var file_filter: String = args[1] if args.size() > 1 else ""

	var project_dir := ProjectSettings.globalize_path("res://")
	var test_dir := dir_arg
	if not test_dir.is_absolute_path():
		test_dir = project_dir.path_join(dir_arg).simplify_path()

	if DirAccess.open(test_dir) == null:
		print("Cannot open test directory: ", test_dir)
		quit(2)
		return

	var suite = _Loreline_PortableTestSuite.new(_read_file, _print_line)

	var locale_regex := RegEx.new()
	locale_regex.compile("\\.\\w{2}\\.lor$")

	# Collect .lor files recursively, skipping imports/ and modified/
	# helper directories and per-locale translation files, matching the
	# other target runners.
	var files: Array[String] = []
	_collect_lor_files(test_dir, locale_regex, files)
	files.sort()

	for path in files:
		if file_filter != "" and path.find(file_filter) == -1:
			continue
		var content := FileAccess.get_file_as_string(path)
		suite.runFile(path, content)

	var ok: bool = suite.printSummary()
	quit(0 if ok else 1)


func _collect_lor_files(dir_path: String, locale_regex: RegEx, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry != "imports" and entry != "modified":
				_collect_lor_files(full, locale_regex, out)
		elif entry.ends_with(".lor") and locale_regex.search(entry) == null:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _read_file(path: String) -> Variant:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return null


func _print_line(line: String) -> void:
	print(line)
