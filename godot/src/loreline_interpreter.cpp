#include "loreline_interpreter.h"
#include "loreline_runtime.h"
#include "loreline_options.h"

#include <atomic>

#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/callable_custom.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

// --- Custom Callables that hold a Ref<LorelineInterpreter> ---
// Keeping a reference to the Callable keeps the interpreter alive.

class LorelineAdvanceCallable : public CallableCustom {
	Ref<LorelineInterpreter> _interp;
public:
	LorelineAdvanceCallable(const Ref<LorelineInterpreter> &interp) : _interp(interp) {}

	uint32_t hash() const override { return _interp->get_instance_id(); }
	String get_as_text() const override { return "LorelineInterpreter::advance()"; }
	ObjectID get_object() const override { return ObjectID(_interp->get_instance_id()); }

	static bool compare_equal(const CallableCustom *a, const CallableCustom *b) {
		return a == b;
	}
	static bool compare_less(const CallableCustom *a, const CallableCustom *b) {
		return a < b;
	}
	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }

	void call(const Variant **p_arguments, int p_argcount, Variant &r_return_value, GDExtensionCallError &r_call_error) const override {
		_interp->advance();
		r_call_error.error = GDEXTENSION_CALL_OK;
	}
};

class LorelineSelectCallable : public CallableCustom {
	Ref<LorelineInterpreter> _interp;
public:
	LorelineSelectCallable(const Ref<LorelineInterpreter> &interp) : _interp(interp) {}

	uint32_t hash() const override { return _interp->get_instance_id(); }
	String get_as_text() const override { return "LorelineInterpreter::select()"; }
	ObjectID get_object() const override { return ObjectID(_interp->get_instance_id()); }

	static bool compare_equal(const CallableCustom *a, const CallableCustom *b) {
		return a == b;
	}
	static bool compare_less(const CallableCustom *a, const CallableCustom *b) {
		return a < b;
	}
	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }

	void call(const Variant **p_arguments, int p_argcount, Variant &r_return_value, GDExtensionCallError &r_call_error) const override {
		int index = 0;
		if (p_argcount > 0 && p_arguments[0]->get_type() == Variant::INT) {
			index = *p_arguments[0];
		}
		_interp->select(index);
		r_call_error.error = GDEXTENSION_CALL_OK;
	}
};

#ifdef LORELINE_USE_JS
#include <godot_cpp/classes/java_script_bridge.hpp>
#include <godot_cpp/classes/json.hpp>
#include "loreline_js_utils.h"

HashMap<int, LorelineInterpreter *> LorelineInterpreter::_js_registry;
#endif

// Handed to the user's async custom function as its `resolve` argument.
// Invoking resumes the interpreter; dropping without invoking cancels the
// async call and lets the interpreter clean up naturally on release.
//
// Holds Ref<LorelineInterpreter> on both backends — retaining the resolve
// Callable keeps the interpreter alive (and transitively options via
// LorelineInterpreter::_options_ref), and provides a valid ObjectID so
// GDScript accepts the Callable.
class LorelineResolveCallable : public CallableCustom {
#ifdef LORELINE_USE_JS
	int _call_id;
	Ref<LorelineInterpreter> _interp;
#else
	mutable Loreline_AsyncResolve *_resolve;
	Ref<LorelineInterpreter> _interp;
#endif
	mutable std::atomic<bool> _resolved;

public:
#ifdef LORELINE_USE_JS
	LorelineResolveCallable(int call_id, const Ref<LorelineInterpreter> &interp)
			: _call_id(call_id), _interp(interp), _resolved(false) {}
#else
	LorelineResolveCallable(Loreline_AsyncResolve *resolve, const Ref<LorelineInterpreter> &interp)
			: _resolve(resolve), _interp(interp), _resolved(false) {}
#endif

