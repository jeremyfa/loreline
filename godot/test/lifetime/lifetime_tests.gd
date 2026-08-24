extends SceneTree

## Backend-agnostic lifetime tests for the Loreline Godot integration.
##
## Uses only the public API, so the exact same file runs against the native
## GDExtension and against the pure-GDScript addon, and both must agree. The
## contract under test:
##
##   An interpreter stays alive exactly as long as the host holds a reference
##   to it, or Loreline still owes the host a callback. Once neither holds, it
##   is released, without stop() or a finish being needed.
##
## Everything is asserted through weakref(), which is deterministic: no object
## counting, no reliance on when the engine happens to sweep.

var failures: Array = []
var checks: int = 0

## Guards against a test function aborting halfway: GDScript unwinds the
## coroutine on a runtime error, the remaining checks simply never run, and the
## suite would otherwise report a smaller total and still call it a pass. Bump
## this when adding or removing checks.
const EXPECTED_CHECKS := 42

## Blank lines matter: consecutive text lines form a single multiline block, so
## a `choice` right under a dialogue line would be swallowed into its text.
## Avoid bare Loreline keywords as dialogue text too (pick, once, cycle,
## shuffle, sequence): they do not lex as plain text.
const STORY := """
beat Start
  Narrator: one

  Narrator: two

  -> Choose

beat Choose
  Narrator: make a decision

  choice
    first
      Narrator: took first

      -> Done
    second
      Narrator: took second

      -> Done

beat Done
  Narrator: end
"""

## Story for the parallel-runs case: each run picks a different branch, writes
## it into its own state, and reads it back, so cross-talk between concurrent
## interpreters shows up as a wrong value rather than as a crash.
const BRANCH_STORY := """
state
  picked: "none"

beat Start
  Narrator: begin

  choice
    take alpha
      picked = "alpha"

      -> Show
    take beta
      picked = "beta"

      -> Show

beat Show
  Narrator: chose $picked
"""

## Stories whose runtime blows up, one straight away and one from inside a
## wait() continuation (a different code path: it surfaces from the runtime
## pump rather than from the host's own call).
const BAD_STORY := """
beat Start
  Narrator: before the error

  no_such_function()

  Narrator: never reached
"""

const BAD_WAIT_STORY := """
beat Start
  Narrator: before waiting

  wait(0.05)

  no_such_function()
"""

## Separate story for the async-function case: the host is handed a resolve
## Callable and answers on a later frame, which is a real deferred gap on both
## backends.
const ASYNC_STORY := """
beat Start
  Narrator: before

  host_waits()

  Narrator: after
"""


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures.append(what)
		print("  FAIL ", what)


## Pumps process frames. Loreline defers starts and drains its queue in
## _process, so tests have to let real frames go by rather than awaiting idle.
func _pump(frames: int = 4) -> void:
	for i in range(frames):
		await process_frame


func _parse(loreline) -> Object:
	var script = await loreline.parse(STORY)
	return script


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Loreline lifetime tests ==")
	var loreline = Loreline.shared()
	var script = await _parse(loreline)
	if script == null:
		print("FATAL: could not parse the test story")
		quit(2)
		return

	await _test_released_after_finish(loreline, script)
	await _test_alive_while_only_callable_held(loreline, script)
	await _test_released_when_abandoned(loreline, script)
	await _test_alive_across_deferred_start(loreline, script)
	await _test_no_accumulation_over_runs(loreline, script)
	await _test_async_function_gap(loreline)
	await _test_async_pending_retains(loreline)
	await _test_failed_parse_does_not_poison(loreline)
	await _test_runtime_error_is_contained(loreline)
	await _test_parallel_interpreters(loreline)
	await _test_dropping_one_run_spares_the_others(loreline)
	await _test_continuation_is_the_only_thing_holding(loreline)

	print("")
	if checks != EXPECTED_CHECKS:
		print("LIFETIME_TESTS_FAILED: ran %d checks, expected %d (a test aborted, or the count needs updating)" % [checks, EXPECTED_CHECKS])
		quit(1)
		return
	if failures.is_empty():
		print("ALL_LIFETIME_TESTS_PASSED (%d checks)" % checks)
		quit(0)
	else:
		print("LIFETIME_TESTS_FAILED: %d of %d" % [failures.size(), checks])
		for f in failures:
			print("  - ", f)
		quit(1)


