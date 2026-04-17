#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <vector>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#ifdef LORELINE_USE_JS
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/classes/java_script_bridge.hpp>
#endif

using namespace godot;

class LorelineInterpreter;
class LorelineOptions;

#include "loreline_script.h"

#ifndef LORELINE_USE_JS
// Per-function userData for the linc wrapper's custom-function closures.
// Lifetime is owned by LorelineInterpreter (via _fn_contexts) so contexts
// never outlive their interpreter — no dangling `wrapper` pointer risk.
struct LorelineFunctionCallContext {
	LorelineOptions *options;
	String function_name;
	bool is_async;
	LorelineInterpreter *wrapper;
};
#endif

class LorelineOptions : public RefCounted {
	GDCLASS(LorelineOptions, RefCounted);

private:
	bool _strict_access;
	Dictionary _functions;       // String → Callable (sync, signature: (interp, args))
	Dictionary _async_functions; // String → Callable (async, signature: (interp, args, resolve))
	Ref<LorelineScript> _translations_script;

#ifndef LORELINE_USE_JS
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

	// Register a synchronous custom function.
	// Callable signature: (interp, args: Array) -> Variant
	// The return value is the function's result in the .lor script.
	void set_function(const String &name, const Callable &fn);

	// Register an asynchronous custom function. Must be called in statement
	// context in the .lor script (not inside an expression or interpolation).
	// Callable signature: (interp, args: Array, resolve: Callable) -> void
	// The function does its async work (await, etc.) and then calls
	// `resolve.call()` to resume the interpreter. Calling resolve more than
	// once is a no-op. Dropping the resolve Callable without calling it
	// cancels the async call — the interpreter stays paused and is cleaned
	// up naturally when it is eventually released.
	void set_async_function(const String &name, const Callable &fn);

	void remove_function(const String &name);

	void set_translations(const Ref<LorelineScript> &translations_script);

	const Dictionary &get_functions() const { return _functions; }
	const Dictionary &get_async_functions() const { return _async_functions; }

#ifndef LORELINE_USE_JS
	// Builds native options and appends the allocated per-function contexts
	// to `out_contexts`. Caller (LorelineScript::play/resume) transfers
	// ownership to the resulting LorelineInterpreter, which frees them in
	// its destructor.
	Loreline_InterpreterOptions *build_native_options(
			LorelineInterpreter *wrapper,
			std::vector<LorelineFunctionCallContext *> &out_contexts);
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
