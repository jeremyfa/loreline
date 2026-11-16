package loreline.lib;

import loreline.Interpreter;

class GoOptions {

    var functions:FunctionsMap = null;

    var strictAccess:Bool = false;

    var translations:GoTranslations = null;

    public function new() {}

    @:go.Export
    public function addFunction(name:String, fn:(GoInterpreter, Array<Dynamic>) -> Dynamic):Void {
        if (functions == null) {
            functions = new FunctionsMap();
        }
        functions.set(name, (interpreter:Interpreter, args:Array<Dynamic>) -> {
            return fn(GoInterpreter.of(interpreter), [for (arg in args) GoLibrary.toHost(interpreter, arg)]);
        });
    }

    @:go.Export
    public function setStrictAccess(strictAccess:Bool):Void {
        this.strictAccess = strictAccess;
    }

    @:go.Export
    public function setTranslations(translations:GoTranslations):Void {
        this.translations = translations;
    }

    public static function build(options:GoOptions):InterpreterOptions {
        if (options == null) {
            return null;
        }
        return {
            functions: options.functions,
            strictAccess: options.strictAccess,
            translations: options.translations != null ? options.translations.translations : null
        };
    }

}
