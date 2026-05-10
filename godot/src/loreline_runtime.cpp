#include "loreline_runtime.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/callable_custom.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <atomic>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/window.hpp>

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/java_script_bridge.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include "loreline_js_bundle.h"
#include "loreline_js_bridge.h"
#include "loreline_js_utils.h"
#include "loreline_interpreter.h"
#endif

Loreline *Loreline::_singleton = nullptr;

#ifdef LORELINE_USE_JS
Vector<Callable> Loreline::_pending_parse_callbacks;
Vector<Callable> Loreline::_pending_load_locale_callbacks;
#endif

Loreline *Loreline::shared() {
	if (_singleton) return _singleton;

	_singleton = memnew(Loreline);
	_singleton->set_name("Loreline");

	// Add to scene tree root so the node gets PROCESS notifications
	// and survives scene changes. Must be immediate (not deferred)
	// so the singleton is usable right away from GDScript _ready().
	SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
	if (tree && tree->get_root()) {
		tree->get_root()->add_child(_singleton);
	}

	// Initialize the runtime immediately
	if (!_singleton->_initialized) {
#ifdef LORELINE_USE_JS
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval(String::utf8(LORELINE_JS_BUNDLE), true);
			js->eval(String::utf8(LORELINE_JS_BRIDGE), true);
			_singleton->_js_loaded = true;
		}
#else
#ifdef ANDROID_ENABLED
		Loreline_createThread();
#endif
		Loreline_init();
		Loreline_update(0);
#endif
		_singleton->_initialized = true;
		_singleton->set_process(true);
	}

	return _singleton;
}

Loreline::Loreline()
		: _initialized(false)
#ifdef LORELINE_USE_JS
		, _js_loaded(false)
#endif
{
#ifndef LORELINE_USE_JS
	_file_ctx.runtime = this;
#endif
}

Loreline::~Loreline() {
}

void Loreline::_bind_methods() {
	ClassDB::bind_static_method("Loreline", D_METHOD("shared"), &Loreline::shared);
	ClassDB::bind_method(D_METHOD("parse", "source", "on_parsed", "file_path", "file_handler"), &Loreline::parse, DEFVAL(""), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("provide_file", "path", "content"), &Loreline::provide_file);
	ClassDB::bind_method(D_METHOD("load_locale", "locale", "script", "on_loaded", "file_path", "file_handler"), &Loreline::load_locale, DEFVAL(""), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("play", "script", "on_dialogue", "on_choice", "on_finished", "beat_name", "options"), &Loreline::play, DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));
	ClassDB::bind_method(D_METHOD("resume", "script", "on_dialogue", "on_choice", "on_finished", "save_data", "beat_name", "options"), &Loreline::resume, DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));

	ADD_SIGNAL(MethodInfo("file_requested",
			PropertyInfo(Variant::STRING, "path")));
}

void Loreline::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			// Already initialized by shared() — nothing to do
			if (_initialized) break;

			if (_singleton && _singleton != this) {
				UtilityFunctions::push_warning("Loreline: shared instance already exists, this node will be ignored.");
				return;
			}
			_singleton = this;

#ifdef LORELINE_USE_JS
			if (!_js_loaded) {
				JavaScriptBridge *js = JavaScriptBridge::get_singleton();
				if (js) {
					js->eval(String::utf8(LORELINE_JS_BUNDLE), true);
					js->eval(String::utf8(LORELINE_JS_BRIDGE), true);
					_js_loaded = true;
				}
			}
#else
#ifdef ANDROID_ENABLED
			Loreline_createThread();
#endif
			Loreline_init();
			Loreline_update(0); // Enable deferred callback mode
#endif
			_initialized = true;
			set_process(true);
		} break;

		case NOTIFICATION_PROCESS: {
			if (_initialized) {
#ifdef LORELINE_USE_JS
				JavaScriptBridge *js = JavaScriptBridge::get_singleton();
				if (js) {
					String code = String("_lorelineBridge.update(") + String::num(get_process_delta_time()) + String(")");
					js->eval(code, true);
					LorelineInterpreter::_poll_js_events();
				}
#else
				Loreline_update(get_process_delta_time());
#endif
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			if (_singleton == this && _initialized) {
#ifndef LORELINE_USE_JS
				Loreline_dispose();
#endif
				_initialized = false;
				_singleton = nullptr;
			}
		} break;
	}
}

#ifndef LORELINE_USE_JS

