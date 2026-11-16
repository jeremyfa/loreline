package loreline.lib;

import go.Error;
import go.Tuple;
import loreline.Interpreter;
import loreline.lib.GoScript;

class GoInterpreter {

    public final interpreter:Interpreter;

    var hostValue:Dynamic = null;

    function new(interpreter:Interpreter) {
        this.interpreter = interpreter;
    }

    public static function of(interpreter:Interpreter):GoInterpreter {
        if (interpreter == null) {
            return null;
        }
        final existing:Any = @:privateAccess interpreter.wrapper;
        if (existing != null) {
            return cast existing;
        }
        final wrapper = new GoInterpreter(interpreter);
        @:privateAccess interpreter.wrapper = wrapper;
        return wrapper;
    }

    public static function dialogueHandler(handler:GoDialogueHandler):DialogueHandler {
        if (handler == null) {
            return null;
        }
        return (interpreter, character, text, tags, callback) -> handler(of(interpreter), character ?? "", text, tags, callback);
    }

    public static function choiceHandler(handler:GoChoiceHandler):ChoiceHandler {
        if (handler == null) {
            return null;
        }
        return (interpreter, options, callback) -> handler(of(interpreter), options, callback);
    }

    public static function finishHandler(handler:GoFinishHandler):FinishHandler {
        if (handler == null) {
            return null;
        }
        return interpreter -> handler(of(interpreter));
    }

    @:go.Export
    public function host():Dynamic {
        return hostValue;
    }

    @:go.Export
    public function setHost(value:Dynamic):Void {
        hostValue = value;
    }

    @:go.Export
    public function key():String {
        return interpreter.key ?? "";
    }

    @:go.Export
    public function isRoot():Bool {
        return interpreter.isRoot();
    }

    @:go.Export
    public function start(beat:String):Error {
        try {
            interpreter.start(GoLibrary.emptyToNull(beat));
            return null;
        }
        catch (e:Any) {
            return GoLibrary.toError(e);
        }
    }

    @:go.Export
    @:go.Tuple('save', 'err')
    public function save():Tuple<{ save:String, err:Error }> {
        try {
            return { save: loreline.Json.stringify(interpreter.save()), err: null };
        }
        catch (e:Any) {
            return { save: "", err: GoLibrary.toError(e) };
        }
    }

    @:go.Export
    public function restore(save:String):Error {
        try {
            interpreter.restore(loreline.Json.parse(save));
            return null;
        }
        catch (e:Any) {
            return GoLibrary.toError(e);
        }
    }

    @:go.Export
    public function resume():Error {
        try {
            interpreter.resume();
            return null;
        }
        catch (e:Any) {
            return GoLibrary.toError(e);
        }
    }

    @:go.Export
    @:go.Tuple('interpreter', 'err')
    public function spawn(key:String, dialogue:GoDialogueHandler, choice:GoChoiceHandler, finish:GoFinishHandler):Tuple<{ interpreter:GoInterpreter, err:Error }> {
        try {
            final child = interpreter.spawn(key, dialogueHandler(dialogue), choiceHandler(choice), finishHandler(finish));
            return { interpreter: of(child), err: null };
        }
        catch (e:Any) {
            return { interpreter: null, err: GoLibrary.toError(e) };
        }
    }

    @:go.Export
    @:go.Tuple('interpreter', 'err')
    public function resumeSpawn(key:String, dialogue:GoDialogueHandler, choice:GoChoiceHandler, finish:GoFinishHandler):Tuple<{ interpreter:GoInterpreter, err:Error }> {
        try {
            final child = interpreter.resumeSpawn(key, dialogueHandler(dialogue), choiceHandler(choice), finishHandler(finish));
            return { interpreter: of(child), err: null };
        }
        catch (e:Any) {
            return { interpreter: null, err: GoLibrary.toError(e) };
        }
    }

    @:go.Export
    public function resumableSpawnKeys():Array<String> {
        return interpreter.resumableSpawnKeys();
    }

    @:go.Export
    public function seedRandom(seed:Float):Void {
        interpreter.seedRandom(seed);
    }

    @:go.Export
    public function seedRandomFromClock():Void {
        interpreter.seedRandom();
    }

    @:go.Export
    public function dispose():Error {
        try {
            interpreter.dispose();
            return null;
        }
        catch (e:Any) {
            return GoLibrary.toError(e);
        }
    }

    @:go.Export
    public function character(name:String):Dynamic {
        return GoLibrary.toHost(interpreter, interpreter.getCharacter(name));
    }

    @:go.Export
    public function characterField(character:String, name:String):Dynamic {
        return GoLibrary.toHost(interpreter, interpreter.getCharacterField(character, name));
    }

    @:go.Export
    public function setCharacterField(character:String, name:String, value:Dynamic):Void {
        interpreter.setCharacterField(character, name, value);
    }

    @:go.Export
    public function stateField(name:String):Dynamic {
        return GoLibrary.toHost(interpreter, interpreter.getStateField(name));
    }

    @:go.Export
    public function setStateField(name:String, value:Dynamic):Void {
        interpreter.setStateField(name, value);
    }

    @:go.Export
    public function topLevelStateField(name:String):Dynamic {
        return GoLibrary.toHost(interpreter, interpreter.getTopLevelStateField(name));
    }

    @:go.Export
    public function setTopLevelStateField(name:String, value:Dynamic):Void {
        interpreter.setTopLevelStateField(name, value);
    }

    @:go.Export
    public function currentNode():GoNode {
        final node = interpreter.currentNode();
        return node != null ? new GoNode(node) : null;
    }

}
