#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/signal.hpp>
#include <godot_cpp/templates/hash_map.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#include "loreline_load_locale_result.h"
#include "loreline_options.h"
#include "loreline_parse_result.h"
#include "loreline_script.h"

using namespace godot;

#ifndef LORELINE_USE_JS
// Per-call native file-handler context. Allocated on the heap for each
// parse()/load_locale() call, passed as the Loreline_FileHandler userData, and
// freed in the matching completion thunk. Never shared between calls.
struct NativeFileContext {
	String base_dir;          // base directory for resolving relative imports
	Callable file_handler;    // optional user-provided file handler
};
#else
// Per-call JS file-handler context. Allocated on the heap for each
// parse()/load_locale() call, registered in Loreline::_js_file_contexts under
// a unique id that's threaded through the JS bridge so file_request events
// can be routed back to the right call. Freed in the corresponding
// completion event handler. Never shared between calls.
struct JsFileContext {
	String base_dir;
	Callable file_handler;
};
#endif

class Loreline : public Node {
	GDCLASS(Loreline, Node);

private:
	static Loreline *_singleton;
	bool _initialized;
	Vector<Ref<LorelineInterpreter>> _active_interpreters;

	// Pending completion emits, drained in NOTIFICATION_PROCESS so that any
	// awaiter (whose `connect` runs after parse()/load_locale() returns) has a
	// chance to subscribe before the signal fires. Without this deferral,
	// synchronous completions would emit before the await connects and the
	// awaiter would hang forever.
	struct PendingParseEmit {
		Ref<LorelineParseResult> result;
		Variant script_arg;
	};
	struct PendingLoadLocaleEmit {
		Ref<LorelineLoadLocaleResult> result;
		Variant translations_arg;
	};
	Vector<PendingParseEmit> _pending_parse_emits;
	Vector<PendingLoadLocaleEmit> _pending_load_locale_emits;

#ifdef LORELINE_USE_JS
	bool _js_loaded;

	friend class LorelineInterpreter;
public:
	// FIFO queues of pending parse / load_locale results awaiting a JS event
	// (parse_complete / load_locale_complete). When an event arrives, we pop
	// the oldest result and push it onto the corresponding pending-emits
	// vector for the next _process drain.
	Vector<Ref<LorelineParseResult>> _pending_parse_results;
	Vector<Ref<LorelineLoadLocaleResult>> _pending_load_locale_results;

	// Map of in-flight per-call file contexts, keyed by a monotonic id
	// threaded through the JS bridge. Entries are inserted by parse() /
	// load_locale() and freed when the matching completion event arrives
	// (or on the parse-eval-error path).
	int _next_js_file_ctx_id = 0;
	HashMap<int, JsFileContext *> _js_file_contexts;

private:
#else
	static void _on_file_request(
			Loreline_String path,
			Loreline_FileRequest *request,
			void *userData);

	static void _on_parse_completion(Loreline_Script *script, void *userData);
	static void _on_load_locale_completion(Loreline_Translations *translations, void *userData);
#endif

	void _queue_parse_emit(const Ref<LorelineParseResult> &result, const Variant &script_arg);
	void _queue_load_locale_emit(const Ref<LorelineLoadLocaleResult> &result, const Variant &translations_arg);
	void _drain_pending_emits();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	static Loreline *shared();

	Loreline();
	~Loreline();

	// Parse a Loreline script. Returns a Signal that fires `completed(script)`
	// once parsing + all imports have resolved. `script` is null on parse error.
	//
	// Typical use:
	//   var script = await loreline.parse("res://story.lor")
	//
	// Path shortcut: if `source` starts with `res://` or `user://` and no
	// `file_path` is provided, Loreline reads the file for you.
	Signal parse(const String &source, const String &file_path = "", const Callable &file_handler = Callable());

	// Load translations for a locale, walking the script's full import tree.
	// Loads `<file>.<locale>.lor` for each file; missing translation files are
	// silently skipped. Returns a Signal that fires `completed(translations)`.
	//
	// Typical use:
	//   var translations = await loreline.load_locale("fr", script)
	Signal load_locale(const String &locale, const Ref<LorelineScript> &script, const String &file_path = "", const Callable &file_handler = Callable());

	Ref<LorelineInterpreter> play(const Ref<LorelineScript> &script, const Callable &on_dialogue = Callable(), const Callable &on_choice = Callable(), const Callable &on_finished = Callable(), const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());
	Ref<LorelineInterpreter> resume(const Ref<LorelineScript> &script, const Callable &on_dialogue, const Callable &on_choice, const Callable &on_finished, const String &save_data, const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());

	void _retain_interpreter(const Ref<LorelineInterpreter> &interp);
	void _release_interpreter(LorelineInterpreter *interp);
	static void _release_active_interpreter(LorelineInterpreter *interp);
};
