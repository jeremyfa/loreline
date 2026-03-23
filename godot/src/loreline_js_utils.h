#pragma once

#ifdef LORELINE_USE_JS

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

#endif // LORELINE_USE_JS
