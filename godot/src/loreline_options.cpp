#include "loreline_options.h"
#include "loreline_interpreter.h"

#include <godot_cpp/variant/utility_functions.hpp>

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/json.hpp>
#include <emscripten.h>
#endif

LorelineOptions::LorelineOptions()
		: _strict_access(false) {
}

LorelineOptions::~LorelineOptions() {
#ifdef LORELINE_USE_JS
	if (_translations_js_id != 0) {
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.releaseTranslations(" + String::num_int64(_translations_js_id) + ")", true);
		}
		_translations_js_id = 0;
	}
#endif
}

#ifdef LORELINE_USE_JS

HashMap<int, Dictionary> LorelineOptions::_js_function_registry;
HashMap<int, Dictionary> LorelineOptions::_js_async_function_registry;

void LorelineOptions::register_js_functions(int interp_id, const Dictionary &functions, const Dictionary &async_functions) {
	if (functions.size() > 0) {
		_js_function_registry[interp_id] = functions;
	}
	if (async_functions.size() > 0) {
		_js_async_function_registry[interp_id] = async_functions;
	}
}

void LorelineOptions::unregister_js_functions(int interp_id) {
	_js_function_registry.erase(interp_id);
	_js_async_function_registry.erase(interp_id);
}

// Called synchronously from JS via Module.ccall when a custom function is invoked.
// Returns the result as a JSON string (caller must free with loreline_free_string).
static char *s_ccall_result = nullptr;

extern "C" EMSCRIPTEN_KEEPALIVE
const char *loreline_call_host_function(int interp_id, const char *name, const char *args_json) {
	// Free previous result
	if (s_ccall_result) {
		free(s_ccall_result);
		s_ccall_result = nullptr;
	}

	String func_name = String::utf8(name);

	// Look up the function registry for this interpreter
	Dictionary *funcs = LorelineOptions::_js_function_registry.getptr(interp_id);
	if (!funcs) return "null";

	Callable fn = funcs->get(func_name, Callable());
	if (!fn.is_valid()) return "null";

	// Parse args JSON array
	Array gdArgs;
	if (args_json && args_json[0] != '\0') {
		Ref<JSON> json_parser;
		json_parser.instantiate();
		if (json_parser->parse(String::utf8(args_json)) == OK) {
			Variant parsed = json_parser->get_data();
			if (parsed.get_type() == Variant::ARRAY) {
				gdArgs = parsed;
			}
		}
	}

	// Call the GDScript function: fn(interp_placeholder, args_array)
	Variant result = fn.call(Variant(), gdArgs);

	// Convert result to JSON string for JS
	String result_json;
	switch (result.get_type()) {
		case Variant::INT:
			result_json = String::num_int64(result);
			break;
		case Variant::FLOAT:
			result_json = String::num(result);
			break;
		case Variant::BOOL:
			result_json = ((bool)result) ? "true" : "false";
			break;
		case Variant::STRING: {
			// JSON-encode the string
			String s = result;
			s = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
			result_json = "\"" + s + "\"";
			break;
		}
		default:
			result_json = "null";
			break;
	}

	// Copy to a malloc'd buffer that persists after return
	CharString utf8 = result_json.utf8();
	s_ccall_result = (char *)malloc(utf8.length() + 1);
	memcpy(s_ccall_result, utf8.get_data(), utf8.length() + 1);
	return s_ccall_result;
}

#endif // LORELINE_USE_JS

void LorelineOptions::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_strict_access", "strict"), &LorelineOptions::set_strict_access);
	ClassDB::bind_method(D_METHOD("get_strict_access"), &LorelineOptions::get_strict_access);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "strict_access"), "set_strict_access", "get_strict_access");

	ClassDB::bind_method(D_METHOD("set_function", "name", "callable"), &LorelineOptions::set_function);
	ClassDB::bind_method(D_METHOD("set_async_function", "name", "callable"), &LorelineOptions::set_async_function);
	ClassDB::bind_method(D_METHOD("remove_function", "name"), &LorelineOptions::remove_function);
	ClassDB::bind_method(D_METHOD("set_translations", "translations_script"), &LorelineOptions::set_translations);
}

void LorelineOptions::set_strict_access(bool strict) {
	_strict_access = strict;
}

bool LorelineOptions::get_strict_access() const {
	return _strict_access;
}

void LorelineOptions::set_function(const String &name, const Callable &fn) {
	_async_functions.erase(name);
	_functions[name] = fn;
}

void LorelineOptions::set_async_function(const String &name, const Callable &fn) {
	_functions.erase(name);
	_async_functions[name] = fn;
}

void LorelineOptions::remove_function(const String &name) {
	_functions.erase(name);
	_async_functions.erase(name);
}

void LorelineOptions::set_translations(const Ref<LorelineScript> &translations_script) {
	_translations_script = translations_script;

#ifdef LORELINE_USE_JS
	// Release previous translations JS object if any
	if (_translations_js_id != 0) {
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.releaseTranslations(" + String::num_int64(_translations_js_id) + ")", true);
		}
		_translations_js_id = 0;
	}

	// Extract translations from the script on the JS side
	if (_translations_script.is_valid() && _translations_script->_js_id != 0) {
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			Variant result = js->eval("_lorelineBridge.extractTranslations(" +
					String::num_int64(_translations_script->_js_id) + ")", true);
			_translations_js_id = (int)result;
		}
	}
#endif
}

#ifndef LORELINE_USE_JS

