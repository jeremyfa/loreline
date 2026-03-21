#include "loreline_interpreter.h"

#include <godot_cpp/variant/utility_functions.hpp>

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/java_script_bridge.hpp>
#include <godot_cpp/classes/json.hpp>

HashMap<int, LorelineInterpreter *> LorelineInterpreter::_js_registry;
#endif

LorelineInterpreter::LorelineInterpreter()
#ifdef LORELINE_USE_JS
		: _js_id(0)
#else
		: _interp(nullptr), _pending_advance(nullptr), _pending_select(nullptr)
#endif
{
}

LorelineInterpreter::~LorelineInterpreter() {
#ifdef LORELINE_USE_JS
	if (_js_id != 0) {
		_js_registry.erase(_js_id);
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.releaseInterpreter(" + String::num_int64(_js_id) + ")", true);
		}
		_js_id = 0;
	}
#else
	if (_interp) {
		Loreline_releaseInterpreter(_interp);
		_interp = nullptr;
	}
#endif
}

void LorelineInterpreter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("advance"), &LorelineInterpreter::advance);
	ClassDB::bind_method(D_METHOD("select", "index"), &LorelineInterpreter::select);
	ClassDB::bind_method(D_METHOD("start", "beat_name"), &LorelineInterpreter::start, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("save_state"), &LorelineInterpreter::save_state);
	ClassDB::bind_method(D_METHOD("restore_state", "data"), &LorelineInterpreter::restore_state);
	ClassDB::bind_method(D_METHOD("get_character_field", "character", "field"), &LorelineInterpreter::get_character_field);
	ClassDB::bind_method(D_METHOD("set_character_field", "character", "field", "value"), &LorelineInterpreter::set_character_field);
	ClassDB::bind_method(D_METHOD("get_state_field", "field"), &LorelineInterpreter::get_state_field);
	ClassDB::bind_method(D_METHOD("set_state_field", "field", "value"), &LorelineInterpreter::set_state_field);
	ClassDB::bind_method(D_METHOD("get_top_level_state_field", "field"), &LorelineInterpreter::get_top_level_state_field);
	ClassDB::bind_method(D_METHOD("set_top_level_state_field", "field", "value"), &LorelineInterpreter::set_top_level_state_field);
	ClassDB::bind_method(D_METHOD("current_node"), &LorelineInterpreter::current_node);

	ADD_SIGNAL(MethodInfo("dialogue",
			PropertyInfo(Variant::STRING, "character"),
			PropertyInfo(Variant::STRING, "text"),
			PropertyInfo(Variant::ARRAY, "tags")));

	ADD_SIGNAL(MethodInfo("choice",
			PropertyInfo(Variant::ARRAY, "options")));

	ADD_SIGNAL(MethodInfo("finished"));
}

#ifdef LORELINE_USE_JS