## A run played to its end must be collected once the host lets go, with no
## explicit teardown.
func _test_released_after_finish(loreline, script) -> void:
	print("- released after finish")
	var done := [false]
	var weak: WeakRef = null
	var interp = loreline.play(
		script,
		func(i, _c, _t, _g, advance): advance.call(),
		func(i, _o, select): select.call(0),
		func(_i): done[0] = true
	)
	weak = weakref(interp)
	interp = null
	# Drive to the end: the host holds nothing, only the Callables handed to
	# the handlers above, which is exactly the supported way to play.
	for i in range(200):
		await _pump(1)
		if done[0]:
			break
	_check(done[0], "story reached finished")
	await _pump(4)
	_check(weak.get_ref() == null, "interpreter released after finish")


## While the host holds only the advance Callable, the run must stay alive:
## that Callable is a reference to the interpreter.
func _test_alive_while_only_callable_held(loreline, script) -> void:
	print("- alive while only the advance Callable is held")
	var kept := [Callable()]
	var weak: WeakRef = null
	var interp = loreline.play(
		script,
		func(i, _c, _t, _g, advance):
			# Park the very first advance and keep only that.
			if not kept[0].is_valid():
				kept[0] = advance
			else:
				advance.call(),
		func(i, _o, select): select.call(0),
		func(_i): pass
	)
	weak = weakref(interp)
	interp = null
	for i in range(60):
		await _pump(1)
		if kept[0].is_valid():
			break
	_check(kept[0].is_valid(), "captured an advance Callable")
	await _pump(10)
	_check(weak.get_ref() != null, "interpreter alive while its Callable is held")
	# Releasing it with nothing else holding must collect the run.
	kept[0] = Callable()
	await _pump(6)
	_check(weak.get_ref() == null, "interpreter released once the Callable is dropped")


## Dropping every reference mid-story, without advancing, must collect the run
## instead of leaking it until a finish that will never come.
func _test_released_when_abandoned(loreline, script) -> void:
	print("- released when abandoned mid-story")
	var seen := [0]
	var weak: WeakRef = null
	var interp = loreline.play(
		script,
		func(i, _c, _t, _g, _advance): seen[0] += 1,
		func(i, _o, _select): pass,
		func(_i): pass
	)
	weak = weakref(interp)
	interp = null
	for i in range(60):
		await _pump(1)
		if seen[0] > 0:
			break
	_check(seen[0] > 0, "story delivered a first dialogue")
	# The handler never advanced and dropped its Callable, so nothing is owed
	# and nothing references the run any more.
	await _pump(8)
	_check(weak.get_ref() == null, "abandoned interpreter released")


## The retainer has to cover the window between play() and the deferred start,
## even if the host discards the returned value immediately.
func _test_alive_across_deferred_start(loreline, script) -> void:
	print("- survives a discarded play() until the first callback")
	var got := [false]
	loreline.play(
		script,
		func(i, _c, _t, _g, _advance): got[0] = true,
		func(i, _o, _select): pass,
		func(_i): pass
	)
	for i in range(60):
		await _pump(1)
		if got[0]:
			break
	_check(got[0], "discarded play() still reached its first dialogue")


## Many sequential runs must not pile up: after the last one settles, none of
## the earlier interpreters may still be alive.
func _test_no_accumulation_over_runs(loreline, script) -> void:
	print("- no accumulation over repeated runs")
	var weaks: Array = []
	for n in range(5):
		var done := [false]
		var interp = loreline.play(
			script,
			func(i, _c, _t, _g, advance): advance.call(),
			func(i, _o, select): select.call(0),
			func(_i): done[0] = true
		)
		weaks.append(weakref(interp))
		interp = null
		for i in range(200):
			await _pump(1)
			if done[0]:
				break
	await _pump(8)
	var alive := 0
	for w in weaks:
		if w.get_ref() != null:
			alive += 1
	_check(alive == 0, "all %d runs released (alive=%d)" % [weaks.size(), alive])


