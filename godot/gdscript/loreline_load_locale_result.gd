class_name LorelineLoadLocaleResult
extends RefCounted

## One-shot await target returned by Loreline.load_locale().
## Emission is deferred to the next process frame so awaiters connect first.

signal completed(translations)
