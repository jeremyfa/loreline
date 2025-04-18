package loreline.cli;

import haxe.CallStack.StackItem;
import haxe.CallStack;
import haxe.Json;
import haxe.io.Path;
import loreline.Error;
import loreline.Interpreter;
import loreline.Lens;
import loreline.test.TestCase;
import loreline.test.TestRunner;
import sys.FileSystem;
import sys.io.File;

using StringTools;
using loreline.Utf8;
using loreline.cli.CliColors;

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

    public static function lorelineVersion():String {
        #if !cppia
        static final fullVersion = '${CliMacros.lorelineVersion()}-${CliMacros.gitCommitShortHash()}';
        return fullVersion;
        #else
        return null;
        #end
    }

    var errorInStdOut:Bool = false;

    var typeDelay:Float = 0.005;

    var sentenceDelay:Float = 0.2;

    var showDisabled:Bool = false;

    var lastCharacter:String = null;

    var loadedSave:Bool = false;

    var hasFailedTest:Bool = false;

    function new() {

        #if loreline_debug_interpreter
        Interpreter.debug = (message, ?pos) -> {
            haxe.Log.trace(message.magenta(), pos);
            print('');
        };
        #end

        final args = [].concat(Sys.args());

        #if neko
        if (args.length > 0 && FileSystem.exists(args[args.length-1]) && FileSystem.isDirectory(args[args.length-1])) {
            Sys.setCwd(args.pop());
        }
        #end

        var i = 2;
        while (i < args.length) {
            if (args[i] == '--show-disabled') {
                showDisabled = true;
                args.splice(i, 1);
            }
            else {
                i++;
            }
        }

        if (args.length >= 1) {
            switch args[0] {

                case 'version':
                    print('v' + lorelineVersion());

                case 'play':
                    if (args.length >= 2)
                        play(args[1]);
                    else
                        fail('Missing file argument');

                case 'json':
                    if (args.length >= 2)
                        json(args[1]);
                    else
                        fail('Missing file argument');

                case 'ast':
                    if (args.length >= 2)
                        ast(args[1]);
                    else
                        fail('Missing file argument');

                case 'test':
                    if (args.length >= 2)
                        test(args[1]);
                    else
                        fail('Missing path argument');

                case 'format':
                    if (args.length >= 2)
                        format(args[1]);
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
        print((" | | ___  _ __ ___| (_)_ __   ___   v" + lorelineVersion()).green());
        print(" | |/ _ \\| '__/ _ \\ | | '_ \\ / _ \\".green());
        print(" | | (_) | | |  __/ | | | | |  __/".green());
        print(" |_|\\___/|_|  \\___|_|_|_| |_|\\___|".green());
        print("");
        print(" " + "USAGE".bold());
        print(" loreline " + "[".gray() + "play" + "|".gray() + "json" + "|".gray() + "ast" + "]".gray() + " " + "story.lor".underline());
        print("");

    }

    function handleFile(path:String, cb:(content:String)->Void) {
        cb(File.getContent(path));
    }

    function json(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(Json.stringify(script.toJson(), null, '  '));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function ast(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(new AstPrinter().print(script));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function test(path:String) {

        for (crlf in [false, true]) {
            if (crlf) {
                print('[ CRLF ]'.cyan().bold());
                print('');
            }
            else {
                print('[ LF ]'.cyan().bold());
                print('');
            }
            if (FileSystem.exists(path) && FileSystem.isDirectory(path)) {
                var dir = path;
                for (file in FileSystem.readDirectory(dir)) {
                    if (file.endsWith('.lor')) {
                        testFile(Path.join([dir, file]), crlf);
                    }
                }
            }
            else {
                testFile(path, crlf);
            }

            print('');
        }

        if (hasFailedTest) {
            Sys.exit(1);
        }

    }

    function testFile(file:String, crlf:Bool) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            var content = File.getContent(file);
            if (crlf) {
                content = content.replace("\r\n", "\n").replace("\n", "\r\n");
            }
            else {
                content = content.replace("\r\n", "\n");
            }
            final script = Loreline.parse(content, file, handleFile);
            script.eachComment((node, comment) -> {
                if (comment.multiline) {
                    final testStart = comment.content.uIndexOf('<test>');
                    if (testStart != -1) {
                        final testEnd = comment.content.uIndexOf('</test>', testStart + 6);
                        if (testEnd != -1) {
                            final testYml = Yaml.parse(comment.content.uSubstring(testStart + 6, testEnd).trim());
                            if (testYml != null && testYml is Array) {
                                for (item in (testYml:Array<Dynamic>)) {
                                    final testCase = new InterpreterTestCase(
                                        file, content, file,
                                        item.beat, item.choices, null,
                                        item.expected
                                    );
                                    final testRunner = new TestRunner(handleFile);
                                    testRunner.runTestCase(testCase, result -> {
                                        final testCase:InterpreterTestCase = cast result.testCase;
                                        if (result.passed) {
                                            print('PASS'.green().bold() + ' - ' + file.gray() + (testCase.choices != null && testCase.choices.length > 0 ? ' ~ '.gray() + '[${testCase.choices.join(',')}]'.gray() : ''));
                                        }
                                        else {
                                            hasFailedTest = true;
                                            print('FAIL'.red().bold() + (result.error != null ? ' - ' + result.error : '') + ' - ' + file.gray() + (testCase.choices != null && testCase.choices.length > 0 ? ' ~ '.gray() + '[${testCase.choices.join(',')}]'.gray() : ''));

                                            if (TestRunner.compareOutput(testCase.expectedOutput, result.actualOutput) != -1) {

                                                print('');

                                                // Normalize line endings (CRLF -> LF) and trim whitespace
                                                final normalizedExpected = testCase.expectedOutput.replace("\r\n", "\n").trim().split("\n");
                                                final normalizedActual = result.actualOutput.replace("\r\n", "\n").trim().split("\n");

                                                final minLen = Std.int(Math.min(normalizedExpected.length, normalizedActual.length));
                                                final maxLen = Std.int(Math.max(normalizedExpected.length, normalizedActual.length));

                                                var foundDifference = false;
                                                var i = 0;
                                                while (i < minLen) {
                                                    if (normalizedExpected[i] == normalizedActual[i]) {
                                                        print(normalizedActual[i].yellow());
                                                    }
                                                    else {
                                                        print('> Unexpected output at line ${i+1}');
                                                        print('>  got: ' + normalizedActual[i].red());
                                                        print('> need: ' + normalizedExpected[i].yellow());
                                                        foundDifference = true;
                                                        break;
                                                    }
                                                    i++;
                                                }

                                                if (!foundDifference && i < maxLen) {
                                                    if (i < normalizedActual.length) {
                                                        while (i < maxLen && normalizedActual[i].trim().length <= 0) {
                                                            i++;
                                                        }
                                                        print('> Unexpected output at line ${i+1}');
                                                        print('>  got: ' + normalizedActual[i].red());
                                                        print('> need: ' + '(empty)'.yellow());
                                                    }
                                                    else {
                                                        while (i < maxLen && normalizedExpected[i].trim().length <= 0) {
                                                            i++;
                                                        }
                                                        print('> Unexpected output at line ${i+1}');
                                                        print('>  got: ' + '(empty)'.red());
                                                        print('> need: ' + normalizedExpected[i].yellow());
                                                    }
                                                }

                                                print('\n');
                                            }

                                        }
                                    });
                                }
                            }
                        }
                    }
                }
            });
        }
        catch (e:Any) {
            hasFailedTest = true;
            print('FAIL'.red().bold() + ' - $e - ' + file.gray());
        }

    }

    function format(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(new Printer().print(script));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function play(file:String) {

        print("");

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);

            final script = Loreline.parse(content, file, handleFile);

            errorInStdOut = true;

            Loreline.play(
                script,
                handleDialogue,
                handleChoice,
                _ -> {
                    // Finished script execution
                }
            );
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function handleDialogue(interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void):Void {

        final multiline = text.contains("\n");
        if (character != null) {
            character = interpreter.getCharacterField(character, 'name') ?? character;

            var tagItems = [];
            for (tag in tags) {
                if (tag.offset == 0 && !tag.closing) {
                    tagItems.push(("<" + tag.value + ">").cyan());
                }
            }
            var tagItemsText = "";
            if (tagItems.length > 0) {
                tagItemsText = tagItems.join("");
                if (!multiline) {
                    tagItemsText += " ";
                }
            }
            if (multiline) {
                text = "\n  " + text.replace("\n", "\n  ").rtrim();
            }
            type(
                " " + (character + ":").cyan().bold() + " " + tagItemsText + text.green()
            );
        }
        else {
            if (multiline) {
                text = text.replace("\n", "\n ").rtrim();
            }
            type(
                " " + text.cyan().italic()
            );
        }

        lastCharacter = character;

        print('');
        if (sentenceDelay > 0) {
            Sys.sleep(sentenceDelay);
        }

        callback();

    }

    function handleChoice(interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void):Void {

        lastCharacter = null;

        var index = 1;
        for (opt in options) {
            if (opt.enabled) {
                type(" " + '$index.'.yellow() + " " + opt.text);
                index++;
            }
            else if (showDisabled) {
                type((" " + '$index.' + " " + opt.text).gray());
                index++;
            }
        }

        print('');

        do {
            Sys.stdout().writeString(" " + ">".yellow() + " ");
            final input = Std.parseInt(Sys.stdin().readLine());
            if (input != null) {
                var index = 1;
                var i = 0;
                for (opt in options) {
                    if (opt.enabled || showDisabled) {
                        if (input == index) {
                            print('');
                            callback(i);
                            return;
                        }
                        index++;
                    }
                    i++;
                }
            }
        }
        while (true);

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

    /**
        Splits text into an array of "characters", where each ANSI sequence is kept with its following character.
        @param text The input text that may contain ANSI escape sequences
        @return Array<String> Array where each element is either a single character or an ANSI sequence + character
    **/
    static function splitWithAnsi(text:String):Array<String> {
        final result:Array<String> = [];
        static final ANSI = ~/[\x1B\x9B](?:[@-Z\\-_]|\[[0-?]*[ -\/]*[@-~]|\].*?(?:\x07|\x1B\\))/g; // Comprehensive ANSI pattern

        var currentIndex:Int = 0;
        var lastMatchEnd:Int = 0;

        // Helper to add non-ANSI characters
        inline function addPlainChars(start:Int, end:Int) {
            #if neko
            var chars = neko.Utf8.sub(text, start, end - start);
            #else
            var chars = text.substring(start, end);
            #end
            for (i in 0...chars.length) {
                #if neko
                result.push(neko.Utf8.sub(chars, i, 1));
                #else
                result.push(chars.charAt(i));
                #end
            }
        }

        // Process the string looking for ANSI sequences
        while (ANSI.matchSub(text, currentIndex)) {
            var matchPos = ANSI.matchedPos();

            // Add any plain characters before the ANSI sequence
            if (matchPos.pos > lastMatchEnd) {
                addPlainChars(lastMatchEnd, matchPos.pos);
            }

            // Get the ANSI sequence
            #if neko
            var ansiSeq = neko.Utf8.sub(text, matchPos.pos, matchPos.len);
            #else
            var ansiSeq = text.substr(matchPos.pos, matchPos.len);
            #end

            // Look ahead for any following ANSI sequences
            var nextPos = matchPos.pos + matchPos.len;
            var combinedAnsi = ansiSeq;
            while (ANSI.matchSub(text, nextPos)) {
                var nextMatch = ANSI.matchedPos();
                if (nextMatch.pos == nextPos) {
                    // Adjacent ANSI sequence found
                    #if neko
                    var nextSeq = neko.Utf8.sub(text, nextMatch.pos, nextMatch.len);
                    #else
                    var nextSeq = text.substr(nextMatch.pos, nextMatch.len);
                    #end
                    combinedAnsi += nextSeq;
                    nextPos = nextMatch.pos + nextMatch.len;
                }
                else {
                    break;
                }
            }

            // Get the character after the ANSI sequence(s)
            if (nextPos < text.length) {
                #if neko
                result.push(combinedAnsi + neko.Utf8.sub(text, nextPos, 1));
                #else
                result.push(combinedAnsi + text.charAt(nextPos));
                #end
                lastMatchEnd = nextPos + 1;
            }
            else {
                // Handle case where ANSI sequence is at the end
                result.push(combinedAnsi);
                lastMatchEnd = nextPos;
            }

            currentIndex = lastMatchEnd;
        }

        // Add any remaining characters after the last ANSI sequence
        if (lastMatchEnd < text.length) {
            addPlainChars(lastMatchEnd, text.length);
        }

        return result;

    }

    function type(str:String, delay:Float = -1):Void {
        if (delay == -1) {
            delay = this.typeDelay;
        }
        if (delay > 0) {
            for (part in splitWithAnsi(str)) {
                Sys.stdout().writeString(part);
                Sys.stdout().flush();
                Sys.sleep(delay);
            }
            Sys.stdout().writeString('\n');
            Sys.stdout().flush();
        }
        else {
            print(str);
            Sys.stdout().flush();
        }
    }

    function print(str:String):Void {
        Sys.stdout().writeString(str + '\n');
    }

    function error(err:Any, ?file:String):Void {
        inline function write(str:String) {
            if (errorInStdOut) {
                Sys.stdout().writeString(str);
            }
            else {
                Sys.stderr().writeString(str);
            }
        }
        if (err is Error) {
            final e:Error = cast err;
            write(e.message.red());
            write(' ');
            if (file != null && file.trim().length > 0) {
                write(
                    (file.trim() + ':' + e.pos.line + ':' + e.pos.column).gray()
                );
            }
            write('\n');
        }
        else {
            write(Std.string(err).red() + '\n');
        }
    }

    function fail(?message:String, ?file:String):Void {
        if (message != null) {
            error(message, file);
            error('');
        }
        Sys.exit(1);
    }

    function printStackTrace(returnOnly:Bool = false, ?stack:Array<StackItem>):String {

        var result = new loreline.Utf8.Utf8Buf();

        inline function print(data:Dynamic) {
            if (!returnOnly) {
                #if cs
                trace(data);
                #elseif android
                trace('' + data);
                #elseif sys
                this.error('' + data);
                #else
                trace(data);
                #end
            }
            result.add(data);
            result.addChar('\n'.code);
        }

        if (stack == null)
            stack = CallStack.callStack();

        // Reverse stack
        var reverseStack = [].concat(stack);
        reverseStack.reverse();
        reverseStack.pop(); // Remove last element, no need to display it

        // Print stack trace and error
        for (item in reverseStack) {
            print(stackItemToString(item));
        }

        return result.toString();

    }

    function stackItemToString(item:StackItem):String {
        static final pattern = ~/loreline\.([a-zA-Z]+)(?:\.[a-zA-Z]+)*::/;

        var str:String = "";
        switch (item) {
            case CFunction:
                str = "a C function";
            case Module(m):
                str = "module " + m;
            case FilePos(itm, file, line, column):
                if (itm != null) {
                    str = stackItemToString(itm);
                    str += ' ';
                }
                str += file;
                if (pattern.match(file)) {
                    var name = pattern.matched(1);
                    name = switch name {
                        case 'ParseError': 'Parser';
                        case _: name;
                    }
                    str += ' src/loreline/' + name + '.hx';
                }
                #if (!cpp || HXCPP_STACK_LINE)
                str += ":";
                str += line;
                #end
            case Method(cname, meth):
                str += (cname);
                str += (".");
                str += (meth);
            #if (haxe_ver >= "3.1.0")
            case LocalFunction(n):
            #else
            case Lambda(n):
            #end
                str += ("local function #");
                str += (n);
        }

        return str;

    }

}