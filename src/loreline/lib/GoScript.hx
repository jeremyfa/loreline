package loreline.lib;

import go.Error;
import go.Tuple;
import loreline.Interpreter;
import loreline.Loreline;
import loreline.Script;

typedef GoDialogueHandler = (GoInterpreter, String, String, Array<TextTag>, () -> Void) -> Void;

typedef GoChoiceHandler = (GoInterpreter, Array<ChoiceOption>, Int -> Void) -> Void;

typedef GoFinishHandler = GoInterpreter -> Void;

class GoScript extends GoNode {

    public final script:Script;

    public function new(script:Script) {
        super(script);
        this.script = script;
    }

    @:go.Export
    @:go.Tuple('interpreter', 'err')
    public function play(dialogue:GoDialogueHandler, choice:GoChoiceHandler, finish:GoFinishHandler, beat:String, options:GoOptions):Tuple<{ interpreter:GoInterpreter, err:Error }> {
        try {
            final interpreter = Loreline.play(
                script,
                GoInterpreter.dialogueHandler(dialogue),
                GoInterpreter.choiceHandler(choice),
                GoInterpreter.finishHandler(finish),
                GoLibrary.emptyToNull(beat),
                GoOptions.build(options)
            );
            return { interpreter: GoInterpreter.of(interpreter), err: null };
        }
        catch (e:Any) {
            return { interpreter: null, err: GoLibrary.toError(e) };
        }
    }

    @:go.Export
    @:go.Tuple('interpreter', 'err')
    public function resume(dialogue:GoDialogueHandler, choice:GoChoiceHandler, finish:GoFinishHandler, save:String, beat:String, options:GoOptions):Tuple<{ interpreter:GoInterpreter, err:Error }> {
        try {
            final interpreter = Loreline.resume(
                script,
                GoInterpreter.dialogueHandler(dialogue),
                GoInterpreter.choiceHandler(choice),
                GoInterpreter.finishHandler(finish),
                loreline.Json.parse(save),
                GoLibrary.emptyToNull(beat),
                GoOptions.build(options)
            );
            return { interpreter: GoInterpreter.of(interpreter), err: null };
        }
        catch (e:Any) {
            return { interpreter: null, err: GoLibrary.toError(e) };
        }
    }

    @:go.Export
    public function print(indent:String, newline:String):String {
        return Loreline.print(script, indent, newline);
    }

}
