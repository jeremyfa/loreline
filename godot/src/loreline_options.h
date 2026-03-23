#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#ifdef LORELINE_USE_JS
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/classes/java_script_bridge.hpp>
#endif

using namespace godot;

#include "loreline_script.h"

class LorelineOptions : public RefCounted {
	GDCLASS(LorelineOptions, RefCounted);

private:
	bool _strict_access;
	Dictionary _functions;       // String → Callable (sync functions)
	Dictionary _async_functions; // String → Callable (async functions: receives resolve Callable)
	Ref<LorelineScript> _translations_script;

#ifndef LORELINE_USE_JS
	struct FunctionCallContext {
		LorelineOptions *options;
		String function_name;
		bool is_async;
	};

	static Loreline_Value _on_custom_function(
			Loreline_Interpreter *interp,
			const Loreline_Value *args,
			int argCount,
			void *userData);

	static void _on_async_custom_function(
			Loreline_Interpreter *interp,
			const Loreline_Value *args,
			int argCount,
			Loreline_AsyncResolve *resolve,
			void *userData);
#endif

protected:
	static void _bind_methods();

public:
	LorelineOptions();
	~LorelineOptions();

	void set_strict_access(bool strict);
	bool get_strict_access() const;

	void set_function(const String &name, const Callable &fn);
	void set_async_function(const String &name, const Callable &fn);
	void remove_function(const String &name);

	void set_translations(const Ref<LorelineScript> &translations_script);

	const Dictionary &get_functions() const { return _functions; }
	const Dictionary &get_async_functions() const { return _async_functions; }

#ifndef LORELINE_USE_JS
	Loreline_InterpreterOptions *build_native_options();
	void release_native_contexts();
#endif

#ifdef LORELINE_USE_JS
	int _translations_js_id = 0;

	// Registry: maps interp JS ID → (function name → Callable)
	static HashMap<int, Dictionary> _js_function_registry;
	static HashMap<int, Dictionary> _js_async_function_registry;

	static void register_js_functions(int interp_id, const Dictionary &functions, const Dictionary &async_functions);
	static void unregister_js_functions(int interp_id);
#endif

	String build_js_options_json() const;
};
