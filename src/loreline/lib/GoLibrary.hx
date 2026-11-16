package loreline.lib;

import go.Error;
import go.Errors;
import go.Tuple;
import haxe.ValueException;
import loreline.Imports.ImportsFileHandler;
import loreline.Interpreter;
import loreline.Loreline;

@:keep
class GoLibrary {

    static function main() {}

    public static function message(e:Any):String {
        if (e is ValueException) {
            return Std.string((cast e:ValueException).value);
        }
        return Std.string(e);
    }

    public static function toError(e:Any):Error {
        return Errors._new(message(e));
    }

    public static function emptyToNull(value:String):String {
        return value == null || value.length == 0 ? null : value;
    }

    public static function fileHandler(readFile:String -> String):ImportsFileHandler {
        return readFile == null ? null : (path, callback) -> callback(readFile(path));
    }

    public static function toHost(interpreter:Interpreter, value:Any, depth:Int = 0):Any {
        if (value == null || value is String || value is Int || value is Float || value is Bool || depth > 32) {
            return value;
        }
        if (Arrays.isArray(value)) {
            return [for (i in 0...Arrays.arrayLength(value)) toHost(interpreter, Arrays.arrayGet(value, i), depth + 1)];
        }
        if (value is Fields || value is haxe.ds.StringMap) {
            final result:haxe.DynamicAccess<Any> = {};
            for (name in Objects.getFields(interpreter, value)) {
                result.set(name, toHost(interpreter, Objects.getField(interpreter, value, name), depth + 1));
            }
            return result;
        }
        return value;
    }

    public function new() {}

    @:go.Export
    @:go.Tuple('script', 'err')
    public function parse(source:String, path:String, readFile:String -> String):Tuple<{ script:GoScript, err:Error }> {
        try {
            final script = Loreline.parse(source, emptyToNull(path), fileHandler(readFile));
            if (script == null) {
                final e = Loreline.lastError();
                return { script: null, err: Errors._new(e != null ? Std.string(e) : "Failed to parse script") };
            }
            return { script: new GoScript(script), err: null };
        }
        catch (e:Any) {
            return { script: null, err: toError(e) };
        }
    }

    @:go.Export
    @:go.Tuple('script', 'err')
    public function scriptFromJson(json:String):Tuple<{ script:GoScript, err:Error }> {
        try {
            return { script: new GoScript(Script.fromJson(loreline.Json.parse(json))), err: null };
        }
        catch (e:Any) {
            return { script: null, err: toError(e) };
        }
    }

    @:go.Export
    @:go.Tuple('node', 'err')
    public function nodeFromJson(json:String):Tuple<{ node:GoNode, err:Error }> {
        try {
            return { node: new GoNode(Node.fromJson(loreline.Json.parse(json))), err: null };
        }
        catch (e:Any) {
            return { node: null, err: toError(e) };
        }
    }

    @:go.Export
    public function extractTranslations(script:GoScript):GoTranslations {
        return new GoTranslations(Loreline.extractTranslations(script.script));
    }

    @:go.Export
    @:go.Tuple('translations', 'err')
    public function loadLocale(locale:String, script:GoScript, path:String, readFile:String -> String):Tuple<{ translations:GoTranslations, err:Error }> {
        try {
            final translations = Loreline.loadLocale(locale, script.script, emptyToNull(path), fileHandler(readFile));
            if (translations == null) {
                final e = Loreline.lastError();
                return { translations: null, err: Errors._new(e != null ? Std.string(e) : "Failed to load locale " + locale) };
            }
            return { translations: new GoTranslations(translations), err: null };
        }
        catch (e:Any) {
            return { translations: null, err: toError(e) };
        }
    }

    @:go.Export
    public function translationFormat(name:String, enabled:Bool):Void {
        Loreline.translationFormat(name, enabled);
    }

    @:go.Export
    public function update(delta:Float):Void {
        loreline.Timer.update(delta);
    }

    @:go.Export
    public function errorMessage(value:Dynamic):String {
        return message(value);
    }

}
