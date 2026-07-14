class_name LorelineScript
extends RefCounted

## A parsed Loreline script. Mirrors the native GDExtension API.

var _script = null


func _init(script = null) -> void:
	_script = script


## Runs the script. Prefer Loreline.play() which also wires Callables.
func play(beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	return LorelineInterpreter._play(_script, beat_name, options)


## Resumes the script from saved state. Prefer Loreline.resume().
func resume(save_data: String, beat_name: String = "", options: LorelineOptions = null) -> LorelineInterpreter:
	return LorelineInterpreter._resume(_script, save_data, beat_name, options)


## Extracts translations from a parsed translation script.
func extract_translations() -> LorelineTranslations:
	return LorelineTranslations.new(loreline_Loreline.extractTranslations(_script))


## Prints the script back to Loreline source form.
func print_script() -> String:
	return loreline_Loreline._print(_script, null, null)


## Serializes the script AST to JSON.
func to_json(pretty: bool = false) -> String:
	return loreline_Json.stringify(_script.toJson(), pretty)


## Recreates a script from to_json() output.
static func from_json(json: String) -> LorelineScript:
	return LorelineScript.new(loreline_Script.fromJson(loreline_Json.parse(json)))
