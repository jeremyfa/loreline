#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "Loreline.h"
#include "loreline_interpreter.h"

using namespace godot;

class LorelineScript : public RefCounted {
	GDCLASS(LorelineScript, RefCounted);

	friend class LorelineRuntime;

private:
	Loreline_Script *_script;

protected:
	static void _bind_methods();

public:
	LorelineScript();
	~LorelineScript();

	Ref<LorelineInterpreter> play(const String &beat_name = "");
	Ref<LorelineInterpreter> resume(const String &save_data, const String &beat_name = "");

	Dictionary extract_translations();
	String print_script();
	String to_json(bool pretty = false);
	static Ref<LorelineScript> from_json(const String &json);
};