## An async custom function pauses the story until the host resolves it, which
## is a genuinely deferred gap on both backends. While the host holds the
## interpreter (the supported pattern), the story must survive the pause and
## carry on, then be collected once the host lets go.
func _test_async_function_gap(loreline) -> void:
	print("- async function pause and resume")
	var script = await loreline.parse(ASYNC_STORY)
	if script == null:
		_check(false, "async story parsed")
		return
	_check(true, "async story parsed")

	var resolver := [Callable()]
	var texts := []
	var options = LorelineOptions.new()
	options.set_async_function("host_waits", func(_i, _args, resolve):
		resolver[0] = resolve)

	var interp = loreline.play(
		script,
		func(_i, _c, text, _g, advance):
			texts.append(text)
			advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): pass,
		"",
		options
	)
	var weak := weakref(interp)

	for i in range(60):
		await _pump(1)
		if resolver[0].is_valid():
			break
	_check(resolver[0].is_valid(), "host received the resolve Callable")
	_check(texts.size() == 1, "story paused at the async call (texts=%d)" % texts.size())

	# Answer several frames later: the pause must not have lost the run.
	await _pump(6)
	_check(weak.get_ref() != null, "interpreter alive while the host holds it")
	resolver[0].call()
	for i in range(60):
		await _pump(1)
		if texts.size() > 1:
			break
	_check(texts.size() > 1, "story resumed after resolve (texts=%d)" % texts.size())

	# Let go of everything: the run must be collected.
	interp = null
	resolver[0] = Callable()
	await _pump(8)
	_check(weak.get_ref() == null, "interpreter released after the async run ended")


## A pending async call is a callback still owed to the host, so holding only
## the resolve Callable must keep the run alive, the same way holding only an
## advance Callable does.
func _test_async_pending_retains(loreline) -> void:
	print("- pending async call retains the run")
	var script = await loreline.parse(ASYNC_STORY)
	if script == null:
		_check(false, "async story parsed (retention case)")
		return

	var resolver := [Callable()]
	var texts := []
	var options = LorelineOptions.new()
	options.set_async_function("host_waits", func(_i, _args, resolve):
		resolver[0] = resolve)

	var interp = loreline.play(
		script,
		func(_i, _c, text, _g, advance):
			texts.append(text)
			advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): pass,
		"",
		options
	)
	var weak := weakref(interp)

	for i in range(60):
		await _pump(1)
		if resolver[0].is_valid():
			break
	_check(resolver[0].is_valid(), "paused with a resolve Callable in hand")

	# Drop every other reference: only the resolve Callable is left.
	interp = null
	await _pump(10)
	_check(weak.get_ref() != null, "run alive while only resolve is held")

	# It must still be usable, and the story must carry on.
	resolver[0].call()
	for i in range(60):
		await _pump(1)
		if texts.size() > 1:
			break
	_check(texts.size() > 1, "story resumed from the retained run (texts=%d)" % texts.size())

	resolver[0] = Callable()
	await _pump(8)
	_check(weak.get_ref() == null, "run released once resolve is dropped")


## A parse failure must stay local to that call. The GDScript runtime lowers
## Haxe throws to a global pending flag, so an unconsumed one used to make every
## later call short-circuit, killing the runtime for the rest of the process.
func _test_failed_parse_does_not_poison(loreline) -> void:
	print("- a failed parse does not poison later parses")
	var good = await loreline.parse(STORY)
	_check(good != null, "good story parses before the failure")

	var bad = await loreline.parse("beat\n    ???? %%%\n  choice choice choice\n")
	_check(bad == null, "invalid story reports failure")

	var again = await loreline.parse(STORY)
	_check(again != null, "the same good story still parses after a failure")

	# And the runtime as a whole must still work, not just parsing.
	var done := [false]
	loreline.play(
		again,
		func(_i, _c, _t, _g, advance): advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): done[0] = true
	)
	for i in range(200):
		await _pump(1)
		if done[0]:
			break
	_check(done[0], "a story still plays to the end after a parse failure")


