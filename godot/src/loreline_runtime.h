#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#include "loreline_script.h"

using namespace godot;

class Loreline : public Node {
	GDCLASS(Loreline, Node);

private:
	bool _initialized;

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
	Loreline();
	~Loreline();

	Ref<LorelineScript> parse(const String &source, const String &file_path = "");
	void provide_file(const String &path, const String &content);
};
