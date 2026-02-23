package loreline.test;

import loreline.Imports;
import loreline.Interpreter;
import loreline.Loreline;
import loreline.SaveData;
import loreline.Script;
import loreline.Utf8;
import loreline.test.TestCase;

using StringTools;
using loreline.Utf8;

/**
 * A test runner for Loreline.
 * Executes test cases and compares the output to expected results.
 */
class TestRunner {

    /**
     * An array to collect test results.
     */
    public final results:Array<TestResult> = [];

    /**
     * The file handler used to load imports.
     */
    public final handleFile:ImportsFileHandler;

    public function new(handleFile:ImportsFileHandler) {
        this.handleFile = handleFile;
    }

    public function runTestCase(testCase:TestCase, done:(result:TestResult)->Void) {

        final clazz = Type.getClass(testCase);
        switch clazz {
            case InterpreterTestCase:
                runInterpreterTestCase(cast testCase, done);
            case _:
                done(new TestResult(
                    testCase, false, null, new Error('Cannot handle test case of type $clazz')
                ));
        }

    }

    function insertTagsInText(text:String, tags:Array<TextTag>, multiline:Bool):String {

        var offsetsWithTags = new Map<Int,Bool>();
        for (t in 0...tags.length) {
            final tag = tags[t];
            offsetsWithTags.set(tag.offset, true);
        }

        final len = text.uLength();
        final textBuf = new Utf8Buf();
        for (i in 0...len) {
            if (offsetsWithTags.exists(i)) {
                for (t in 0...tags.length) {
                    final tag = tags[t];
                    if (tag.offset == i) {
                        textBuf.addChar("<".code);
                        textBuf.addChar("<".code);
                        if (tag.closing) {
                            textBuf.addChar("/".code);
                        }
                        textBuf.add(tag.value);
                        textBuf.addChar(">".code);
                        textBuf.addChar(">".code);
                    }
                }
            }

            final c = text.uCharCodeAt(i);
            if (multiline && c == "\n".code) {
                textBuf.addChar("\n".code);
                textBuf.addChar(" ".code);
                textBuf.addChar(" ".code);
            }
            else {
                textBuf.addChar(c);
            }
        }
        for (t in 0...tags.length) {
            final tag = tags[t];
            if (tag.offset >= len) {
                textBuf.addChar("<".code);
                textBuf.addChar("<".code);
                if (tag.closing) {
                    textBuf.addChar("/".code);
                }
                textBuf.add(tag.value);
                textBuf.addChar(">".code);
                textBuf.addChar(">".code);
            }
        }

        text = textBuf.toString().rtrim();
        return text;

    }

    public static function compareOutput(expectedOutput:String, actualOutput:String):Int {

        // Normalize line endings (CRLF -> LF) and trim whitespace
        final normalizedExpected = expectedOutput.replace("\r\n", "\n").trim().split("\n");
        final normalizedActual = actualOutput.replace("\r\n", "\n").trim().split("\n");

        final minLen = Std.int(Math.min(normalizedExpected.length, normalizedActual.length));
        final maxLen = Std.int(Math.max(normalizedExpected.length, normalizedActual.length));

        var i = 0;
        while (i < minLen) {
            if (normalizedExpected[i] != normalizedActual[i]) return i;
            i++;
        }

        if (i < maxLen) {
            return i;
        }

        return -1;

    }