// CallableCustom that wraps a Loreline_FileRequest. Hands a Godot Callable to
// the user; when invoked with the file content (or null), fires
// Loreline_provideFile, which consumes the request token. Mirrors the
// LorelineAdvanceCallable / LorelineSelectCallable pattern.
class LorelineFileProvideCallable : public CallableCustom {
	mutable Loreline_FileRequest *_request;
	mutable std::atomic<bool> _provided;

public:
	LorelineFileProvideCallable(Loreline_FileRequest *request)
			: _request(request), _provided(false) {}

	~LorelineFileProvideCallable() {
		bool expected = false;
		if (_provided.compare_exchange_strong(expected, true)) {
			// Host dropped the Callable without calling provide — release the
			// request with NULL content so Loreline can finish cleanly.
			if (_request) {
				Loreline_provideFile(_request, Loreline_String());
				_request = nullptr;
			}
		}
	}

	uint32_t hash() const override { return (uint32_t)(uintptr_t)this; }
	String get_as_text() const override { return "LorelineFileProvide"; }
	ObjectID get_object() const override { return ObjectID(); }

	static bool compare_equal(const CallableCustom *a, const CallableCustom *b) { return a == b; }
	static bool compare_less(const CallableCustom *a, const CallableCustom *b) { return a < b; }
	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }

	void call(const Variant **p_arguments, int p_argcount, Variant &r_return_value, GDExtensionCallError &r_call_error) const override {
		r_call_error.error = GDEXTENSION_CALL_OK;

		bool expected = false;
		if (!_provided.compare_exchange_strong(expected, true)) {
			UtilityFunctions::push_error("LorelineFileProvide: provide called more than once — ignoring");
			return;
		}

		Loreline_String content;
		if (p_argcount >= 1 && p_arguments[0]->get_type() == Variant::STRING) {
			String s = *p_arguments[0];
			CharString utf8 = s.utf8();
			content = Loreline_String(utf8.get_data());
			Loreline_provideFile(_request, content);
		} else {
			// null / not-found
			Loreline_provideFile(_request, Loreline_String());
		}
		_request = nullptr;
	}
};

void Loreline::_on_file_request(
		Loreline_String path,
		Loreline_FileRequest *request,
		void *userData) {
	FileRequestContext *ctx = static_cast<FileRequestContext *>(userData);
	String godot_path = String::utf8(path.c_str());

	// Check if the user has provided an override via provide_file()
	if (ctx->file_overrides.has(godot_path)) {
		String content = ctx->file_overrides[godot_path];
		CharString utf8 = content.utf8();
		Loreline_provideFile(request, Loreline_String(utf8.get_data()));
		return;
	}

	// Try the user-provided file handler callable (async-capable):
	// hand it a Callable that wraps the request token. The user calls it
	// (sync or async) with the file content (or null for not-found).
	if (ctx->file_handler.is_valid()) {
		Callable provide_callable(memnew(LorelineFileProvideCallable(request)));
		ctx->file_handler.call(godot_path, provide_callable);
		// Fire-and-forget: the Callable's lifetime owns the request from here.
		// If the user never invokes provide, the Callable's destructor will
		// release the request with NULL content.
		return;
	}

	// Emit signal to allow user to override
	ctx->runtime->emit_signal("file_requested", godot_path);

	// Check again after signal (user may have called provide_file in handler)
	if (ctx->file_overrides.has(godot_path)) {
		String content = ctx->file_overrides[godot_path];
		CharString utf8 = content.utf8();
		Loreline_provideFile(request, Loreline_String(utf8.get_data()));
		return;
	}

	// Default: read from Godot resource system
	// The path from Loreline is relative to the source file, so prepend base_dir
	String full_path = godot_path;
	if (!full_path.begins_with("res://") && !full_path.begins_with("/")) {
		full_path = ctx->base_dir.path_join(godot_path);
	}

	if (FileAccess::file_exists(full_path)) {
		Ref<FileAccess> file = FileAccess::open(full_path, FileAccess::READ);
		if (file.is_valid()) {
			String content = file->get_as_text();
			file->close();
			CharString utf8 = content.utf8();
			Loreline_provideFile(request, Loreline_String(utf8.get_data()));
			return;
		}
	}

	// File not found — provide null
	Loreline_provideFile(request, Loreline_String());
}
#endif

#ifndef LORELINE_USE_JS
// Per-call binding for the async parse completion thunk.
struct ParseCompletionBinding {
	Callable on_parsed;
};

void Loreline::_on_parse_completion(Loreline_Script *script, void *userData) {
	ParseCompletionBinding *binding = static_cast<ParseCompletionBinding *>(userData);
	Ref<LorelineScript> wrapper;
	if (script) {
		wrapper.instantiate();
		wrapper->_script = script;
	}
	if (binding->on_parsed.is_valid()) {
		binding->on_parsed.call(wrapper);
	}
	delete binding;
}
#endif

