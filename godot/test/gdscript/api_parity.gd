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

	# 7. Child interpreters
	await _run_spawn(loreline)

	# 8. Random generator in save data, reseeded from the host
	await _run_seed_random(loreline)

	_finish()


# Same scenario in every binding runner. A child spawned from the root shares
# its state, gets host functions bound to itself, and both playheads are saved
# from any interpreter then continued after a restore with resume_spawn().
var _spawn_log: Array = []
var _spawn_pending := {}


func _spawn_name(interp: LorelineInterpreter) -> String:
	var key := interp.get_key()
	return key if key != "" else "root"


func _on_spawn_dialogue(interp: LorelineInterpreter, character: String, text: String, _tags: Array, advance: Callable) -> void:
	var name := _spawn_name(interp)
	_spawn_log.append(name + ": " + (character + ": " if character != "" else "") + text)
	_spawn_pending[name] = advance


func _spawn_wait(count: int) -> void:
	for i in 60:
		if _spawn_log.size() >= count:
			return
		await process_frame
	_fail("spawn: timed out waiting for " + str(count) + " lines, got " + str(_spawn_log))


func _spawn_next(name: String) -> void:
	if not _spawn_pending.has(name):
		_fail("spawn: no pending dialogue for " + name)
		return
	var advance: Callable = _spawn_pending[name]
	_spawn_pending.erase(name)
	advance.call()


func _run_spawn(loreline) -> void:
	var source := """
state
  gold: 0

beat Main
  gold = gold + 1

  Main gold $gold

  Main where $current_beat() host $who()

beat Side
  new state
    local: 5

  gold = gold + 10

  Side gold $gold local $local

  Side where $current_beat() host $who()
"""
	var script = await loreline.parse(source, "spawn.lor")
	if script == null:
		_fail("spawn: parse returned null")
		return

	var noop_choice := func(_interp, _options, _select): pass
	var noop_finished := func(_interp): pass
	var options := LorelineOptions.new()
	options.set_function("who", func(interp, _args): return _spawn_name(interp))

	var root: LorelineInterpreter = loreline.play(script, _on_spawn_dialogue, noop_choice, noop_finished, "Main", options)
	await _spawn_wait(1)
	var npc: LorelineInterpreter = root.spawn("npc", _on_spawn_dialogue, noop_choice, noop_finished)
	if npc == null:
		_fail("spawn: spawn returned null")
		return
	npc.start("Side")
	await _spawn_wait(2)
	_spawn_next("root")
	await _spawn_wait(3)

	if npc.get_key() != "npc" or root.get_key() != "":
		_fail("spawn: unexpected keys " + npc.get_key() + " / " + root.get_key())
	if npc.is_root() or not root.is_root():
		_fail("spawn: is_root mismatch")
	var saved: String = npc.save_state()
	if saved != root.save_state():
		_fail("spawn: save from child differs from save from root")

	_spawn_pending.clear()
	var restored: LorelineInterpreter = loreline.resume(script, _on_spawn_dialogue, noop_choice, noop_finished, saved, "", options)
	await _spawn_wait(4)
	if restored.resumable_spawn_keys() != ["npc"]:
		_fail("spawn: resumable_spawn_keys " + str(restored.resumable_spawn_keys()))
	var restored_npc: LorelineInterpreter = restored.resume_spawn("npc", _on_spawn_dialogue, noop_choice, noop_finished)
	if restored_npc == null:
		_fail("spawn: resume_spawn returned null")
		return
	await _spawn_wait(5)
	_spawn_next("npc")
	await _spawn_wait(6)

	var expected := [
		"root: Main gold 1",
		"npc: Side gold 11 local 5",
		"root: Main where Main host root",
		"root: Main where Main host root",
		"npc: Side gold 11 local 5",
		"npc: Side where Side host npc"
	]
	if _spawn_log != expected:
		_fail("spawn: unexpected log " + str(_spawn_log))


# Same scenario in every binding runner. The random generator is saved, and
# seed_random() reseeds it from the host: after a restore at the first line,
# reseeding with the seed of the script makes the second line draw what the
# first one drew.
func _run_seed_random(loreline) -> void:
	var source := """
beat Main
  seed_random(7)
  First $random(1, 1000000000)

  Second $random(1, 1000000000)
"""
	var script = await loreline.parse(source, "random.lor")
	if script == null:
		_fail("random: parse returned null")
		return

	_spawn_log.clear()
	_spawn_pending.clear()
	var noop_choice := func(_interp, _options, _select): pass
	var noop_finished := func(_interp): pass
	var root: LorelineInterpreter = loreline.play(script, _on_spawn_dialogue, noop_choice, noop_finished, "Main")
	await _spawn_wait(1)
	var saved: String = root.save_state()

	_spawn_pending.clear()
	var restored: LorelineInterpreter = loreline.resume(script, _on_spawn_dialogue, noop_choice, noop_finished, saved)
	await _spawn_wait(2)
	restored.seed_random(7)
	_spawn_next("root")
	await _spawn_wait(3)

	var first: String = _spawn_log[0].get_slice(" ", 2) if _spawn_log.size() > 0 else ""
	var second: String = _spawn_log[2].get_slice(" ", 2) if _spawn_log.size() > 2 else ""
	if first == "" or second != first:
		_fail("random: expected " + first + " after reseeding, got " + str(_spawn_log))


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