void LorelineInterpreter::_poll_js_events() {
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return;

	Variant events_json = js->eval("_lorelineBridge.pollEvents()", true);
	if (events_json.get_type() != Variant::STRING) return;
	String events_str = events_json;
	if (events_str.is_empty()) return;

	Ref<JSON> json_parser;
	json_parser.instantiate();
	if (json_parser->parse(events_str) != OK) return;

	Array events = json_parser->get_data();
	for (int i = 0; i < events.size(); i++) {
		Dictionary event = events[i];
		String type = event.get("type", "");
		int interp_id = event.get("interpId", 0);

		LorelineInterpreter **pp = _js_registry.getptr(interp_id);
		if (!pp) continue;
		LorelineInterpreter *interp = *pp;

		if (type == "dialogue") {
			String character = event.get("character", "");
			String text = event.get("text", "");
			Array tags_raw = event.get("tags", Array());

			Array godot_tags;
			for (int j = 0; j < tags_raw.size(); j++) {
				Dictionary tag_raw = tags_raw[j];
				Dictionary tag;
				tag["value"] = tag_raw.get("value", "");
				tag["offset"] = tag_raw.get("offset", 0);
				tag["closing"] = tag_raw.get("closing", false);
				godot_tags.append(tag);
			}
			interp->emit_signal("dialogue", character, text, godot_tags);

		} else if (type == "choice") {
			Array opts_raw = event.get("options", Array());
			Array godot_options;
			for (int j = 0; j < opts_raw.size(); j++) {
				Dictionary opt_raw = opts_raw[j];
				Dictionary option;
				option["text"] = opt_raw.get("text", "");
				option["enabled"] = opt_raw.get("enabled", true);

				Array opt_tags;
				if (opt_raw.has("tags")) {
					Array tags_arr = opt_raw["tags"];
					for (int k = 0; k < tags_arr.size(); k++) {
						Dictionary tag_raw = tags_arr[k];
						Dictionary tag;
						tag["value"] = tag_raw.get("value", "");
						tag["offset"] = tag_raw.get("offset", 0);
						tag["closing"] = tag_raw.get("closing", false);
						opt_tags.append(tag);
					}
				}
				option["tags"] = opt_tags;
				godot_options.append(option);
			}
			interp->emit_signal("choice", godot_options);

		} else if (type == "finished") {
			interp->emit_signal("finished");
		}
	}
}

#else

// --- Native callback bridge ---

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

#endif // LORELINE_USE_JS

// --- Public methods ---

void LorelineInterpreter::advance() {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (js) {
		js->eval("_lorelineBridge.advance(" + String::num_int64(_js_id) + ")", true);
		_poll_js_events();
	}
#else
	if (_pending_advance) {
		auto fn = _pending_advance;
		_pending_advance = nullptr;
		fn();
	}
#endif
}

void LorelineInterpreter::select(int index) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (js) {
		js->eval("_lorelineBridge.select(" + String::num_int64(_js_id) + "," + String::num_int64(index) + ")", true);
		_poll_js_events();
	}
#else
	if (_pending_select) {
		auto fn = _pending_select;
		_pending_select = nullptr;
		fn(index);
	}
#endif
}

void LorelineInterpreter::start(const String &beat_name) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (js) {
		String escaped_beat = beat_name.replace("\\", "\\\\").replace("'", "\\'");
		js->eval("_lorelineBridge.start(" + String::num_int64(_js_id) + ",'" + escaped_beat + "')", true);
		_poll_js_events();
	}
#else
	if (!_interp) {
		return;
	}
	CharString utf8 = beat_name.utf8();
	Loreline_start(_interp, Loreline_String(utf8.get_data()));
#endif
}

String LorelineInterpreter::save_state() {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return String();
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return String();
	Variant result = js->eval("_lorelineBridge.save(" + String::num_int64(_js_id) + ")", true);
	return result;
#else
	if (!_interp) {
		return String();
	}
	Loreline_String result = Loreline_save(_interp);
	if (result.isNull()) {
		return String();
	}
	return String::utf8(result.c_str());
#endif
}

void LorelineInterpreter::restore_state(const String &data) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (js) {
		String escaped = data.replace("\\", "\\\\").replace("'", "\\'");
		js->eval("_lorelineBridge.restore(" + String::num_int64(_js_id) + ",'" + escaped + "')", true);
		_poll_js_events();
	}
#else
	if (!_interp) {
		return;
	}
	CharString utf8 = data.utf8();
	Loreline_restore(_interp, Loreline_String(utf8.get_data()));
#endif
}

Variant LorelineInterpreter::get_character_field(const String &character, const String &field) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return Variant();
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return Variant();
	String escaped_char = character.replace("\\", "\\\\").replace("'", "\\'");
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	return js->eval("_lorelineBridge.getCharacterField(" + String::num_int64(_js_id) +
		",'" + escaped_char + "','" + escaped_field + "')", true);
#else
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
#endif
}

