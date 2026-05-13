#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

/**
 * One-shot result object returned by `Loreline.parse()`.
 *
 * Emits a `completed(script)` signal exactly once when the parse finishes.
 * Callers typically `await` the signal:
 *
 *     var script = await loreline.parse("res://story.lor")
 *
 * The instance is kept alive by the Loreline singleton until the signal fires.
 */
class LorelineParseResult : public RefCounted {
	GDCLASS(LorelineParseResult, RefCounted);

protected:
	static void _bind_methods() {
		ADD_SIGNAL(MethodInfo("completed",
				PropertyInfo(Variant::OBJECT, "script")));
	}
};