    function runInterpreterTestCase(testCase:InterpreterTestCase, done:(result:TestResult)->Void) {

        final output = new Utf8Buf();
        final choices = testCase.choices != null ? [].concat(testCase.choices) : null;
        var choiceCount:Int = 0;
        var dialogueCount:Int = 0;
        var parsedScript:Script = null;

        // Pre-declare handleChoice so handleDialogue can reference it
        // (mutual reference: both save paths use Loreline.resume with both handlers)
        var handleChoice:(Interpreter, Array<ChoiceOption>, (Int)->Void)->Void = null;

        function handleFinish(interpreter:Interpreter) {

            final actualOutput = output.toString();
            final compareResult = compareOutput(testCase.expectedOutput, actualOutput);
            final passed = (compareResult == -1);

            done(new TestResult(
                testCase, passed, actualOutput, null
            ));

        }

        function handleDialogue(interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void) {
            final multiline = text.contains("\n");
            if (character != null) {
                character = interpreter.getCharacterField(character, 'name') ?? character;

                output.add(character);
                output.addChar(":".code);

                text = insertTagsInText(text, tags, multiline);

                if (multiline) {
                    output.addChar("\n".code);
                    output.addChar(" ".code);
                    output.addChar(" ".code);
                    output.add(text);
                }
                else {
                    output.addChar(" ".code);
                    output.add(text);
                }
            }
            else {
                text = insertTagsInText(text, tags, multiline);
                output.addChar("~".code);
                output.addChar(" ".code);
                output.add(text);
            }
            output.addChar("\n".code);
            output.addChar("\n".code);

            // Save/restore test: save at the specified dialogue event,
            // then resume on a new interpreter
            if (testCase.saveAtDialogue >= 0 && dialogueCount == testCase.saveAtDialogue) {
                dialogueCount++;
                final saveData:SaveData = interpreter.save();

                if (testCase.restoreInput != null) {
                    // Parse the modified script and resume with it
                    Loreline.parse(testCase.restoreInput, testCase.filePath, handleFile, restoreScript -> {
                        if (restoreScript != null) {
                            Loreline.resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData);
                        } else {
                            done(new TestResult(testCase, false, output.toString(), new Error('Error parsing restoreInput script')));
                        }
                    });
                } else {
                    // Resume on a new interpreter (handlers are closures sharing the same state)
                    Loreline.resume(
                        parsedScript,
                        handleDialogue,
                        handleChoice,
                        handleFinish,
                        saveData
                    );
                }
                return;
            }

            dialogueCount++;
            callback();
        }

        handleChoice = function(interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void) {

            for (opt in options) {
                if (opt.enabled) {
                    output.addChar("+".code);
                }
                else {
                    output.addChar("-".code);
                }
                final multiline = opt.text.contains("\n");
                final text = insertTagsInText(opt.text, opt.tags, multiline);
                if (multiline) {
                    output.addChar(" ".code);
                    output.add(text);
                }
                else {
                    output.addChar(" ".code);
                    output.add(text);
                }
                output.addChar("\n".code);
            }
            output.addChar("\n".code);

            // Save/restore test: save at the specified choice point,
            // then resume on a new interpreter
            if (testCase.saveAtChoice >= 0 && choiceCount == testCase.saveAtChoice) {
                choiceCount++;
                final saveData:SaveData = interpreter.save();

                if (testCase.restoreInput != null) {
                    // Parse the modified script and resume with it
                    Loreline.parse(testCase.restoreInput, testCase.filePath, handleFile, restoreScript -> {
                        if (restoreScript != null) {
                            Loreline.resume(restoreScript, handleDialogue, handleChoice, handleFinish, saveData);
                        } else {
                            done(new TestResult(testCase, false, output.toString(), new Error('Error parsing restoreInput script')));
                        }
                    });
                } else {
                    // Resume on a new interpreter (handlers are closures sharing the same state)
                    Loreline.resume(
                        parsedScript,
                        handleDialogue,
                        handleChoice,
                        handleFinish,
                        saveData
                    );
                }
                return;
            }

            choiceCount++;

            if (choices == null || choices.length == 0) {
                // Early finish when no choices
                handleFinish(interpreter);
            }
            else {
                final index = choices.shift();
                callback(index);
            }

        };

        try {
            // Parse the script
            Loreline.parse(testCase.input, testCase.filePath, handleFile, script -> {

                if (script != null) {
                    parsedScript = script;

                    // Execute the script
                    Loreline.play(
                        script,
                        handleDialogue,
                        handleChoice,
                        handleFinish,
                        testCase.beatName,
                        testCase.options
                    );

                }
                else {
                    done(new TestResult(
                        testCase, false, output.toString(), new Error('Error when parsing script')
                    ));
                }

            });
        }
        catch (e:Any) {
            if (e is Error) {
                done(new TestResult(
                    testCase, false, output.toString(), e
                ));
            }
            else {
                done(new TestResult(
                    testCase, false, output.toString(), new Error('Failed to run interpreter test case: ' + e)
                ));
            }
        }

    }

}
