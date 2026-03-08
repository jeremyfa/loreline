#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "Loreline.h"
#include "loreline_script.h"

using namespace godot;

class LorelineRuntime : public Node {
	GDCLASS(LorelineRuntime, Node);

private:
	bool _initialized;

	// File import handling: userData for parse callback points to a struct
	// containing the LorelineRuntime pointer and an optional override map.
	struct FileRequestContext {
		LorelineRuntime *runtime;
		String base_dir;
		Dictionary file_overrides; // path -> content, populated via provide_file()
	};

	FileRequestContext _file_ctx;

	static void _on_file_request(
			Loreline_String path,
			void (*provide)(Loreline_String content),
			void *userData);

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	LorelineRuntime();
	~LorelineRuntime();

	Ref<LorelineScript> parse(const String &source, const String &file_path = "");
	void provide_file(const String &path, const String &content);
};
