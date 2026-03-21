#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#ifdef LORELINE_USE_JS
#include <godot_cpp/templates/hash_map.hpp>
#endif

using namespace godot;

class LorelineInterpreter : public RefCounted {
	GDCLASS(LorelineInterpreter, RefCounted);

	friend class LorelineScript;
	friend class Loreline;

private:
#ifdef LORELINE_USE_JS
	int _js_id; // ID in the JS object store

	// Registry of active interpreters by JS ID, for event dispatch
	static HashMap<int, LorelineInterpreter *> _js_registry;

	// Poll JS event queue and dispatch signals to registered interpreters
	static void _poll_js_events();
#else
	Loreline_Interpreter *_interp;
	void (*_pending_advance)(void);
	void (*_pending_select)(int);

	static void _on_dialogue(
			Loreline_Interpreter *interpreter,
			Loreline_String character,
			Loreline_String text,
			const Loreline_TextTag *tags,
			int tagCount,
			void (*advance)(void),
			void *userData);

	static void _on_choice(
			Loreline_Interpreter *interpreter,
			const Loreline_ChoiceOption *options,
			int optionCount,
			void (*select)(int index),
			void *userData);

	static void _on_finish(
			Loreline_Interpreter *interpreter,
			void *userData);

	static Array _convert_tags(const Loreline_TextTag *tags, int tagCount);
	static Array _convert_options(const Loreline_ChoiceOption *options, int optionCount);
	static Variant _value_to_variant(const Loreline_Value &value);
	static Loreline_Value _variant_to_value(const Variant &variant);
#endif

protected:
	static void _bind_methods();

public:
	LorelineInterpreter();
	~LorelineInterpreter();

	void advance();
	void select(int index);

	void start(const String &beat_name);
	String save_state();
	void restore_state(const String &data);

	Variant get_character_field(const String &character, const String &field);
	void set_character_field(const String &character, const String &field, const Variant &value);

	Variant get_state_field(const String &field);
	void set_state_field(const String &field, const Variant &value);
	Variant get_top_level_state_field(const String &field);
	void set_top_level_state_field(const String &field, const Variant &value);
	Dictionary current_node();
};
