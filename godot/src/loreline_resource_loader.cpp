#include "loreline_resource_loader.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

void LorelineResourceLoader::_bind_methods() {
}

PackedStringArray LorelineResourceLoader::_get_recognized_extensions() const {
	PackedStringArray extensions;
	extensions.push_back("lor");
	return extensions;
}

bool LorelineResourceLoader::_handles_type(const StringName &type) const {
	return type == StringName("Resource");
}

String LorelineResourceLoader::_get_resource_type(const String &path) const {
	if (path.get_extension().to_lower() == "lor") {
		return "Resource";
	}
	return "";
}

Variant LorelineResourceLoader::_load(const String &path, const String &original_path,
		bool use_sub_threads, int32_t cache_mode) const {
	Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
	if (!file.is_valid()) {
		UtilityFunctions::push_error("LorelineResourceLoader: failed to open " + path);
		return Variant();
	}

	String source = file->get_as_text();
	file->close();

	Ref<Resource> res;
	res.instantiate();
	res->set_meta("source", source);
	res->set_meta("loreline_path", path);
	return res;
}
