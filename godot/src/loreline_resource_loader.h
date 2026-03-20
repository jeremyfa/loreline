#pragma once

#include <godot_cpp/classes/resource_format_loader.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

class LorelineResourceLoader : public ResourceFormatLoader {
	GDCLASS(LorelineResourceLoader, ResourceFormatLoader);

protected:
	static void _bind_methods();

public:
	virtual PackedStringArray _get_recognized_extensions() const override;
	virtual bool _handles_type(const StringName &type) const override;
	virtual String _get_resource_type(const String &path) const override;
	virtual Variant _load(const String &path, const String &original_path,
			bool use_sub_threads, int32_t cache_mode) const override;
};