void LorelineInterpreter::set_character_field(const String &character, const String &field, const Variant &value) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return;
	String escaped_char = character.replace("\\", "\\\\").replace("'", "\\'");
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'";
			break;
		}
		default: js_value = "null"; break;
	}
	js->eval("_lorelineBridge.setCharacterField(" + String::num_int64(_js_id) +
		",'" + escaped_char + "','" + escaped_field + "'," + js_value + ")", true);
#else
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
#endif
}

Variant LorelineInterpreter::get_state_field(const String &field) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return Variant();
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return Variant();
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	return js->eval("_lorelineBridge.getStateField(" + String::num_int64(_js_id) +
		",'" + escaped_field + "')", true);
#else
	if (!_interp) {
		return Variant();
	}
	CharString field_utf8 = field.utf8();
	Loreline_Value value = Loreline_getStateField(
			_interp,
			Loreline_String(field_utf8.get_data()));
	return _value_to_variant(value);
#endif
}

void LorelineInterpreter::set_state_field(const String &field, const Variant &value) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return;
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'";
			break;
		}
		default: js_value = "null"; break;
	}
	js->eval("_lorelineBridge.setStateField(" + String::num_int64(_js_id) +
		",'" + escaped_field + "'," + js_value + ")", true);
#else
	if (!_interp) {
		return;
	}
	CharString field_utf8 = field.utf8();
	Loreline_setStateField(
			_interp,
			Loreline_String(field_utf8.get_data()),
			_variant_to_value(value));
#endif
}

Variant LorelineInterpreter::get_top_level_state_field(const String &field) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return Variant();
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return Variant();
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	return js->eval("_lorelineBridge.getTopLevelStateField(" + String::num_int64(_js_id) +
		",'" + escaped_field + "')", true);
#else
	if (!_interp) {
		return Variant();
	}
	CharString field_utf8 = field.utf8();
	Loreline_Value value = Loreline_getTopLevelStateField(
			_interp,
			Loreline_String(field_utf8.get_data()));
	return _value_to_variant(value);
#endif
}

void LorelineInterpreter::set_top_level_state_field(const String &field, const Variant &value) {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return;
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return;
	String escaped_field = field.replace("\\", "\\\\").replace("'", "\\'");
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'";
			break;
		}
		default: js_value = "null"; break;
	}
	js->eval("_lorelineBridge.setTopLevelStateField(" + String::num_int64(_js_id) +
		",'" + escaped_field + "'," + js_value + ")", true);
#else
	if (!_interp) {
		return;
	}
	CharString field_utf8 = field.utf8();
	Loreline_setTopLevelStateField(
			_interp,
			Loreline_String(field_utf8.get_data()),
			_variant_to_value(value));
#endif
}

Dictionary LorelineInterpreter::current_node() {
#ifdef LORELINE_USE_JS
	if (_js_id == 0) return Dictionary();
	JavaScriptBridge *js = JavaScriptBridge::get_singleton();
	if (!js) return Dictionary();
	Variant json_str = js->eval("_lorelineBridge.currentNode(" + String::num_int64(_js_id) + ")", true);
	if (json_str.get_type() != Variant::STRING) return Dictionary();
	Ref<JSON> json_parser;
	json_parser.instantiate();
	if (json_parser->parse(json_str) != OK) return Dictionary();
	Dictionary data = json_parser->get_data();
	Dictionary result;
	result["type"] = data.get("type", "");
	result["line"] = data.get("line", 0);
	result["column"] = data.get("column", 0);
	result["offset"] = data.get("offset", 0);
	result["length"] = data.get("length", 0);
	return result;
#else
	if (!_interp) {
		return Dictionary();
	}
	Loreline_Node node = Loreline_currentNode(_interp);
	if (node.type.isNull()) {
		return Dictionary();
	}
	Dictionary result;
	result["type"] = String::utf8(node.type.c_str());
	result["line"] = node.line;
	result["column"] = node.column;
	result["offset"] = node.offset;
	result["length"] = node.length;
	return result;
#endif
}
