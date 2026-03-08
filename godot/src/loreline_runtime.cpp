#include "loreline_runtime.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

LorelineRuntime::LorelineRuntime()
		: _initialized(false) {
	_file_ctx.runtime = this;
}

LorelineRuntime::~LorelineRuntime() {
}

void LorelineRuntime::_bind_methods() {
	ClassDB::bind_method(D_METHOD("parse", "source", "file_path"), &LorelineRuntime::parse, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("provide_file", "path", "content"), &LorelineRuntime::provide_file);

	ADD_SIGNAL(MethodInfo("file_requested",
			PropertyInfo(Variant::STRING, "path")));
}

void LorelineRuntime::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			Loreline_init();
			_initialized = true;
			set_process(true);
		} break;

		case NOTIFICATION_PROCESS: {
			if (_initialized) {
				Loreline_update(get_process_delta_time());
			}
		} break;

		case NOTIFICATION_EXIT_TREE: {
			if (_initialized) {
				Loreline_dispose();
				_initialized = false;
			}
		} break;
	}
}

void LorelineRuntime::_on_file_request(
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

Ref<LorelineScript> LorelineRuntime::parse(const String &source, const String &file_path) {
	if (!_initialized) {
		UtilityFunctions::push_error("LorelineRuntime: not initialized. Add this node to the scene tree first.");
		return Ref<LorelineScript>();
	}

	CharString source_utf8 = source.utf8();
	CharString path_utf8 = file_path.utf8();

	// Set up the base directory for resolving imports
	if (!file_path.is_empty()) {
		_file_ctx.base_dir = file_path.get_base_dir();
	} else {
		_file_ctx.base_dir = "res://";
	}
	_file_ctx.file_overrides.clear();

	Loreline_String loreline_source = Loreline_String(source_utf8.get_data());
	Loreline_String loreline_path = file_path.is_empty()
			? Loreline_String()
			: Loreline_String(path_utf8.get_data());

	Loreline_Script *raw = Loreline_parse(
			loreline_source,
			loreline_path,
			_on_file_request,
			static_cast<void *>(&_file_ctx));

	if (!raw) {
		UtilityFunctions::push_error("LorelineRuntime: failed to parse script.");
		return Ref<LorelineScript>();
	}

	Ref<LorelineScript> script;
	script.instantiate();
	script->_script = raw;
	return script;
}

void LorelineRuntime::provide_file(const String &path, const String &content) {
	_file_ctx.file_overrides[path] = content;
}
