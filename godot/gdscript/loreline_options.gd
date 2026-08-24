class_name LorelineOptions
extends RefCounted

## Options for Loreline.play() / Loreline.resume(). Mirrors the native
## GDExtension API.
##
## Custom function conventions:
## - sync:  func(interp: LorelineInterpreter, args: Array) -> Variant
## - async: func(interp: LorelineInterpreter, args: Array, resolve: Callable)
##   Call resolve.call() to resume execution. Calling resolve twice is a
##   no-op; dropping it without calling leaves the interpreter paused.

var strict_access: bool = false:
	set = set_strict_access, get = get_strict_access

var _strict_access: bool = false
var _functions: Dictionary = {}
var _async_functions: Dictionary = {}
var _translations: LorelineTranslations = null


func set_strict_access(strict: bool) -> void:
	_strict_access = strict


func get_strict_access() -> bool:
	return _strict_access


func set_function(name: String, callable: Callable) -> void:
	_async_functions.erase(name)
	_functions[name] = callable


func set_async_function(name: String, callable: Callable) -> void:
	_functions.erase(name)
	_async_functions[name] = callable


func remove_function(name: String) -> void:
	_functions.erase(name)
	_async_functions.erase(name)


func set_translations(translations: LorelineTranslations) -> void:
	_translations = translations


## Builds the options value passed to the compiled Loreline core.
func _build_core_options() -> Dictionary:
	var options := {}
	if _strict_access:
		options["strictAccess"] = true
	if _translations != null and _translations._translations != null:
		options["translations"] = _translations._translations
	var functions := {}
	for name in _functions:
		var user_fn: Callable = _functions[name]
		functions[name] = func(core_interp, args):
			# Sync call: control returns to the core immediately, so the
			# inflight retainer is left exactly as it was.
			return user_fn.call(Loreline._wrapper_of(core_interp), args)
	for name in _async_functions:
		var user_fn: Callable = _async_functions[name]
		functions[name] = func(core_interp, args):
			return _Loreline_Async.new(func(done: Callable):
				var interp = Loreline._wrapper_of(core_interp)
				# An unresolved async call is a callback still owed to the
				# host, and `resolve` below captures `interp` strongly, so
				# holding that Callable keeps the run alive for the whole
				# pause. That mirrors the native backend, where the resolve
				# CallableCustom holds a Ref<LorelineInterpreter>. Hand the
				# retention over to it, exactly as the dialogue and choice
				# deliveries hand over to their advance/select Callables.
				Loreline.shared()._release_inflight(interp)
				var used := [false]
				var resolve := func():
					if used[0]:
						push_warning("Loreline: resolve called more than once, ignoring.")
						return
					used[0] = true
					# Control comes back to the runtime: retain across the gap
					# to the next delivery, which is where it is released.
					Loreline.shared()._retain_inflight(interp)
					done.call()
				user_fn.call(interp, args, resolve))
	if functions.size() > 0:
		options["functions"] = functions
	return options
