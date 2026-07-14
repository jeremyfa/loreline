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
			return user_fn.call(core_interp.wrapper, args)
	for name in _async_functions:
		var user_fn: Callable = _async_functions[name]
		functions[name] = func(core_interp, args):
			return _Loreline_Async.new(func(done: Callable):
				var used := [false]
				var resolve := func():
					if used[0]:
						push_warning("Loreline: resolve called more than once, ignoring.")
						return
					used[0] = true
					done.call()
				user_fn.call(core_interp.wrapper, args, resolve))
	if functions.size() > 0:
		options["functions"] = functions
	return options