void Loreline::parse(const String &source, const Callable &on_parsed, const String &file_path, const Callable &file_handler) {
	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		if (on_parsed.is_valid()) on_parsed.call(Variant());
		return;
	}

	// Convenience: if source looks like a resource path and no file_path given, load it
	String actual_source = source;
	String actual_file_path = file_path;
	if (actual_file_path.is_empty() &&
			(source.begins_with("res://") || source.begins_with("user://"))) {
		actual_file_path = source;
		Ref<FileAccess> file = FileAccess::open(actual_file_path, FileAccess::READ);
		if (file.is_valid()) {
			actual_source = file->get_as_text();
			file->close();
		} else {
			UtilityFunctions::push_error("Loreline: failed to open " + actual_file_path);
			if (on_parsed.is_valid()) on_parsed.call(Variant());
			return;
		}
	}

#ifdef LORELINE_USE_JS
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		UtilityFunctions::push_error("Loreline: JavaScriptBridge not available.");
		if (on_parsed.is_valid()) on_parsed.call(Variant());
		return;
	}

	// Build JS call to parse. Pass null fileCallback (the C++ side handles
	// file requests via the per-frame _process polling now).
	String escaped_source = loreline_escape_js(actual_source);
	String escaped_path = loreline_escape_js(actual_file_path);

	String js_code;
	if (!actual_file_path.is_empty()) {
		js_code = "_lorelineBridge.parse('" + escaped_source + "','" + escaped_path + "',null)";
	} else {
		js_code = "_lorelineBridge.parse('" + escaped_source + "',null,null)";
	}

	Variant result = js->eval(js_code, true);
	int script_id = result;

	if (script_id > 0) {
		// Synchronous completion (no imports / sync handler hit)
		Ref<LorelineScript> script;
		script.instantiate();
		script->_js_id = script_id;
		if (on_parsed.is_valid()) on_parsed.call(script);
		return;
	}
	if (script_id == -1) {
		// Async — completion will arrive via _process draining events.
		_pending_parse_callbacks.push_back(on_parsed);
		return;
	}
	UtilityFunctions::push_error("Loreline: failed to parse script.");
	if (on_parsed.is_valid()) on_parsed.call(Variant());

#else
	CharString source_utf8 = actual_source.utf8();
	CharString path_utf8 = actual_file_path.utf8();

	// Set up the base directory for resolving imports
	if (!actual_file_path.is_empty()) {
		_file_ctx.base_dir = actual_file_path.get_base_dir();
	} else {
		_file_ctx.base_dir = "res://";
	}
	_file_ctx.file_overrides.clear();
	_file_ctx.file_handler = file_handler;

	Loreline_String loreline_source = Loreline_String(source_utf8.get_data());
	Loreline_String loreline_path = actual_file_path.is_empty()
			? Loreline_String()
			: Loreline_String(path_utf8.get_data());

	ParseCompletionBinding *binding = new ParseCompletionBinding{ on_parsed };
	Loreline_parseAsync(
			loreline_source,
			loreline_path,
			_on_file_request,
			static_cast<void *>(&_file_ctx),
			_on_parse_completion,
			binding);
#endif
}

void Loreline::provide_file(const String &path, const String &content) {
#ifdef LORELINE_USE_JS
	_file_overrides[path] = content;
#else
	_file_ctx.file_overrides[path] = content;
#endif
}

#ifndef LORELINE_USE_JS
struct LoadLocaleCompletionBinding {
	Callable on_loaded;
};

void Loreline::_on_load_locale_completion(Loreline_Translations *translations, void *userData) {
	LoadLocaleCompletionBinding *binding = static_cast<LoadLocaleCompletionBinding *>(userData);
	Ref<LorelineTranslations> wrapper;
	if (translations) {
		wrapper.instantiate();
		wrapper->_handle = translations;
	}
	if (binding->on_loaded.is_valid()) {
		binding->on_loaded.call(wrapper);
	}
	delete binding;
}
#endif

void Loreline::load_locale(const String &locale, const Ref<LorelineScript> &script, const Callable &on_loaded, const String &file_path, const Callable &file_handler) {
	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		if (on_loaded.is_valid()) on_loaded.call(Variant());
		return;
	}
	if (script.is_null()) {
		UtilityFunctions::push_error("Loreline.load_locale: script is null.");
		if (on_loaded.is_valid()) on_loaded.call(Variant());
		return;
	}

