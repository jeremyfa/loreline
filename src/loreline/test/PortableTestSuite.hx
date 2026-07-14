package loreline.test;

import loreline.Imports.ImportsFileHandler;
import loreline.Interpreter;
import loreline.Json;
import loreline.Loreline;
import loreline.MiniYaml;
import loreline.Script;
import loreline.test.TestCase;
import loreline.test.TestRunner;

using StringTools;
using loreline.Utf8;

/**
 * Target-agnostic test suite runner: replicates the CLI's per-file
 * interpreter tests (LF and CRLF), the printer roundtrip checks, and the
 * JSON roundtrip checks, without any sys dependency. The host provides
 * file reading and printing callbacks, making this usable from targets
 * like GDScript where the embedding environment does the I/O.
 */
@:keep
class PortableTestSuite {

    /** Reads a file synchronously, returning null if missing. */
    public final readFile:(path:String)->Null<String>;

    /** Prints one line of runner output. */
    public final printLine:(line:String)->Void;

    public var passCount(default, null):Int = 0;

    public var failCount(default, null):Int = 0;

    public var fileCount(default, null):Int = 0;

    public var fileFailCount(default, null):Int = 0;

    public function new(readFile:(path:String)->Null<String>, printLine:(line:String)->Void) {
        this.readFile = readFile;
        this.printLine = printLine;

        // Test fixtures exercise every supported translation format.
        Loreline.translationFormat("po", true);
        Loreline.translationFormat("xliff", true);
        Loreline.translationFormat("csv", true);
    }

    function handleFile(path:String, cb:(content:String)->Void):Void {
        cb(readFile(path));
    }

    static function customTestFunctions():loreline.Interpreter.FunctionsMap {
        // FunctionsMap is a DynamicAccess under loreline_functions_map_dynamic_access
        // (js/lua/python/gdscript builds) and a StringMap otherwise; set() exists
        // on both.
        final fns:loreline.Interpreter.FunctionsMap = #if loreline_functions_map_dynamic_access {} #else new Map<String, Any>() #end;
        fns.set("custom_echo", (interp:Interpreter, args:Array<Any>) -> [for (a in args) Std.string(a)].join(","));
        fns.set("custom_arg_count", (interp:Interpreter, args:Array<Any>) -> args.length);
        fns.set("custom_set_state", (interp:Interpreter, args:Array<Any>) -> { interp.setStateField(args[0], args[1]); null; });
        fns.set("custom_get_state", (interp:Interpreter, args:Array<Any>) -> interp.getStateField(args[0]));
        return fns;
    }

    /**
     * Runs every check for one .lor file: interpreter test items in LF and
     * CRLF modes, printer roundtrip (LF and CRLF) and JSON roundtrip
     * (LF and CRLF).
     * @param filePath Path of the file (used for imports resolution and labels)
     * @param rawContent The raw file content
     */
    public function runFile(filePath:String, rawContent:String):Void {

        fileCount++;
        final failBefore = failCount;

        // Interpreter tests
        for (crlf in [false, true]) {
            runInterpreterTests(filePath, rawContent, crlf);
        }

        // Printer roundtrip
        for (crlf in [false, true]) {
            runRoundtrip(filePath, rawContent, crlf);
        }

        // JSON roundtrip
        for (crlf in [false, true]) {
            runJsonRoundtrip(filePath, rawContent, crlf);
        }

        if (failCount > failBefore) fileFailCount++;

    }

    function normalize(content:String, crlf:Bool):String {
        var result = content.replace("\r\n", "\n");
        if (crlf) result = result.replace("\n", "\r\n");
        return result;
    }

    function collectTestItems(script:Script, filePath:String, crlf:Bool):{ items:Array<Dynamic>, restoreInputs:Array<String> } {
        final testItems:Array<Dynamic> = [];
        final restoreInputs:Array<String> = [];
        script.eachComment((node, comment) -> {
            if (comment.multiline) {
                final testStart = comment.content.uIndexOf('<test>');
                if (testStart != -1) {
                    final testEnd = comment.content.uIndexOf('</test>', testStart + 6);
                    if (testEnd != -1) {
                        final testYml = MiniYaml.parse(comment.content.uSubstring(testStart + 6, testEnd).trim());
                        if (testYml != null && testYml is Array) {
                            for (item in (testYml:Array<Dynamic>)) {
                                var restoreInput:String = null;
                                if (item.restoreFile != null) {
                                    final restorePath = directory(filePath) + "/" + item.restoreFile;
                                    final restoreContent = readFile(restorePath);
                                    if (restoreContent != null) {
                                        restoreInput = normalize(restoreContent, crlf);
                                    }
                                }
                                testItems.push(item);
                                restoreInputs.push(restoreInput);
                            }
                        }
                    }
                }
            }
        });
        return { items: testItems, restoreInputs: restoreInputs };
    }

