#include "loreline_runtime.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

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

	// Add to scene tree root so the node gets READY/PROCESS notifications
	// and survives scene changes
	SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
	if (tree && tree->get_root()) {
		tree->get_root()->call_deferred("add_child", _singleton);
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
	ClassDB::bind_method(D_METHOD("parse", "source", "file_path", "file_handler"), &Loreline::parse, DEFVAL(""), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("provide_file", "path", "content"), &Loreline::provide_file);
	ClassDB::bind_method(D_METHOD("play", "script", "on_dialogue", "on_choice", "on_finished", "beat_name", "options"), &Loreline::play, DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(Callable()), DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));
	ClassDB::bind_method(D_METHOD("resume", "script", "on_dialogue", "on_choice", "on_finished", "save_data", "beat_name", "options"), &Loreline::resume, DEFVAL(""), DEFVAL(Ref<LorelineOptions>()));

	ADD_SIGNAL(MethodInfo("file_requested",
			PropertyInfo(Variant::STRING, "path")));
}

void Loreline::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			if (_singleton && _singleton != this) {
				UtilityFunctions::push_warning("Loreline: shared instance already exists, this node will be ignored.");
				return;
			}
			_singleton = this;

			// If this node was placed in a scene (not via shared()), reparent
			// to root viewport so it survives scene changes
			if (get_parent() != get_tree()->get_root()) {
				call_deferred("reparent", get_tree()->get_root());
			}

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
void Loreline::_on_file_request(
		Loreline_String path,
		void (*provide)(Loreline_String content),
		void *userData) {
	FileRequestContext *ctx = static_cast<FileRequestContext *>(userData);
	String godot_path = String::utf8(path.c_str());

	// Check if the user has provided an override via provide_file()
	if (ctx->file_overrides.has(godot_path)) {
		String content = ctx->file_overrides[godot_path];
		CharString utf8 = content.utf8();
		provide(Loreline_String(utf8.get_data()));
		return;
	}

	// Try the user-provided file handler callable (if any)
	if (ctx->file_handler.is_valid()) {
		Variant result = ctx->file_handler.call(godot_path);
		if (result.get_type() == Variant::STRING) {
			String content = result;
			CharString utf8 = content.utf8();
			provide(Loreline_String(utf8.get_data()));
			return;
		}
	}

	// Emit signal to allow user to override
	ctx->runtime->emit_signal("file_requested", godot_path);

	// Check again after signal (user may have called provide_file in handler)
	if (ctx->file_overrides.has(godot_path)) {
		String content = ctx->file_overrides[godot_path];
		CharString utf8 = content.utf8();
		provide(Loreline_String(utf8.get_data()));
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
			provide(Loreline_String(utf8.get_data()));
			return;
		}
	}

	// File not found — provide null
	provide(Loreline_String());
}
#endif

Ref<LorelineScript> Loreline::parse(const String &source, const String &file_path, const Callable &file_handler) {
	if (!_initialized) {
		UtilityFunctions::push_error("Loreline: not initialized. Add this node to the scene tree first.");
		return Ref<LorelineScript>();
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
			return Ref<LorelineScript>();
		}
	}

