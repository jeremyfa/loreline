#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#include "loreline_interpreter.h"

using namespace godot;

class LorelineOptions;

class LorelineScript : public RefCounted {
	GDCLASS(LorelineScript, RefCounted);

	friend class Loreline;

private:
#ifdef LORELINE_USE_JS
	int _js_id; // ID in the JS object store
#else
	Loreline_Script *_script;
#endif

protected:
	static void _bind_methods();

public:
	LorelineScript();
	~LorelineScript();

	Ref<LorelineInterpreter> play(const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());
	Ref<LorelineInterpreter> resume(const String &save_data, const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());

	Dictionary extract_translations();
	String print_script();
	String to_json(bool pretty = false);
	static Ref<LorelineScript> from_json(const String &json);
};