    static function directory(path:String):String {
        final normalized = path.replace("\\", "/");
        final idx = normalized.lastIndexOf("/");
        return idx >= 0 ? normalized.substring(0, idx) : ".";
    }

    function runInterpreterTests(filePath:String, rawContent:String, crlf:Bool):Void {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        try {
            final content = normalize(rawContent, crlf);
            final script = Loreline.parse(content, filePath, handleFile);
            final collected = collectTestItems(script, filePath, crlf);

            for (idx in 0...collected.items.length) {
                final item = collected.items[idx];
                final restoreInput = collected.restoreInputs[idx];
                final rawSaveAtChoice:Null<Int> = item.saveAtChoice;
                final rawSaveAtDialogue:Null<Int> = item.saveAtDialogue;
                final saveAtChoice:Int = rawSaveAtChoice != null ? rawSaveAtChoice : -1;
                final saveAtDialogue:Int = rawSaveAtDialogue != null ? rawSaveAtDialogue : -1;
                var options:InterpreterOptions = ({functions: customTestFunctions()} : InterpreterOptions);
                if (item.translation != null) {
                    final lang:String = item.translation;
                    final translations = Loreline.loadLocale(lang, script, filePath, handleFile);
                    if (translations != null) {
                        options = ({functions: customTestFunctions(), translations: translations} : InterpreterOptions);
                    }
                }
                final testCase = new InterpreterTestCase(
                    filePath, content, filePath,
                    item.beat, item.choices, options,
                    saveAtChoice, saveAtDialogue, restoreInput, item.expected
                );
                final testRunner = new TestRunner(handleFile);
                testRunner.runTestCase(testCase, result -> {
                    final resultCase:InterpreterTestCase = cast result.testCase;
                    final choicesLabel = resultCase.choices != null && resultCase.choices.length > 0 ? ' ~ [' + resultCase.choices.join(',') + ']' : '';
                    final label = filePath + ' ~ ' + modeLabel + choicesLabel;
                    if (result.passed) {
                        passCount++;
                        printLine('PASS - ' + label);
                    }
                    else {
                        failCount++;
                        printLine('FAIL - ' + label + (result.error != null ? ' - ' + result.error : ''));
                        printDiff(resultCase.expectedOutput, result.actualOutput);
                    }
                });
            }
        }
        catch (e:Any) {
            failCount++;
            printLine('FAIL - ' + filePath + ' ~ ' + modeLabel);
            printLine('  Error: ' + Std.string(e));
        }
    }

    function printDiff(expectedOutput:String, actualOutput:String):Void {
        if (expectedOutput == null || actualOutput == null) return;
        final normalizedExpected = expectedOutput.replace("\r\n", "\n").trim().split("\n");
        final normalizedActual = actualOutput.replace("\r\n", "\n").trim().split("\n");
        final minLen = Std.int(Math.min(normalizedExpected.length, normalizedActual.length));
        for (i in 0...minLen) {
            if (normalizedExpected[i] != normalizedActual[i]) {
                printLine('  > Unexpected output at line ' + (i + 1));
                printLine('  >  got: ' + normalizedActual[i]);
                printLine('  > need: ' + normalizedExpected[i]);
                return;
            }
        }
        if (minLen < normalizedActual.length) {
            printLine('  > Unexpected output at line ' + (minLen + 1));
            printLine('  >  got: ' + normalizedActual[minLen]);
            printLine('  > need: (empty)');
        }
        else if (minLen < normalizedExpected.length) {
            printLine('  > Unexpected output at line ' + (minLen + 1));
            printLine('  >  got: (empty)');
            printLine('  > need: ' + normalizedExpected[minLen]);
        }
    }

