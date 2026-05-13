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
}

Loreline::~Loreline() {
}

void Loreline::_bind_methods() {
	ClassDB::bind_static_method("Loreline", D_METHOD("shared"), &Loreline::shared);
	ClassDB::bind_method(D_METHOD("parse", "source", "file_path", "file_handler"), &Loreline::parse, DEFVAL(""), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("load_locale", "locale", "script", "file_path", "file_handler"), &Loreline::load_locale, DEFVAL(""), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("play", "script", "on_dialogue", "on_choice", "on_finished", "beat_name", "options"), &Loreline::play, DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));
	ClassDB::bind_method(D_METHOD("resume", "script", "on_dialogue", "on_choice", "on_finished", "save_data", "beat_name", "options"), &Loreline::resume, DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));
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
				// Drain pending parse/load_locale emits AFTER the runtime/JS
				// poll has populated them. This way the user's await has had
				// at least one frame to connect before we fire the signal.
				_drain_pending_emits();
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			if (_singleton == this && _initialized) {
				// Release any pending emit refs cleanly; the underlying parse
				// pipeline is torn down by Loreline_dispose / JS bridge teardown.
				_pending_parse_emits.clear();
				_pending_load_locale_emits.clear();
#ifdef LORELINE_USE_JS
				_pending_parse_results.clear();
				_pending_load_locale_results.clear();
				// Free any in-flight JS file contexts left by parses or
				// load_locale calls that didn't complete before shutdown.
				for (KeyValue<int, JsFileContext *> &e : _js_file_contexts) {
					memdelete(e.value);
				}
				_js_file_contexts.clear();
#endif
#ifndef LORELINE_USE_JS
				Loreline_dispose();
#endif
				_initialized = false;
				_singleton = nullptr;
			}
		} break;
	}
}

void Loreline::_queue_parse_emit(const Ref<LorelineParseResult> &result, const Variant &script_arg) {
	PendingParseEmit pe;
	pe.result = result;
	pe.script_arg = script_arg;
	_pending_parse_emits.push_back(pe);
}

void Loreline::_queue_load_locale_emit(const Ref<LorelineLoadLocaleResult> &result, const Variant &translations_arg) {
	PendingLoadLocaleEmit pe;
	pe.result = result;
	pe.translations_arg = translations_arg;
	_pending_load_locale_emits.push_back(pe);
}