	~LorelineResolveCallable() {
		bool expected = false;
		if (!_resolved.compare_exchange_strong(expected, true)) {
			return; // already resolved or canceled
		}
#ifdef LORELINE_USE_JS
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.cancelFunctionDone(" + String::num_int64(_call_id) + ")", true);
		}
#else
		if (_resolve) {
			Loreline_cancelAsync(_resolve);
			_resolve = nullptr;
		}
#endif
	}

	uint32_t hash() const override { return (uint32_t)(uintptr_t)this; }
	String get_as_text() const override { return "LorelineAsyncResolve"; }
	ObjectID get_object() const override {
		return _interp.is_valid() ? ObjectID(_interp->get_instance_id()) : ObjectID();
	}

	static bool compare_equal(const CallableCustom *a, const CallableCustom *b) { return a == b; }
	static bool compare_less(const CallableCustom *a, const CallableCustom *b) { return a < b; }
	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }

	void call(const Variant **p_arguments, int p_argcount, Variant &r_return_value, GDExtensionCallError &r_call_error) const override {
		r_call_error.error = GDEXTENSION_CALL_OK;
		bool expected = false;
		if (!_resolved.compare_exchange_strong(expected, true)) {
			UtilityFunctions::push_warning("LorelineResolveCallable: resolve called more than once — ignoring");
			return;
		}
#ifdef LORELINE_USE_JS
		JavaScriptBridge *js = JavaScriptBridge::get_singleton();
		if (js) {
			js->eval("_lorelineBridge.provideFunctionDone(" + String::num_int64(_call_id) + ")", true);
			LorelineInterpreter::_poll_js_events();
		}
#else
		if (_resolve) {
			Loreline_resolveAsync(_resolve, Loreline_Value::null_val());
			_resolve = nullptr;
			// No inline flush: interpreter-level retain/release on each
			// DISPATCH_OUT site keeps the interpreter alive until the
			// frame-level Loreline_update drains the queue.
		}
#endif
	}
};

#ifndef LORELINE_USE_JS
Callable loreline_make_resolve_callable(Loreline_AsyncResolve *resolve, const Ref<LorelineInterpreter> &interp) {
	return Callable(memnew(LorelineResolveCallable(resolve, interp)));
}
#else
Callable loreline_make_resolve_callable(
		int call_id,
		const Ref<LorelineInterpreter> &interp) {
	return Callable(memnew(LorelineResolveCallable(call_id, interp)));
}
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
	// Remove from active list if still there (user dropped ref before finish)
	Loreline::_release_active_interpreter(this);

#ifdef LORELINE_USE_JS
	if (_js_id != 0) {
		_js_registry.erase(_js_id);
		LorelineOptions::unregister_js_functions(_js_id);
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
	// Free per-function contexts now that the Haxe interpreter is gone — no
	// further callbacks can fire on them. Must happen after releaseInterpreter
	// so any in-flight callback already saw a valid ctx.
	for (LorelineFunctionCallContext *ctx : _fn_contexts) {
		delete ctx;
	}
	_fn_contexts.clear();
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
			PropertyInfo(Variant::OBJECT, "interpreter"),
			PropertyInfo(Variant::STRING, "character"),
			PropertyInfo(Variant::STRING, "text"),
			PropertyInfo(Variant::ARRAY, "tags"),
			PropertyInfo(Variant::CALLABLE, "advance")));

	ADD_SIGNAL(MethodInfo("choice",
			PropertyInfo(Variant::OBJECT, "interpreter"),
			PropertyInfo(Variant::ARRAY, "options"),
			PropertyInfo(Variant::CALLABLE, "select")));

	ADD_SIGNAL(MethodInfo("finished",
			PropertyInfo(Variant::OBJECT, "interpreter")));
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
			Callable advance_callable = Callable(interp, "advance");
			interp->emit_signal("dialogue", interp, character, text, godot_tags, advance_callable);

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
			Callable select_callable = Callable(interp, "select");
			interp->emit_signal("choice", interp, godot_options, select_callable);

		} else if (type == "finished") {
			interp->emit_signal("finished", interp);

		} else if (type == "async_function_call") {
			int call_id = event.get("callId", 0);
			String func_name = event.get("name", "");
			Array args = event.get("args", Array());

			Dictionary *funcs = LorelineOptions::_js_async_function_registry.getptr(interp_id);
			Callable fn;
			if (funcs) {
				fn = funcs->get(func_name, Callable());
			}
			if (!fn.is_valid()) {
				// No registered function — resume the interpreter so it doesn't wedge.
				if (js) {
					js->eval("_lorelineBridge.provideFunctionDone(" + String::num_int64(call_id) + ")", true);
				}
				continue;
			}

			Ref<LorelineInterpreter> interp_ref(interp);
			Callable resolve_callable = loreline_make_resolve_callable(call_id, interp_ref);
			fn.call(Variant(), args, resolve_callable);
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
	// Construct the Ref FIRST, before releasing the active-list Ref, so the
	// refcount never dips to 0 (strict overlap).
	Ref<LorelineInterpreter> self_ref(self);

	self->_pending_advance = advance;
	self->_pending_select = nullptr;

	String godot_character = character.isNull() ? String() : String::utf8(character.c_str());
	String godot_text = text.isNull() ? String() : String::utf8(text.c_str());
	Array godot_tags = _convert_tags(tags, tagCount);

	// Release from active list — the Callable now holds the Ref keeping the interpreter alive
	Loreline::_release_active_interpreter(self);

	Callable advance_callable(memnew(LorelineAdvanceCallable(self_ref)));
	self->emit_signal("dialogue", self, godot_character, godot_text, godot_tags, advance_callable);
}

