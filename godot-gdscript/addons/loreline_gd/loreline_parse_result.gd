class_name LorelineParseResult
extends RefCounted

## One-shot await target returned by Loreline.parse().
## Emission is deferred to the next process frame so awaiters connect first.

signal completed(script)