void Loreline::_drain_pending_emits() {
	if (!_pending_parse_emits.is_empty()) {
		Vector<PendingParseEmit> drain = _pending_parse_emits;
		_pending_parse_emits.clear();
		for (int i = 0; i < drain.size(); i++) {
			if (drain[i].result.is_valid()) {
				drain[i].result->emit_signal("completed", drain[i].script_arg);
			}
		}
	}
	if (!_pending_load_locale_emits.is_empty()) {
		Vector<PendingLoadLocaleEmit> drain = _pending_load_locale_emits;
		_pending_load_locale_emits.clear();
		for (int i = 0; i < drain.size(); i++) {
			if (drain[i].result.is_valid()) {
				drain[i].result->emit_signal("completed", drain[i].translations_arg);
			}
		}
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
	NativeFileContext *ctx = static_cast<NativeFileContext *>(userData);
	String godot_path = String::utf8(path.c_str());

	// 1. User-provided file handler (async-capable): hand it a Callable that
	// wraps the request token. The user calls it (sync or later) with the
	// file content (or null for not-found).
	if (ctx->file_handler.is_valid()) {
		Callable provide_callable(memnew(LorelineFileProvideCallable(request)));
		ctx->file_handler.call(godot_path, provide_callable);
		// Fire-and-forget: the Callable's lifetime owns the request from here.
		// If the user never invokes provide, the Callable's destructor will
		// release the request with NULL content.
		return;
	}

	// 2. Default: read from Godot resource system.
	// Path from Loreline is relative to the source file, so prepend base_dir.
	String full_path = godot_path;
	if (!full_path.begins_with("res://") && !full_path.begins_with("user://") && !full_path.begins_with("/")) {
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
// Per-call binding for the async parse completion thunk. Holds the result Ref
// (so the LorelineParseResult survives until the underlying async parse fires
// the completion, which may happen synchronously inside parse() itself,
// since Loreline_parseAsync may call back inline; see linc_Loreline.cpp:1033)
// AND owns the per-call NativeFileContext that was passed to
// Loreline_parseAsync as userData. The thunk frees both.
struct ParseCompletionBinding {
	Ref<LorelineParseResult> result;
	NativeFileContext *ctx;
};

void Loreline::_on_parse_completion(Loreline_Script *script, void *userData) {
	ParseCompletionBinding *binding = static_cast<ParseCompletionBinding *>(userData);
	Ref<LorelineScript> wrapper;
	if (script) {
		wrapper.instantiate();
		wrapper->_script = script;
	}
	if (Loreline::_singleton) {
		Loreline::_singleton->_queue_parse_emit(
				binding->result,
				wrapper.is_valid() ? Variant(wrapper) : Variant());
	}
	delete binding->ctx;
	delete binding;
}
#endif

Signal Loreline::parse(const String &source, const String &file_path, const Callable &file_handler) {
	Ref<LorelineParseResult> result;
	result.instantiate();
	Signal sig(result.ptr(), "completed");

	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		_queue_parse_emit(result, Variant());
		return sig;
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
			_queue_parse_emit(result, Variant());
			return sig;
		}
	}

	String base_dir = actual_file_path.is_empty()
			? String("res://")
			: actual_file_path.get_base_dir();

#ifdef LORELINE_USE_JS
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		UtilityFunctions::push_error("Loreline: JavaScriptBridge not available.");
		_queue_parse_emit(result, Variant());
		return sig;
	}

	JsFileContext *ctx = memnew(JsFileContext);
	ctx->base_dir = base_dir;
	ctx->file_handler = file_handler;
	int ctx_id = ++_next_js_file_ctx_id;
	_js_file_contexts[ctx_id] = ctx;

	String escaped_source = loreline_escape_js(actual_source);
	String escaped_path = loreline_escape_js(actual_file_path);

	String js_code;
	if (!actual_file_path.is_empty()) {
		js_code = "_lorelineBridge.parse('" + escaped_source + "','" + escaped_path + "',null,"
				+ String::num_int64(ctx_id) + ")";
	} else {
		js_code = "_lorelineBridge.parse('" + escaped_source + "',null,null,"
				+ String::num_int64(ctx_id) + ")";
	}

	Variant js_result = js->eval(js_code, true);
	int script_id = js_result;

	if (script_id > 0) {
		// Synchronous completion (no imports / sync handler hit). The JS
		// bridge also queued a parse_complete event with the same ctx_id,
		// which will free the ctx when drained. We push the script ref now
		// so the await resolves on the next process tick.
		Ref<LorelineScript> script_ref;
		script_ref.instantiate();
		script_ref->_js_id = script_id;
		_queue_parse_emit(result, script_ref);
		return sig;
	}
	if (script_id == -1) {
		// Async — completion will arrive via _poll_js_events draining events.
		_pending_parse_results.push_back(result);
		return sig;
	}

	// Error path: JS bridge returned 0 (caught exception). No completion
	// event will arrive, so free the ctx we just inserted.
	memdelete(_js_file_contexts[ctx_id]);
	_js_file_contexts.erase(ctx_id);
	UtilityFunctions::push_error("Loreline: failed to parse script.");
	_queue_parse_emit(result, Variant());
	return sig;

#else
	NativeFileContext *ctx = new NativeFileContext{ base_dir, file_handler };

	CharString source_utf8 = actual_source.utf8();
	CharString path_utf8 = actual_file_path.utf8();

	Loreline_String loreline_source = Loreline_String(source_utf8.get_data());
	Loreline_String loreline_path = actual_file_path.is_empty()
			? Loreline_String()
			: Loreline_String(path_utf8.get_data());

	ParseCompletionBinding *binding = new ParseCompletionBinding{ result, ctx };
	Loreline_parseAsync(
			loreline_source,
			loreline_path,
			_on_file_request,
			static_cast<void *>(ctx),
			_on_parse_completion,
			binding);
	return sig;
#endif
}