## A story that errors at runtime must not take the rest of the runtime with it:
## other interpreters keep running, the failed runs are released rather than
## retained forever, and later runs still work. The pending-exception flag is
## global, so getting this wrong breaks every interpreter at once.
func _test_runtime_error_is_contained(loreline) -> void:
	print("- a runtime error stays contained")
	var bad = await loreline.parse(BAD_STORY)
	var bad_wait = await loreline.parse(BAD_WAIT_STORY)
	var good = await loreline.parse(STORY)
	_check(bad != null and bad_wait != null and good != null, "error stories parsed")

	# A healthy run alongside two failing ones, started in between them.
	var texts := []
	var done := [false]
	var healthy = loreline.play(
		good,
		func(_i, _c, text, _g, advance):
			texts.append(text)
			advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): done[0] = true
	)
	var f1 = loreline.play(
		bad,
		func(_i, _c, _t, _g, advance): advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): pass
	)
	var f2 = loreline.play(
		bad_wait,
		func(_i, _c, _t, _g, advance): advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): pass
	)
	for i in range(200):
		await _pump(1)
		if done[0]:
			break
	_check(done[0], "healthy run finished next to two failing ones")

	var w1 := weakref(f1)
	var w2 := weakref(f2)
	healthy = null
	f1 = null
	f2 = null
	await _pump(10)
	_check(w1.get_ref() == null, "run that errored immediately was released")
	_check(w2.get_ref() == null, "run that errored from a wait() was released")

	# The runtime must still be fully usable.
	var later := [false]
	loreline.play(
		good,
		func(_i, _c, _t, _g, advance): advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): later[0] = true
	)
	for i in range(200):
		await _pump(1)
		if later[0]:
			break
	_check(later[0], "a new run still plays to the end after the errors")


## Several interpreters must run side by side without interfering: each keeps
## its own state, gets only its own callbacks, and its lifetime is independent
## of the others. Nothing here auto-advances; the test parks each run's Callable
## and drives them round-robin, so the runs really are interleaved rather than
## each finishing before the next begins.
func _test_parallel_interpreters(loreline) -> void:
	print("- parallel interpreters stay independent")
	var script = await loreline.parse(BRANCH_STORY)
	if script == null:
		_check(false, "branch story parsed")
		return
	_check(true, "branch story parsed")

	# Per-run recorded output, and its parked continuation.
	var texts := [[], [], []]
	var pending: Array = [Callable(), Callable(), Callable()]
	var kind := ["", "", ""]   # "advance" or "select"
	var finished := [false, false, false]
	var runs: Array = []

	for n in range(3):
		var idx := n
		runs.append(loreline.play(
			script,
			func(_i, _c, text, _g, advance):
				texts[idx].append(text)
				pending[idx] = advance
				kind[idx] = "advance",
			func(_i, _o, select):
				pending[idx] = select
				kind[idx] = "select",
			func(_i): finished[idx] = true
		))

	# Round-robin: give every run one step per pass. Runs 0 and 2 take the
	# first option, run 1 takes the second. `step` is declared out here and
	# cleared below: a Callable left in a local keeps its interpreter alive,
	# which would look like a leak that is really the test's own doing.
	var step := Callable()
	for pass_no in range(40):
		var progressed := false
		for n in range(3):
			if finished[n] or not pending[n].is_valid():
				continue
			step = pending[n]
			pending[n] = Callable()
			progressed = true
			if kind[n] == "select":
				step.call(1 if n == 1 else 0)
			else:
				step.call()
		await _pump(1)
		if finished[0] and finished[1] and finished[2]:
			break
		if not progressed:
			continue

	_check(finished[0] and finished[1] and finished[2],
		"all three runs finished (%s)" % str(finished))

	# No cross-talk: each run saw its own two lines, in order, and the branch it
	# actually chose.
	var shapes_ok := true
	var branches := []
	for n in range(3):
		if texts[n].size() != 2 or texts[n][0] != "begin":
			shapes_ok = false
		branches.append(texts[n][1] if texts[n].size() > 1 else "<missing>")
	_check(shapes_ok, "each run got exactly its own two lines (%s)" % str(texts.map(func(t): return t.size())))
	_check(branches[0] == "chose alpha" and branches[2] == "chose alpha",
		"runs that picked the first option read back alpha (%s)" % str(branches))
	_check(branches[1] == "chose beta",
		"the run that picked the second option read back beta (%s)" % str(branches))

	# Lifetime isolation: dropping the finished runs collects them all.
	var weaks := []
	for r in runs:
		weaks.append(weakref(r))
	runs.clear()
	# Clear in place: the handler lambdas captured this very Array, so rebinding
	# the local would leave them holding the old one, and any Callable still in
	# it keeps its interpreter alive.
	for n in range(3):
		pending[n] = Callable()
	step = Callable()
	await _pump(8)
	var alive := 0
	for w in weaks:
		if w.get_ref() != null:
			alive += 1
	_check(alive == 0, "all three runs released independently (alive=%d)" % alive)


