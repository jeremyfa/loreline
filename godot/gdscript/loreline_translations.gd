class_name LorelineTranslations
extends RefCounted

## Opaque holder for a translations map, obtained from
## LorelineScript.extract_translations() or Loreline.load_locale(), and
## passed to LorelineOptions.set_translations().

var _translations = null


func _init(translations = null) -> void:
	_translations = translations
