#include "loreline_script.h"

LorelineScript::LorelineScript()
		: _script(nullptr) {
}

LorelineScript::~LorelineScript() {
	if (_script) {
		Loreline_releaseScript(_script);
		_script = nullptr;
	}
}

void LorelineScript::_bind_methods() {
	ClassDB::bind_method(D_METHOD("play", "beat_name"), &LorelineScript::play, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("resume", "save_data", "beat_name"), &LorelineScript::resume, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("extract_translations"), &LorelineScript::extract_translations);
	ClassDB::bind_method(D_METHOD("print_script"), &LorelineScript::print_script);
	ClassDB::bind_method(D_METHOD("to_json", "pretty"), &LorelineScript::to_json, DEFVAL(false));
}

Ref<LorelineInterpreter> LorelineScript::play(const String &beat_name) {
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
}

Ref<LorelineInterpreter> LorelineScript::resume(const String &save_data, const String &beat_name) {
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
}

Dictionary LorelineScript::extract_translations() {
	if (!_script) {
		return Dictionary();
	}
	// TODO: implement translation extraction
	// Loreline_Translations is opaque; need to expose iteration in C API
	return Dictionary();
}

String LorelineScript::print_script() {
	if (!_script) {
		return String();
	}
	Loreline_String result = Loreline_printScript(_script);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
}

String LorelineScript::to_json(bool pretty) {
	if (!_script) {
		return String();
	}
	Loreline_String result = Loreline_scriptToJson(_script, pretty);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
}
