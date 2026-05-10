#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

#ifndef LORELINE_USE_JS
#include "Loreline.h"
#endif

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/java_script_bridge.hpp>
#endif

using namespace godot;

/**
 * Ref-counted wrapper around a Loreline translations handle.
 *
 * Obtained from `LorelineScript::extract_translations()` or
 * `Loreline::load_locale()`. Pass to `LorelineOptions::set_translations()`.
 *
 * Opaque to GDScript — users only pass it around.
 */
class LorelineTranslations : public RefCounted {
	GDCLASS(LorelineTranslations, RefCounted);

protected:
	static void _bind_methods() {}

public:
#ifndef LORELINE_USE_JS
	Loreline_Translations *_handle = nullptr;
#else
	int _js_id = 0;
#endif

	LorelineTranslations() {}

	~LorelineTranslations() {
#ifndef LORELINE_USE_JS
		if (_handle) {
			Loreline_releaseTranslations(_handle);
			_handle = nullptr;
		}
#else
		if (_js_id != 0) {
			JavaScriptBridge *js = JavaScriptBridge::get_singleton();
			if (js) {
				js->eval("_lorelineBridge.releaseTranslations(" + String::num_int64(_js_id) + ")", true);
			}
			_js_id = 0;
		}
#endif
	}
};
