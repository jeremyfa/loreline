class_name LorelineTranslations
extends RefCounted

## Opaque holder for a translations map. To play a story in a language, get it
## from Loreline.load_locale() and pass it to LorelineOptions.set_translations().
## LorelineScript.extract_translations() gives the translations of one file by
## #id, which the interpreter can't play.

var _translations = null


func _init(translations = null) -> void:
	_translations = translations
