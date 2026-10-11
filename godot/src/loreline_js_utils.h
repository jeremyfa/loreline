#pragma once

#ifdef LORELINE_USE_JS

#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

// Escape a Godot String for use inside a JS single-quoted string literal.
// Handles: backslash, single quote, newline, carriage return, tab, null bytes.
static inline String loreline_escape_js(const String &s) {
	return s.replace("\\", "\\\\")
			.replace("'", "\\'")
			.replace("\n", "\\n")
			.replace("\r", "\\r")
			.replace("\0", "")
			.replace("\t", "\\t");
}

// Parses a JSON string returned by the JS bridge into a Variant.
// Values cross the eval boundary as JSON so containers (arrays,
// dictionaries) survive; scalars ride the same way for uniformity.
static inline Variant loreline_json_to_variant(const Variant &json_str) {
	if (json_str.get_type() != Variant::STRING) return Variant();
	String s = json_str;
	if (s.is_empty()) return Variant();
	Ref<JSON> json_parser;
	json_parser.instantiate();
	if (json_parser->parse(s) != OK) return Variant();
	return json_parser->get_data();
}

#endif // LORELINE_USE_JS