## Dropping one interpreter mid-run must not disturb the others.
func _test_dropping_one_run_spares_the_others(loreline) -> void:
	print("- dropping one run mid-story spares the others")
	var script = await loreline.parse(STORY)
	if script == null:
		_check(false, "story parsed for the drop case")
		return

	var keep_done := [false]
	var keep_texts := []
	var keep = loreline.play(
		script,
		func(_i, _c, text, _g, advance):
			keep_texts.append(text)
			advance.call(),
		func(_i, _o, select): select.call(0),
		func(_i): keep_done[0] = true
	)
	# A second run parked on its first dialogue, then abandoned.
	var parked := [Callable()]
	var doomed = loreline.play(
		script,
		func(_i, _c, _t, _g, advance): parked[0] = advance,
		func(_i, _o, _select): pass,
		func(_i): pass
	)
	var weak_doomed := weakref(doomed)
	for i in range(60):
		await _pump(1)
		if parked[0].is_valid():
			break
	_check(parked[0].is_valid(), "second run reached its first dialogue")

	doomed = null
	parked[0] = Callable()
	await _pump(8)
	_check(weak_doomed.get_ref() == null, "abandoned run collected")

	for i in range(200):
		await _pump(1)
		if keep_done[0]:
			break
	_check(keep_done[0], "the kept run finished after the other was collected (texts=%d)" % keep_texts.size())


## Pins what the continuation handed to a handler is, and is not, with respect
## to ownership: it is the one thing keeping an otherwise unreferenced run
## alive, and discarding it without calling it must let the run go. This is the
## contract the C API layer deliberately does NOT provide (there the value
## carries the handle only); the engine binding is what adds ownership, so it
## has to be checked here rather than assumed.
func _test_continuation_is_the_only_thing_holding(loreline) -> void:
	print("- the continuation owns the run, and only it")
	var script = await loreline.parse(STORY)
	if script == null:
		_check(false, "story parsed for the ownership case")
		return

	# Case 1: discarded without being called, nothing else references the run.
	var reached := [false]
	var discarded = loreline.play(
		script,
		func(_i, _c, _t, _g, _advance): reached[0] = true,  # let `advance` die here
		func(_i, _o, _select): pass,
		func(_i): pass
	)
	var weak_discarded := weakref(discarded)
	discarded = null
	for i in range(60):
		await _pump(1)
		if reached[0]:
			break
	_check(reached[0], "run reached its handler")
	await _pump(10)
	_check(weak_discarded.get_ref() == null, "run released after its continuation was discarded")

	# Case 2: the continuation is the sole owner, and hands ownership over to
	# the next one at each step, so the run survives a whole story that way.
	var held := [Callable()]
	var held_kind := [""]
	var finished := [false]
	var steps := [0]
	var chained = loreline.play(
		script,
		func(_i, _c, _t, _g, advance):
			steps[0] += 1
			held[0] = advance
			held_kind[0] = "advance",
		func(_i, _o, select):
			held[0] = select
			held_kind[0] = "select",
		func(_i): finished[0] = true
	)
	var weak_chained := weakref(chained)
	chained = null
	await _pump(4)
	_check(weak_chained.get_ref() != null, "run alive with only the continuation holding it")

	# Drive it to the end holding nothing but the latest continuation.
	var step := Callable()
	for i in range(200):
		if held[0].is_valid():
			step = held[0]
			var kind: String = held_kind[0]
			held[0] = Callable()
			# Call each continuation with its own arity. The native backend
			# tolerates a spare argument on advance, the GDScript one does not,
			# so passing one would only test that difference by accident.
			if kind == "select":
				step.call(0)
			else:
				step.call()
		await _pump(1)
		if finished[0]:
			break
	_check(finished[0], "story finished driven only by its continuations (steps=%d)" % steps[0])

	held[0] = Callable()
	step = Callable()
	await _pump(10)
	_check(weak_chained.get_ref() == null, "run released once the last continuation is gone")
