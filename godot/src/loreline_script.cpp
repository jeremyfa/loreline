#include "loreline_script.h"

#include <godot_cpp/variant/utility_functions.hpp>

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/java_script_bridge.hpp>
#endif

LorelineScript::LorelineScript()
#ifdef LORELINE_USE_JS
		: _js_id(0)
#else
		: _script(nullptr)
#endif
{
}

LorelineScript::~LorelineScript() {
#ifdef LORELINE_USE_JS
	if (_js_id != 0) {
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.releaseScript(" + String::num_int64(_js_id) + ")", true);
		}
		_js_id = 0;
	}
#else
	if (_script) {
		Loreline_releaseScript(_script);
		_script = nullptr;
	}
#endif
}

void LorelineScript::_bind_methods() {
	ClassDB::bind_method(D_METHOD("play", "beat_name"), &LorelineScript::play, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("resume", "save_data", "beat_name"), &LorelineScript::resume, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("extract_translations"), &LorelineScript::extract_translations);
	ClassDB::bind_method(D_METHOD("print_script"), &LorelineScript::print_script);
	ClassDB::bind_method(D_METHOD("to_json", "pretty"), &LorelineScript::to_json, DEFVAL(false));
	ClassDB::bind_static_method("LorelineScript", D_METHOD("from_json", "json"), &LorelineScript::from_json);
}

Ref<LorelineInterpreter> LorelineScript::play(const String &beat_name) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) {
		return Ref<LorelineInterpreter>();
	}

	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		return Ref<LorelineInterpreter>();
	}

	String escaped_beat = beat_name.replace("\\", "\\\\").replace("'", "\\'");
	String js_code = "_lorelineBridge.play(" + String::num_int64(_js_id) + ",'" + escaped_beat + "')";
	Variant result = js->eval(js_code, true);
	int interp_id = result;
	if (interp_id == 0) {
		return Ref<LorelineInterpreter>();
	}

	Ref<LorelineInterpreter> interp;
	interp.instantiate();
	interp->_js_id = interp_id;
	LorelineInterpreter::_js_registry[interp_id] = interp.ptr();
	// Don't poll events here — GDScript connects signals AFTER play/resume returns.
	// Events will be dispatched on the next _process frame.
	return interp;

#else
	if (!_script) {
		return Ref<LorelineInterpreter>();
	}

	Ref<LorelineInterpreter> interp;
	interp.instantiate();

	CharString beat_utf8 = beat_name.utf8();
	Loreline_String loreline_beat = beat_name.is_empty()
			? Loreline_String()
			: Loreline_String(beat_utf8.get_data());

	interp->_interp = Loreline_play(
			_script,
			LorelineInterpreter::_on_dialogue,
			LorelineInterpreter::_on_choice,
			LorelineInterpreter::_on_finish,
			loreline_beat,
			nullptr, // translations
			static_cast<void *>(interp.ptr()));

	if (!interp->_interp) {
		return Ref<LorelineInterpreter>();
	}

	return interp;
#endif
}

Ref<LorelineInterpreter> LorelineScript::resume(const String &save_data, const String &beat_name) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) {
		return Ref<LorelineInterpreter>();
	}

	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		return Ref<LorelineInterpreter>();
	}

	String escaped_save = save_data.replace("\\", "\\\\").replace("'", "\\'");
	String escaped_beat = beat_name.replace("\\", "\\\\").replace("'", "\\'");
	String js_code = "_lorelineBridge.resume(" + String::num_int64(_js_id) +
		",'" + escaped_save + "','" + escaped_beat + "')";
	Variant result = js->eval(js_code, true);
	int interp_id = result;
	if (interp_id == 0) {
		return Ref<LorelineInterpreter>();
	}

	Ref<LorelineInterpreter> interp;
	interp.instantiate();
	interp->_js_id = interp_id;
	LorelineInterpreter::_js_registry[interp_id] = interp.ptr();
	// Don't poll events here — GDScript connects signals AFTER play/resume returns.
	// Events will be dispatched on the next _process frame.
	return interp;

#else
	if (!_script) {
		return Ref<LorelineInterpreter>();
	}

	Ref<LorelineInterpreter> interp;
	interp.instantiate();

	CharString save_utf8 = save_data.utf8();
	CharString beat_utf8 = beat_name.utf8();
	Loreline_String loreline_save = Loreline_String(save_utf8.get_data());
	Loreline_String loreline_beat = beat_name.is_empty()
			? Loreline_String()
			: Loreline_String(beat_utf8.get_data());

	interp->_interp = Loreline_resume(
			_script,
			LorelineInterpreter::_on_dialogue,
			LorelineInterpreter::_on_choice,
			LorelineInterpreter::_on_finish,
			loreline_save,
			loreline_beat,
			nullptr, // translations
			static_cast<void *>(interp.ptr()));

	if (!interp->_interp) {
		return Ref<LorelineInterpreter>();
	}

	return interp;
#endif
}

Dictionary LorelineScript::extract_translations() {
#ifdef LORELINE_USE_JS
	// TODO: implement translation extraction for JS path
	return Dictionary();
#else
	if (!_script) {
		return Dictionary();
	}
	// TODO: implement translation extraction
	return Dictionary();
#endif
}

String LorelineScript::print_script() {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) {
		return String();
	}
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		return String();
	}
	Variant result = js->eval("_lorelineBridge.printScript(" + String::num_int64(_js_id) + ")", true);
	return result;
#else
	if (!_script) {
		return String();
	}
	Loreline_String result = Loreline_printScript(_script);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
#endif
}

String LorelineScript::to_json(bool pretty) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) {
		return String();
	}
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		return String();
	}
	String pretty_str = pretty ? "true" : "false";
	Variant result = js->eval("_lorelineBridge.scriptToJson(" + String::num_int64(_js_id) + "," + pretty_str + ")", true);
	return result;
#else
	if (!_script) {
		return String();
	}
	Loreline_String result = Loreline_scriptToJson(_script, pretty);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
#endif
}

Ref<LorelineScript> LorelineScript::from_json(const String &json) {
#ifdef LORELINE_USE_JS
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) {
		return Ref<LorelineScript>();
	}
	String escaped_json = json.replace("\\", "\\\\").replace("'", "\\'");
	Variant result = js->eval("_lorelineBridge.scriptFromJson('" + escaped_json + "')", true);
	int script_id = result;
	if (script_id == 0) {
		return Ref<LorelineScript>();
	}
	Ref<LorelineScript> ref;
	ref.instantiate();
	ref->_js_id = script_id;
	return ref;
#else
	CharString json_utf8 = json.utf8();
	Loreline_Script *script = Loreline_scriptFromJson(Loreline_String(json_utf8.get_data()));
	if (!script) {
		return Ref<LorelineScript>();
	}
	Ref<LorelineScript> ref;
	ref.instantiate();
	ref->_script = script;
	return ref;
#endif
}