#ifdef LORELINE_USE_JS
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		UtilityFunctions::push_error("Loreline: JavaScriptBridge not available.");
		return Ref<LorelineScript>();
	}

	// Build JS call to parse, with file callback if we have a path
	// Escape source and path for JS string literal
	String escaped_source = loreline_escape_js(actual_source);
	String escaped_path = loreline_escape_js(actual_file_path);

	String js_code;
	if (!actual_file_path.is_empty()) {
		// Create a file callback that reads from Godot resources
		// We pass file overrides and base_dir into JS scope
		String base_dir = actual_file_path.get_base_dir();
		String escaped_base = loreline_escape_js(base_dir);

		// Store file overrides as JSON for JS access
		String overrides_json = "{}";
		if (_file_overrides.size() > 0) {
			// Build JSON manually
			overrides_json = "{";
			Array keys = _file_overrides.keys();
			for (int i = 0; i < keys.size(); i++) {
				if (i > 0) overrides_json += ",";
				String key = keys[i];
				String val = _file_overrides[key];
				overrides_json += "'" + loreline_escape_js(key) + "':'" + loreline_escape_js(val) + "'";
			}
			overrides_json += "}";
		}

		js_code = String("(function(){") +
			"var overrides=" + overrides_json + ";" +
			"return _lorelineBridge.parse('" + escaped_source + "','" + escaped_path + "'," +
			"function(path){" +
				"if(overrides[path]!==undefined)return overrides[path];" +
				"return null;" +
			"});" +
			"})()";
	} else {
		js_code = "_lorelineBridge.parse('" + escaped_source + "',null,null)";
	}

	Variant result = js->eval(js_code, true);
	int script_id = result;

	if (script_id > 0) {
		// Synchronous completion (no imports or all overrides hit)
		Ref<LorelineScript> script;
		script.instantiate();
		script->_js_id = script_id;
		return script;
	} else if (script_id == -1) {
		// Async file loading — loop to handle file_request events
		String base_dir = actual_file_path.is_empty() ? String("res://") : actual_file_path.get_base_dir();
		int final_script_id = 0;
		int max_iterations = 1000; // Safety limit

		for (int iter = 0; iter < max_iterations; iter++) {
			Variant events_var = js->eval("_lorelineBridge.pollEvents()", true);
			String events_json = events_var;
			if (events_json.is_empty()) {
				continue;
			}

			// Parse the events JSON array manually
			// Events are: [{type:"file_request",requestId:N,path:"..."}, {type:"parse_complete",scriptId:N}]
			Ref<JSON> json_parser;
			json_parser.instantiate();
			Error err = json_parser->parse(events_json);
			if (err != OK) {
				break;
			}

			Array events = json_parser->get_data();
			bool done = false;
			for (int i = 0; i < events.size(); i++) {
				Dictionary evt = events[i];
				String type = evt["type"];

				if (type == "file_request") {
					int req_id = evt["requestId"];
					String req_path = evt["path"];

					String content_to_provide = "null";

					// Try user-provided file handler first
					if (file_handler.is_valid()) {
						Variant handler_result = file_handler.call(req_path);
						if (handler_result.get_type() == Variant::STRING) {
							String content = handler_result;
							String escaped = loreline_escape_js(content);
							content_to_provide = "'" + escaped + "'";
						}
					}

					// Fall back to FileAccess if handler didn't provide content
					if (content_to_provide == "null") {
						String full_path = req_path;
						if (!full_path.begins_with("res://") && !full_path.begins_with("/")) {
							full_path = base_dir.path_join(req_path);
						}

						if (FileAccess::file_exists(full_path)) {
							Ref<FileAccess> file = FileAccess::open(full_path, FileAccess::READ);
							if (file.is_valid()) {
								String content = file->get_as_text();
								file->close();
								String escaped = loreline_escape_js(content);
								content_to_provide = "'" + escaped + "'";
							}
						}
					}

					// Provide the file content — this may trigger more file_requests or parse_complete
					String provide_code = "_lorelineBridge.provideFile(" + String::num_int64(req_id) + "," + content_to_provide + ")";
					js->eval(provide_code, true);
				} else if (type == "parse_complete") {
					final_script_id = evt["scriptId"];
					done = true;
					break;
				}
			}
			if (done) break;
		}

		if (final_script_id > 0) {
			Ref<LorelineScript> script;
			script.instantiate();
			script->_js_id = final_script_id;
			return script;
		}

		UtilityFunctions::push_error("Loreline: failed to parse script (async file loading).");
		return Ref<LorelineScript>();
	}

	UtilityFunctions::push_error("Loreline: failed to parse script.");
	return Ref<LorelineScript>();

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

	Loreline_Script *raw = Loreline_parse(
			loreline_source,
			loreline_path,
			_on_file_request,
			static_cast<void *>(&_file_ctx));

	if (!raw) {
		UtilityFunctions::push_error("Loreline: failed to parse script.");
		return Ref<LorelineScript>();
	}

	Ref<LorelineScript> script;
	script.instantiate();
	script->_script = raw;
	return script;
#endif
}

void Loreline::provide_file(const String &path, const String &content) {
#ifdef LORELINE_USE_JS
	_file_overrides[path] = content;
#else
	_file_ctx.file_overrides[path] = content;
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
		if (on_dialogue.is_valid()) interp->connect("dialogue", on_dialogue);
		if (on_choice.is_valid()) interp->connect("choice", on_choice);
		if (on_finished.is_valid()) interp->connect("finished", on_finished);
	}
	return interp;
}
