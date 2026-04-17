#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <vector>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#ifdef LORELINE_USE_JS
#include <godot_cpp/templates/hash_map.hpp>
#endif

using namespace godot;

class LorelineOptions;
#ifndef LORELINE_USE_JS
struct LorelineFunctionCallContext;
#endif

class LorelineInterpreter : public RefCounted {
	GDCLASS(LorelineInterpreter, RefCounted);

	friend class LorelineScript;
	friend class Loreline;
	friend class LorelineOptions;
	friend class LorelineResolveCallable;

private:
#ifdef LORELINE_USE_JS
	int _js_id; // ID in the JS object store

	// Registry of active interpreters by JS ID, for event dispatch
	static HashMap<int, LorelineInterpreter *> _js_registry;

	// Poll JS event queue and dispatch signals to registered interpreters
	static void _poll_js_events();
#else
	Loreline_Interpreter *_interp;
	Variant _options_ref; // Retained so LorelineFunctionCallContext->options stays valid
	std::vector<LorelineFunctionCallContext *> _fn_contexts; // owned — freed in destructor
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

	// Interpreter-level retain/release passed to Loreline_play/resume.
	// userData is this wrapper (set as interp.ptr() when calling play).
	// Every LORELINE_BEGIN_DISPATCH_OUT site in the linc wrapper invokes
	// these around its queued lambda, so queued callbacks always outlive
	// their interpreter.
	static Loreline_Retainer *_retain_interpreter(void *userData);
	static void _release_interpreter(Loreline_Retainer *retainer);

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

// Builds the `resolve` Callable passed as the third argument to a user's
// async custom function. Invoking the Callable resumes the interpreter;
// dropping it without invoking cancels the async call without resuming.
#ifndef LORELINE_USE_JS
Callable loreline_make_resolve_callable(Loreline_AsyncResolve *resolve, const Ref<LorelineInterpreter> &interp);
#else
Callable loreline_make_resolve_callable(
		int call_id,
		const Ref<LorelineInterpreter> &interp);
#endif
