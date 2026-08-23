@tool
class_name LorelineResourceLoader
extends ResourceFormatLoader

## Makes `.lor` files recognized as resources, mirroring the native
## GDExtension's LorelineResourceLoader.
##
## Beyond allowing `load("res://story.lor")`, this is what lets the export
## system see `.lor` files at all: a preset exporting "all resources" only
## picks up files some ResourceFormatLoader claims, so without this the story
## files are silently missing from every export and the game runs fine in the
## editor but shows nothing once exported.
##
## The `class_name` above is load-bearing, not cosmetic: Godot picks custom
## resource format loaders up from the global script class registry, which is
## what makes this work with no plugin enabled and no project setup. Removing
## it silently stops `.lor` files from being exported.


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["lor"])


func _handles_type(type: StringName) -> bool:
	return type == &"Resource"


func _get_resource_type(path: String) -> String:
	if path.get_extension().to_lower() == "lor":
		return "Resource"
	return ""


func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LorelineResourceLoader: failed to open " + path)
		return null

	var source := file.get_as_text()
	file.close()

	var res := Resource.new()
	res.set_meta("source", source)
	res.set_meta("loreline_path", path)
	return res
