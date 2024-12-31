package loreline;

import haxe.Json;
import loreline.Error;
import loreline.Interpreter;
import sys.FileSystem;
import sys.io.File;

using StringTools;
using loreline.Colors;

enum CliCommand {

    PLAY;

    JSON;

}

@:structInit
class CliOptions {

}

class Cli {

    public static function main() {
        new Cli();
    }

    var options:CliOptions = {};

    function new() {

        final args = Sys.args();

        if (args.length >= 1) {
            switch args[0] {
                case 'play':
                    if (args.length >= 2)
                        play(args[1]);
                    else
                        fail('Missing file argument');
                case _:
                    help();
            }
        }
        else {
            help();
        }

    }

    function help() {

        print("  _                _ _            ".green());
        print(" | | ___  _ __ ___| (_)_ __   ___ ".green());
        print(" | |/ _ \\| '__/ _ \\ | | '_ \\ / _ \\".green());
        print(" | | (_) | | |  __/ | | | | |  __/".green());
        print(" |_|\\___/|_|  \\___|_|_|_| |_|\\___|".green());
        print("");
        print(" " + "USAGE".bold());
        print(" loreline " + "[".gray() + "play" + "|".gray() + "json" + "]".gray() + " " + "story.lor".underline());
        print("");

    }

    function play(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content);

            Loreline.play(
                script,
                handleDialogue,
                handleChoice,
                () -> {}
            );
        }
        catch (e:Any) {
            if (e is Array) {
                for (err in (e:Array<Any>)) {
                    fail(err, file);
                }
            }
            else {
                fail(e, file);
            }
        }

    }

    function handleDialogue(character:String, text:String, tags:Array<TextTag>, callback:()->Void):Void {

        if (character != null) {
            print(
                character.cyan() + " " + text.green()
            );
        }
        else {
            print(
                text.green()
            );
        }

        print('');

        callback();

    }

    function handleChoice(options:Array<ChoiceOption>, callback:(index:Int)->Void):Void {

        //

    }

    function argValue(args:Array<String>, name:String, required:Bool = false):String {

        var index = args.indexOf('--$name');

        if (index == -1) {
            if (required) {
                fail('Argument --$name is required');
            }
            return null;
        }

        if (index + 1 >= args.length) {
            fail('A value is required after --$name argument.');
        }

        var value = args[index + 1];

        return value;

    }

    function argFlag(args:Array<String>, name:String):Bool {

        var index = args.indexOf('--$name');

        if (index == -1) {
            return false;
        }

        return true;

    }

    function print(str:String):Void {
        Sys.stdout().writeString(str + '\n');
    }

    function error(err:Any, ?file:String):Void {
        if (err is Error) {
            final e:Error = cast err;
            Sys.stderr().writeString(e.message.red());
            Sys.stderr().writeString(' ');
            if (file != null && file.trim().length > 0) {
                Sys.stderr().writeString(
                    (file.trim() + ':' + e.pos.line + ':' + e.pos.column).gray()
                );
            }
            Sys.stderr().writeString('\n');
        }
        else {
            Sys.stderr().writeString(Std.string(err).red() + '\n');
        }
    }

    function fail(?message:String, ?file:String):Void {
        if (message != null) {
            error(message, file);
            error('');
        }
        Sys.exit(1);
    }

}