#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

/**
 * One-shot result object returned by `Loreline.load_locale()`.
 *
 * Emits a `completed(translations)` signal exactly once when the locale's
 * translation files have been resolved across the script's import tree.
 * Callers typically `await` the signal:
 *
 *     var translations = await loreline.load_locale("fr", script)
 *
 * The instance is kept alive by the Loreline singleton until the signal fires.
 */
class LorelineLoadLocaleResult : public RefCounted {
	GDCLASS(LorelineLoadLocaleResult, RefCounted);

protected:
	static void _bind_methods() {
		ADD_SIGNAL(MethodInfo("completed",
				PropertyInfo(Variant::OBJECT, "translations")));
	}
};
