#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#include "loreline_options.h"
#include "loreline_script.h"

using namespace godot;

class Loreline : public Node {
	GDCLASS(Loreline, Node);

private:
	static Loreline *_singleton;
	bool _initialized;
	Vector<Ref<LorelineInterpreter>> _active_interpreters;

#ifdef LORELINE_USE_JS
	bool _js_loaded;
	Dictionary _file_overrides;
#else
	// File import handling: userData for parse callback points to a struct
	// containing the Loreline pointer and an optional override map.
	struct FileRequestContext {
		Loreline *runtime;
		String base_dir;
		Dictionary file_overrides; // path -> content, populated via provide_file()
		Callable file_handler;     // optional user-provided file handler
	};

	FileRequestContext _file_ctx;

	static void _on_file_request(
			Loreline_String path,
			void (*provide)(Loreline_String content),
			void *userData);
#endif

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	static Loreline *shared();

	Loreline();
	~Loreline();

	Ref<LorelineScript> parse(const String &source, const String &file_path = "", const Callable &file_handler = Callable());
	void provide_file(const String &path, const String &content);

	Ref<LorelineInterpreter> play(const Ref<LorelineScript> &script, const Callable &on_dialogue = Callable(), const Callable &on_choice = Callable(), const Callable &on_finished = Callable(), const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());
	Ref<LorelineInterpreter> resume(const Ref<LorelineScript> &script, const Callable &on_dialogue, const Callable &on_choice, const Callable &on_finished, const String &save_data, const String &beat_name = "", const Ref<LorelineOptions> &options = Ref<LorelineOptions>());

	void _retain_interpreter(const Ref<LorelineInterpreter> &interp);
	void _release_interpreter(LorelineInterpreter *interp);
	static void _release_active_interpreter(LorelineInterpreter *interp);
};