    function runRoundtrip(filePath:String, rawContent:String, crlf:Bool):Void {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        final label = filePath + ' ~ ' + modeLabel + ' ~ roundtrip';
        final newline = crlf ? "\r\n" : "\n";
        try {
            final content = normalize(rawContent, crlf);

            final script1 = Loreline.parse(content, filePath, handleFile);
            if (script1 == null) {
                failCount++;
                printLine('FAIL - ' + label);
                printLine('  Error: Failed to parse original script');
                return;
            }

            // Structural check: print -> parse -> print must be stable
            final print1 = Loreline.print(script1, '  ', newline);
            final script2 = Loreline.parse(print1, filePath, handleFile);
            if (script2 == null) {
                failCount++;
                printLine('FAIL - ' + label);
                printLine('  Error: Failed to parse printed script');
                return;
            }
            final print2 = Loreline.print(script2, '  ', newline);

            if (print1 != print2) {
                failCount++;
                printLine('FAIL - ' + label);
                final lines1 = print1.replace("\r\n", "\n").split("\n");
                final lines2 = print2.replace("\r\n", "\n").split("\n");
                final ml = Std.int(Math.min(lines1.length, lines2.length));
                for (i in 0...ml) {
                    if (lines1[i] != lines2[i]) {
                        printLine('  > Printer output not idempotent at line ' + (i + 1));
                        printLine('  >  print1: ' + lines1[i]);
                        printLine('  >  print2: ' + lines2[i]);
                        break;
                    }
                }
                if (lines1.length != lines2.length) {
                    printLine('  > Line count differs: print1=' + lines1.length + ', print2=' + lines2.length);
                }
                return;
            }

            // Behavioral check: run each test item on the printed content
            final collected = collectTestItems(script1, filePath, crlf);
            var allPassed = true;
            var firstError:String = null;
            var firstExpected:String = null;
            var firstActual:String = null;

            for (idx in 0...collected.items.length) {
                final item = collected.items[idx];
                final restoreInput = collected.restoreInputs[idx];
                final rawSaveAtChoice:Null<Int> = item.saveAtChoice;
                final rawSaveAtDialogue:Null<Int> = item.saveAtDialogue;
                final saveAtChoice:Int = rawSaveAtChoice != null ? rawSaveAtChoice : -1;
                final saveAtDialogue:Int = rawSaveAtDialogue != null ? rawSaveAtDialogue : -1;
                var options:InterpreterOptions = ({functions: customTestFunctions()} : InterpreterOptions);
                if (item.translation != null) {
                    final lang:String = item.translation;
                    final translations = Loreline.loadLocale(lang, script1, filePath, handleFile);
                    if (translations != null) {
                        options = ({functions: customTestFunctions(), translations: translations} : InterpreterOptions);
                    }
                }
                final testCase = new InterpreterTestCase(
                    filePath, print1, filePath,
                    item.beat, item.choices, options,
                    saveAtChoice, saveAtDialogue, restoreInput, item.expected
                );
                final testRunner = new TestRunner(handleFile);
                testRunner.runTestCase(testCase, result -> {
                    if (!result.passed) {
                        allPassed = false;
                        if (firstError == null) {
                            firstError = result.error != null ? Std.string(result.error) : null;
                            firstExpected = testCase.expectedOutput;
                            firstActual = result.actualOutput;
                        }
                    }
                });
            }

            if (allPassed) {
                passCount++;
                printLine('PASS - ' + label);
            }
            else {
                failCount++;
                printLine('FAIL - ' + label);
                if (firstError != null) {
                    printLine('  Error: ' + firstError);
                }
                if (firstExpected != null && firstActual != null) {
                    printDiff(firstExpected, firstActual);
                }
            }
        }
        catch (e:Any) {
            failCount++;
            printLine('FAIL - ' + label);
            printLine('  Error: ' + Std.string(e));
        }
    }

    function runJsonRoundtrip(filePath:String, rawContent:String, crlf:Bool):Void {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        final label = filePath + ' ~ ' + modeLabel + ' ~ json-roundtrip';
        try {
            final content = normalize(rawContent, crlf);
            final script = Loreline.parse(content, filePath, handleFile);
            if (script == null) {
                failCount++;
                printLine('FAIL - ' + label);
                printLine('  Error: Failed to parse script');
                return;
            }
            final json1 = Json.stringify(script.toJson());
            final script2 = Script.fromJson(Json.parse(json1));
            final json2 = Json.stringify(script2.toJson());

            if (json1 == json2) {
                passCount++;
                printLine('PASS - ' + label);
            }
            else {
                failCount++;
                printLine('FAIL - ' + label);
                printLine('  > JSON mismatch after roundtrip');
            }
        }
        catch (e:Any) {
            failCount++;
            printLine('FAIL - ' + label);
            printLine('  Error: ' + Std.string(e));
        }
    }

    /**
     * Prints the final summary in the same format as the other runners.
     * @return True if every test passed
     */
    public function printSummary():Bool {
        final total = passCount + failCount;
        printLine('');
        if (failCount == 0) {
            printLine('  All ' + total + ' tests passed (' + fileCount + ' files)');
            return true;
        }
        else {
            printLine('  ' + failCount + ' of ' + total + ' tests failed (' + fileFailCount + ' of ' + fileCount + ' files)');
            return false;
        }
    }

}