Loreline_Value LorelineOptions::_on_custom_function(
		Loreline_Interpreter *interp,
		const Loreline_Value *args,
		int argCount,
		void *userData) {
	LorelineFunctionCallContext *ctx = static_cast<LorelineFunctionCallContext *>(userData);
	if (!ctx || !ctx->options) return Loreline_Value::null_val();

	Callable fn = ctx->options->_functions.get(ctx->function_name, Callable());
	if (!fn.is_valid()) return Loreline_Value::null_val();

	// Build wrapper Ref FIRST (guard + source for the Variant we pass to GDScript).
	Ref<LorelineInterpreter> wrapper_ref(ctx->wrapper);
	Variant wrapper_variant = ctx->wrapper ? Variant(wrapper_ref) : Variant();

	Array gdArgs;
	for (int i = 0; i < argCount; i++) {
		gdArgs.append(LorelineInterpreter::_value_to_variant(args[i]));
	}

	Variant result = fn.call(wrapper_variant, gdArgs);
	return LorelineInterpreter::_variant_to_value(result);
}

void LorelineOptions::_on_async_custom_function(
		Loreline_Interpreter *interp,
		const Loreline_Value *args,
		int argCount,
		Loreline_AsyncResolve *resolve,
		void *userData) {
	LorelineFunctionCallContext *ctx = static_cast<LorelineFunctionCallContext *>(userData);
	if (!ctx || !ctx->options) {
		Loreline_resolveAsync(resolve, Loreline_Value::null_val());
		return;
	}

	Callable fn = ctx->options->_async_functions.get(ctx->function_name, Callable());
	if (!fn.is_valid()) {
		Loreline_resolveAsync(resolve, Loreline_Value::null_val());
		return;
	}

	// Build wrapper Ref FIRST (guard + source for the resolve Callable and the interp arg).
	Ref<LorelineInterpreter> wrapper_ref(ctx->wrapper);
	Variant wrapper_variant = ctx->wrapper ? Variant(wrapper_ref) : Variant();

	Array gdArgs;
	for (int i = 0; i < argCount; i++) {
		gdArgs.append(LorelineInterpreter::_value_to_variant(args[i]));
	}

	// Build the resolve Callable. It owns the Loreline_AsyncResolve handle
	// and holds a Ref<LorelineInterpreter> so retaining resolve keeps the
	// interpreter alive across the async pause.
	Callable resolve_callable = loreline_make_resolve_callable(resolve, wrapper_ref);

	fn.call(wrapper_variant, gdArgs, resolve_callable);
}

Loreline_InterpreterOptions *LorelineOptions::build_native_options(
		LorelineInterpreter *wrapper,
		std::vector<LorelineFunctionCallContext *> &out_contexts) {
	Loreline_InterpreterOptions *opts = Loreline_createOptions();

	if (_strict_access) {
		Loreline_optionsSetStrictAccess(opts, true);
	}

	// Extract and set translations if a translation script is provided
	if (_translations_script.is_valid() && _translations_script->_script) {
		Loreline_Translations *translations = Loreline_extractTranslations(_translations_script->_script);
		if (translations) {
			Loreline_optionsSetTranslations(opts, translations);
			Loreline_releaseTranslations(translations);
		}
	}

	// Register sync functions
	Array funcNames = _functions.keys();
	for (int i = 0; i < funcNames.size(); i++) {
		String name = funcNames[i];
		CharString name_utf8 = name.utf8();

		LorelineFunctionCallContext *ctx = new LorelineFunctionCallContext();
		ctx->options = this;
		ctx->function_name = name;
		ctx->is_async = false;
		ctx->wrapper = wrapper;
		out_contexts.push_back(ctx);

		Loreline_optionsAddFunction(opts,
				Loreline_String(name_utf8.get_data()),
				_on_custom_function,
				static_cast<void *>(ctx));
	}

	// Register async functions
	Array asyncFuncNames = _async_functions.keys();
	for (int i = 0; i < asyncFuncNames.size(); i++) {
		String name = asyncFuncNames[i];
		CharString name_utf8 = name.utf8();

		LorelineFunctionCallContext *ctx = new LorelineFunctionCallContext();
		ctx->options = this;
		ctx->function_name = name;
		ctx->is_async = true;
		ctx->wrapper = wrapper;
		out_contexts.push_back(ctx);

		Loreline_optionsAddAsyncFunction(opts,
				Loreline_String(name_utf8.get_data()),
				_on_async_custom_function,
				static_cast<void *>(ctx));
	}

	return opts;
}

#endif // !LORELINE_USE_JS

String LorelineOptions::build_js_options_json() const {
	// Build JSON for JS bridge
	String json = "{";
	bool has_prev = false;

	if (_strict_access) {
		json += "\"strictAccess\":true";
		has_prev = true;
	}

	// Include function names so the JS bridge can create sync wrappers
	if (_functions.size() > 0) {
		if (has_prev) json += ",";
		json += "\"functions\":[";
		Array names = _functions.keys();
		for (int i = 0; i < names.size(); i++) {
			if (i > 0) json += ",";
			String name = names[i];
			json += "\"" + name.replace("\"", "\\\"") + "\"";
		}
		json += "]";
		has_prev = true;
	}

	// Include async function names
	if (_async_functions.size() > 0) {
		if (has_prev) json += ",";
		json += "\"asyncFunctions\":[";
		Array names = _async_functions.keys();
		for (int i = 0; i < names.size(); i++) {
			if (i > 0) json += ",";
			String name = names[i];
			json += "\"" + name.replace("\"", "\\\"") + "\"";
		}
		json += "]";
		has_prev = true;
	}

#ifdef LORELINE_USE_JS
	// Include translations JS object ID
	if (_translations_js_id != 0) {
		if (has_prev) json += ",";
		json += "\"translationsId\":" + String::num_int64(_translations_js_id);
		has_prev = true;
	}
#endif

	json += "}";
	return json;
}