#ifdef LORELINE_USE_JS
	if (script->_js_id == 0) {
		UtilityFunctions::push_error("Loreline.load_locale: script has no JS id.");
		if (on_loaded.is_valid()) on_loaded.call(Variant());
		return;
	}
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		if (on_loaded.is_valid()) on_loaded.call(Variant());
		return;
	}

	String locale_escaped = loreline_escape_js(locale);
	String fp_escaped = loreline_escape_js(file_path);

	String js_code = String("_lorelineBridge.loadLocale(") +
		String::num_int64(script->_js_id) + ",'" + locale_escaped + "','" + fp_escaped + "',null)";

	Variant result = js->eval(js_code, true);
	int translations_id = (int)result;

	if (translations_id > 0) {
		Ref<LorelineTranslations> wrapper;
		wrapper.instantiate();
		wrapper->_js_id = translations_id;
		if (on_loaded.is_valid()) on_loaded.call(wrapper);
		return;
	}
	if (translations_id == -1) {
		_pending_load_locale_callbacks.push_back(on_loaded);
		return;
	}
	UtilityFunctions::push_error("Loreline.load_locale: failed for locale '" + locale + "'.");
	if (on_loaded.is_valid()) on_loaded.call(Variant());
#else
	if (!script->_script) {
		UtilityFunctions::push_error("Loreline.load_locale: script has no underlying handle.");
		if (on_loaded.is_valid()) on_loaded.call(Variant());
		return;
	}

	// Re-use the runtime's file handler context for resolving translation files
	_file_ctx.file_handler = file_handler;

	CharString locale_utf8 = locale.utf8();
	CharString fp_utf8 = file_path.utf8();

	Loreline_String loreline_locale = Loreline_String(locale_utf8.get_data());
	Loreline_String loreline_path = file_path.is_empty()
			? Loreline_String()
			: Loreline_String(fp_utf8.get_data());

	LoadLocaleCompletionBinding *binding = new LoadLocaleCompletionBinding{ on_loaded };
	Loreline_loadLocaleAsync(
			loreline_locale,
			script->_script,
			loreline_path,
			_on_file_request,
			static_cast<void *>(&_file_ctx),
			_on_load_locale_completion,
			binding);
#endif
}

Ref<LorelineInterpreter> Loreline::play(const Ref<LorelineScript> &script, const Callable &on_dialogue, const Callable &on_choice, const Callable &on_finished, const String &beat_name, const Ref<LorelineOptions> &options) {
	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		return Ref<LorelineInterpreter>();
	}
	if (script.is_null()) {
		UtilityFunctions::push_error("Loreline: script is null.");
		return Ref<LorelineInterpreter>();
	}
	Ref<LorelineInterpreter> interp = script->play(beat_name, options);
	if (interp.is_valid()) {
		_retain_interpreter(interp);
		if (on_dialogue.is_valid()) interp->connect("dialogue", on_dialogue);
		if (on_choice.is_valid()) interp->connect("choice", on_choice);
		if (on_finished.is_valid()) interp->connect("finished", on_finished);
	}
	return interp;
}

Ref<LorelineInterpreter> Loreline::resume(const Ref<LorelineScript> &script, const Callable &on_dialogue, const Callable &on_choice, const Callable &on_finished, const String &save_data, const String &beat_name, const Ref<LorelineOptions> &options) {
	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		return Ref<LorelineInterpreter>();
	}
	if (script.is_null()) {
		UtilityFunctions::push_error("Loreline: script is null.");
		return Ref<LorelineInterpreter>();
	}
	Ref<LorelineInterpreter> interp = script->resume(save_data, beat_name, options);
	if (interp.is_valid()) {
		_retain_interpreter(interp);
		if (on_dialogue.is_valid()) interp->connect("dialogue", on_dialogue);
		if (on_choice.is_valid()) interp->connect("choice", on_choice);
		if (on_finished.is_valid()) interp->connect("finished", on_finished);
	}
	return interp;
}

void Loreline::_retain_interpreter(const Ref<LorelineInterpreter> &interp) {
	_active_interpreters.push_back(interp);
}

void Loreline::_release_interpreter(LorelineInterpreter *interp) {
	for (int i = 0; i < _active_interpreters.size(); i++) {
		if (_active_interpreters[i].ptr() == interp) {
			_active_interpreters.remove_at(i);
			return;
		}
	}
}

void Loreline::_release_active_interpreter(LorelineInterpreter *interp) {
	if (_singleton) {
		_singleton->_release_interpreter(interp);
	}
}