void LorelineInterpreter::_on_choice(
		Loreline_Interpreter *interpreter,
		const Loreline_ChoiceOption *options,
		int optionCount,
		void (*select)(int index),
		void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	// Construct the Ref FIRST (strict overlap — see _on_dialogue).
	Ref<LorelineInterpreter> self_ref(self);

	self->_pending_select = select;
	self->_pending_advance = nullptr;

	Array godot_options = _convert_options(options, optionCount);

	// Release from active list — the Callable now holds the Ref keeping the interpreter alive
	Loreline::_release_active_interpreter(self);

	Callable select_callable(memnew(LorelineSelectCallable(self_ref)));
	self->emit_signal("choice", self, godot_options, select_callable);
}

// Interpreter-level retain/release — passed to Loreline_play/resume, invoked
// around every queued callback in the linc wrapper.
Loreline_Retainer *LorelineInterpreter::_retain_interpreter(void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	if (!self) return nullptr;
	self->reference();
	return reinterpret_cast<Loreline_Retainer *>(self);
}

void LorelineInterpreter::_release_interpreter(Loreline_Retainer *retainer) {
	if (!retainer) return;
	LorelineInterpreter *self = reinterpret_cast<LorelineInterpreter *>(retainer);
	if (self->unreference()) {
		memdelete(self);
	}
}

void LorelineInterpreter::_on_finish(
		Loreline_Interpreter *interpreter,
		void *userData) {
	LorelineInterpreter *self = static_cast<LorelineInterpreter *>(userData);
	// Guard refcount through emit_signal. If no external Refs remain after
	// this function returns, the interpreter is released here.
	Ref<LorelineInterpreter> guard(self);

	self->_pending_advance = nullptr;
	self->_pending_select = nullptr;

	Loreline::_release_active_interpreter(self);

	self->emit_signal("finished", self);
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
		// No inline flush: interpreter-level retain/release on each DISPATCH_OUT
		// site keeps the interpreter alive until the frame-level Loreline_update
		// drains the queue.
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
		String escaped_beat = loreline_escape_js(beat_name);
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
		String escaped = loreline_escape_js(data);
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
	String escaped_char = loreline_escape_js(character);
	String escaped_field = loreline_escape_js(field);
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
	String escaped_char = loreline_escape_js(character);
	String escaped_field = loreline_escape_js(field);
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + loreline_escape_js(s) + "'";
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
	String escaped_field = loreline_escape_js(field);
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
	String escaped_field = loreline_escape_js(field);
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + loreline_escape_js(s) + "'";
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
	String escaped_field = loreline_escape_js(field);
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
	String escaped_field = loreline_escape_js(field);
	String js_value;
	switch (value.get_type()) {
		case Variant::INT: js_value = String::num_int64(value); break;
		case Variant::FLOAT: js_value = String::num(value); break;
		case Variant::BOOL: js_value = ((bool)value) ? "true" : "false"; break;
		case Variant::STRING: {
			String s = value;
			js_value = "'" + loreline_escape_js(s) + "'";
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
