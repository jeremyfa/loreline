#include "loreline_interpreter.h"

#include <godot_cpp/variant/utility_functions.hpp>

LorelineInterpreter::LorelineInterpreter()
		: _interp(nullptr), _pending_advance(nullptr), _pending_select(nullptr) {
}

LorelineInterpreter::~LorelineInterpreter() {
	if (_interp) {
		Loreline_releaseInterpreter(_interp);
		_interp = nullptr;
	}
}

void LorelineInterpreter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("advance"), &LorelineInterpreter::advance);
	ClassDB::bind_method(D_METHOD("select", "index"), &LorelineInterpreter::select);
	ClassDB::bind_method(D_METHOD("start", "beat_name"), &LorelineInterpreter::start, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("save_state"), &LorelineInterpreter::save_state);
	ClassDB::bind_method(D_METHOD("restore_state", "data"), &LorelineInterpreter::restore_state);
	ClassDB::bind_method(D_METHOD("get_character_field", "character", "field"), &LorelineInterpreter::get_character_field);
	ClassDB::bind_method(D_METHOD("set_character_field", "character", "field", "value"), &LorelineInterpreter::set_character_field);

	ADD_SIGNAL(MethodInfo("dialogue",
			PropertyInfo(Variant::STRING, "character"),
			PropertyInfo(Variant::STRING, "text"),
			PropertyInfo(Variant::ARRAY, "tags")));

	ADD_SIGNAL(MethodInfo("choice",
			PropertyInfo(Variant::ARRAY, "options")));

	ADD_SIGNAL(MethodInfo("finished"));
}

// --- Callback bridge ---

void LorelineInterpreter::_on_dialogue(
		Loreline_Interpreter *interpreter,
		Loreline_String character,
		Loreline_String text,
		const Loreline_TextTag *tags,
		int tagCount,
		void (*advance)(void),
		void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	self->_pending_advance = advance;
	self->_pending_select = nullptr;

	String godot_character = character.isNull() ? String() : String::utf8(character.c_str());
	String godot_text = text.isNull() ? String() : String::utf8(text.c_str());
	Array godot_tags = _convert_tags(tags, tagCount);

	self->emit_signal("dialogue", godot_character, godot_text, godot_tags);
}

void LorelineInterpreter::_on_choice(
		Loreline_Interpreter *interpreter,
		const Loreline_ChoiceOption *options,
		int optionCount,
		void (*select)(int index),
		void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	self->_pending_select = select;
	self->_pending_advance = nullptr;

	Array godot_options = _convert_options(options, optionCount);

	self->emit_signal("choice", godot_options);
}

void LorelineInterpreter::_on_finish(
		Loreline_Interpreter *interpreter,
		void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	self->_pending_advance = nullptr;
	self->_pending_select = nullptr;

	self->emit_signal("finished");
}

// --- Conversion helpers ---

Array LorelineInterpreter::_convert_tags(const Loreline_TextTag *tags, int tagCount) {
	Array result;
	for (int i = 0; i < tagCount; i++) {
		Dictionary tag;
		tag["value"] = String::utf8(tags[i].value.c_str());
		tag["offset"] = tags[i].offset;
		tag["closing"] = tags[i].closing;
		result.append(tag);
	}
	return result;
}

Array LorelineInterpreter::_convert_options(const Loreline_ChoiceOption *options, int optionCount) {
	Array result;
	for (int i = 0; i < optionCount; i++) {
		Dictionary option;
		option["text"] = String::utf8(options[i].text.c_str());
		option["enabled"] = options[i].enabled;
		option["tags"] = _convert_tags(options[i].tags, options[i].tagCount);
		result.append(option);
	}
	return result;
}

Variant LorelineInterpreter::_value_to_variant(const Loreline_Value &value) {
	switch (value.type) {
		case Loreline_Int:
			return Variant(value.intValue);
		case Loreline_Float:
			return Variant(value.floatValue);
		case Loreline_Bool:
			return Variant(value.boolValue);
		case Loreline_StringValue:
			return Variant(String::utf8(value.stringValue.c_str()));
		case Loreline_Null:
		default:
			return Variant();
	}
}

Loreline_Value LorelineInterpreter::_variant_to_value(const Variant &variant) {
	switch (variant.get_type()) {
		case Variant::INT:
			return Loreline_Value::from_int(static_cast<int>(variant));
		case Variant::FLOAT:
			return Loreline_Value::from_float(static_cast<double>(variant));
		case Variant::BOOL:
			return Loreline_Value::from_bool(static_cast<bool>(variant));
		case Variant::STRING: {
			String s = variant;
			return Loreline_Value::from_string(Loreline_String(s.utf8().get_data()));
		}
		case Variant::NIL:
		default:
			return Loreline_Value::null_val();
	}
}

// --- Public methods ---

void LorelineInterpreter::advance() {
	if (_pending_advance) {
		auto fn = _pending_advance;
		_pending_advance = nullptr;
		fn();
	}
}

void LorelineInterpreter::select(int index) {
	if (_pending_select) {
		auto fn = _pending_select;
		_pending_select = nullptr;
		fn(index);
	}
}

void LorelineInterpreter::start(const String &beat_name) {
	if (!_interp) {
		return;
	}
	CharString utf8 = beat_name.utf8();
	Loreline_start(_interp, Loreline_String(utf8.get_data()));
}

String LorelineInterpreter::save_state() {
	if (!_interp) {
		return String();
	}
	Loreline_String result = Loreline_save(_interp);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
}

void LorelineInterpreter::restore_state(const String &data) {
	if (!_interp) {
		return;
	}
	CharString utf8 = data.utf8();
	Loreline_restore(_interp, Loreline_String(utf8.get_data()));
}

Variant LorelineInterpreter::get_character_field(const String &character, const String &field) {
	if (!_interp) {
		return Variant();
	}
	CharString char_utf8 = character.utf8();
	CharString field_utf8 = field.utf8();
	Loreline_Value value = Loreline_getCharacterField(
			_interp,
			Loreline_String(char_utf8.get_data()),
			Loreline_String(field_utf8.get_data()));
	return _value_to_variant(value);
}

void LorelineInterpreter::set_character_field(const String &character, const String &field, const Variant &value) {
	if (!_interp) {
		return;
	}
	CharString char_utf8 = character.utf8();
	CharString field_utf8 = field.utf8();
	Loreline_setCharacterField(
			_interp,
			Loreline_String(char_utf8.get_data()),
			Loreline_String(field_utf8.get_data()),
			_variant_to_value(value));
}