#ifndef LORELINE_USE_JS
struct LoadLocaleCompletionBinding {
	Ref<LorelineLoadLocaleResult> result;
	NativeFileContext *ctx;
};

void Loreline::_on_load_locale_completion(Loreline_Translations *translations, void *userData) {
	LoadLocaleCompletionBinding *binding = static_cast<LoadLocaleCompletionBinding *>(userData);
	Ref<LorelineTranslations> wrapper;
	if (translations) {
		wrapper.instantiate();
		wrapper->_handle = translations;
	}
	if (Loreline::_singleton) {
		Loreline::_singleton->_queue_load_locale_emit(
				binding->result,
				wrapper.is_valid() ? Variant(wrapper) : Variant());
	}
	delete binding->ctx;
	delete binding;
}
#endif

Signal Loreline::load_locale(const String &locale, const Ref<LorelineScript> &script, const String &file_path, const Callable &file_handler) {
	Ref<LorelineLoadLocaleResult> result;
	result.instantiate();
	Signal sig(result.ptr(), "completed");

	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		_queue_load_locale_emit(result, Variant());
		return sig;
	}
	if (script.is_null()) {
		UtilityFunctions::push_error("Loreline.load_locale: script is null.");
		_queue_load_locale_emit(result, Variant());
		return sig;
	}

	String base_dir = file_path.is_empty() ? String("res://") : file_path.get_base_dir();

#ifdef LORELINE_USE_JS
	if (script->_js_id == 0) {
		UtilityFunctions::push_error("Loreline.load_locale: script has no JS id.");
		_queue_load_locale_emit(result, Variant());
		return sig;
	}
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		_queue_load_locale_emit(result, Variant());
		return sig;
	}

	JsFileContext *ctx = memnew(JsFileContext);
	ctx->base_dir = base_dir;
	ctx->file_handler = file_handler;
	int ctx_id = ++_next_js_file_ctx_id;
	_js_file_contexts[ctx_id] = ctx;

	String locale_escaped = loreline_escape_js(locale);
	String fp_escaped = loreline_escape_js(file_path);

	String js_code = String("_lorelineBridge.loadLocale(") +
		String::num_int64(script->_js_id) + ",'" + locale_escaped + "','" + fp_escaped + "',null,"
		+ String::num_int64(ctx_id) + ")";

	Variant js_result = js->eval(js_code, true);
	int translations_id = (int)js_result;

	if (translations_id > 0) {
		Ref<LorelineTranslations> wrapper;
		wrapper.instantiate();
		wrapper->_js_id = translations_id;
		_queue_load_locale_emit(result, wrapper);
		return sig;
	}
	if (translations_id == -1) {
		_pending_load_locale_results.push_back(result);
		return sig;
	}

	// Error path: free the ctx we just inserted.
	memdelete(_js_file_contexts[ctx_id]);
	_js_file_contexts.erase(ctx_id);
	UtilityFunctions::push_error("Loreline.load_locale: failed for locale '" + locale + "'.");
	_queue_load_locale_emit(result, Variant());
	return sig;
#else
	if (!script->_script) {
		UtilityFunctions::push_error("Loreline.load_locale: script has no underlying handle.");
		_queue_load_locale_emit(result, Variant());
		return sig;
	}

	NativeFileContext *ctx = new NativeFileContext{ base_dir, file_handler };

	CharString locale_utf8 = locale.utf8();
	CharString fp_utf8 = file_path.utf8();

	Loreline_String loreline_locale = Loreline_String(locale_utf8.get_data());
	Loreline_String loreline_path = file_path.is_empty()
			? Loreline_String()
			: Loreline_String(fp_utf8.get_data());

	LoadLocaleCompletionBinding *binding = new LoadLocaleCompletionBinding{ result, ctx };
	Loreline_loadLocaleAsync(
			loreline_locale,
			script->_script,
			loreline_path,
			_on_file_request,
			static_cast<void *>(ctx),
			_on_load_locale_completion,
			binding);
	return sig;
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
