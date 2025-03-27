package loreline;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import loreline.Node.AstNode;

class Objects {

    public static function isFields(value:Any):Bool {

        if (value is Fields) {
            return true;
        }
        else if (value is StringMap) {
            return true;
        }
        else if (value is IntMap) {
            return false;
        }
        #if cs
        else if (isCsDict(value)) {
            return true;
        }
        else if (isCsFields(value)) {
            return true;
        }
        #end
        else if (value is Int || value is Float || value is Bool || value is String) {
            return false;
        }
        else if (Arrays.isArray(value)) {
            return false;
        }

        return true;

    }

    public static function getField(interpreter:Interpreter, fields:Any, name:String):Any {

        return if (fields is Fields) {
            (cast fields:Fields).lorelineGet(interpreter, name);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).get(name);
        }
        #if cs
        else if (isCsDict(fields)) {
            getCsDictField(fields, name);
        }
        else if (isCsFields(fields)) {
            getCsFieldsValue(interpreter, fields, name);
        }
        #end
        else {
            Reflect.getProperty(fields, name);
        }

    }

    public static function getFields(interpreter:Interpreter, fields:Any):Array<String> {

        return if (fields is Fields) {
            (cast fields:Fields).lorelineFields(interpreter);
        }
        else if (fields is StringMap) {
            [for (key in (cast fields:StringMap<Any>).keys()) key];
        }
        #if cs
        else if (isCsDict(fields)) {
            getCsDictKeys(fields);
        }
        else if (isCsFields(fields)) {
            getCsFieldsKeys(interpreter, fields);
        }
        #end
        else {
            Reflect.fields(fields);
        }

    }

    public static function setField(interpreter:Interpreter, fields:Any, name:String, value:Any):Void {

        if (fields is Fields) {
            (cast fields:Fields).lorelineSet(interpreter, name, value);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).set(name, value);
        }
        #if cs
        else if (isCsDict(fields)) {
            setCsDictField(fields, name, value);
        }
        else if (isCsFields(fields)) {
            setCsFieldsValue(interpreter, fields, name, value);
        }
        #end
        else {
            Reflect.setProperty(fields, name, value);
        }

    }

    public static function fieldExists(interpreter:Interpreter, fields:Any, name:String):Bool {

        return if (fields is Fields) {
            (cast fields:Fields).lorelineExists(interpreter, name);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).exists(name);
        }
        #if cs
        else if (isCsDict(fields)) {
            csDictFieldExists(fields, name);
        }
        else if (isCsFields(fields)) {
            csFieldsKeyExists(interpreter, fields, name);
        }
        #end
        else {
            Reflect.hasField(fields, name);
        }

    }

    public static function createFields(?interpreter:Interpreter, ?type:String, ?node:Node):Any {

        @:privateAccess
        if (interpreter != null && interpreter.customCreateFields != null) {
            final customInstance:Any = interpreter.customCreateFields(interpreter, type, node);
            if (customInstance != null) {
                return customInstance;
            }
        }

        if (type != null) {
            final instance:Any = Type.createEmptyInstance(Type.resolveClass(type));
            if (instance is Fields) {
                final fields:Fields = cast instance;
                fields.lorelineCreate(interpreter);
            }
            return instance;
        }

        #if (cs && loreline_use_cs_types)
        return untyped __cs__('new System.Collections.Generic.Dictionary<string,object>()');
        #else
        return new Map<String,Any>();
        #end
    }

    #if cs

    public static function isCsDict(fields:Any):Bool {
        return untyped __cs__('{0} is global::System.Collections.IDictionary', fields);
    }

    public static function getCsDictField(fields:Any, name:String):Any {
        untyped __cs__('global::System.Collections.IDictionary dict = (global::System.Collections.IDictionary){0}', fields);
        return untyped __cs__('dict[{0}]', name);
    }

    public static function setCsDictField(fields:Any, name:String, value:Any):Void {
        untyped __cs__('global::System.Collections.IDictionary dict = (global::System.Collections.IDictionary){0}', fields);
        untyped __cs__('dict[{0}] = {1}', name, value);
    }

    public static function csDictFieldExists(fields:Any, name:String):Bool {
        untyped __cs__('global::System.Collections.IDictionary dict = (global::System.Collections.IDictionary){0}', fields);
        return untyped __cs__('dict.Contains({0})', name);
    }

    public static function getCsDictKeys(fields:Any):Array<String> {
        untyped __cs__('global::System.Collections.IDictionary dict = (global::System.Collections.IDictionary){0}', fields);
        final keys:Array<String> = [];
        untyped __cs__('foreach (var dictKey in dict.Keys) {');
        untyped __cs__('if (dictKey is string) {');
        final key:String = null;
        untyped __cs__('{0} = (string)dictKey', key);
        keys.push(key);
        untyped __cs__('}');
        untyped __cs__('}');
        return keys;
    }

    public static function isCsFields(fields:Any):Bool {
        return untyped __cs__('{0} is global::Loreline.IFields', fields);
    }

    public static function getCsFieldsValue(?interpreter:Interpreter, fields:Any, name:String):Any {
        untyped __cs__('global::Loreline.IFields f = (global::Loreline.IFields){0}', fields);
        return untyped __cs__('f.LorelineGet((global::Loreline.Interpreter)({0}), {1})', @:privateAccess interpreter?.wrapper, name);
    }

    public static function setCsFieldsValue(?interpreter:Interpreter, fields:Any, name:String, value:Any):Void {
        untyped __cs__('global::Loreline.IFields f = (global::Loreline.IFields){0}', fields);
        untyped __cs__('f.LorelineSet((global::Loreline.Interpreter)({0}), {1}, {2})', @:privateAccess interpreter?.wrapper, name, value);
    }

    public static function csFieldsKeyExists(?interpreter:Interpreter, fields:Any, name:String):Bool {
        untyped __cs__('global::Loreline.IFields f = (global::Loreline.IFields){0}', fields);
        return untyped __cs__('f.LorelineExists((global::Loreline.Interpreter)({0}), {1})', @:privateAccess interpreter?.wrapper, name);
    }

    public static function getCsFieldsKeys(?interpreter:Interpreter, fields:Any):Array<String> {
        untyped __cs__('global::Loreline.IFields f = (global::Loreline.IFields){0}', fields);
        final keys:Array<String> = [];
        untyped __cs__('foreach (string fieldsKey in f.LorelineFields((global::Loreline.Interpreter)({0}))) {', @:privateAccess interpreter?.wrapper);
        final key:String = null;
        untyped __cs__('{0} = fieldsKey', key);
        keys.push(key);
        untyped __cs__('}');
        return keys;
    }

    #end

}