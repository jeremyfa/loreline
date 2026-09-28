package loreline.test;

import loreline.Imports.ImportsFileHandler;
import loreline.Interpreter;
import loreline.Lens;
import loreline.Node;
import loreline.Script;
import loreline.test.TestCase;
import loreline.test.TestRunner;

using StringTools;

/**
 * One output event of a test run: a dialogue or a choice, as rendered by TestRunner.
 */
private typedef SweepEvent = {
    /** "dialogue" or "choice" */
    var kind:String;
    /** Index among the events of the same kind (what saveAtDialogue/saveAtChoice count) */
    var kindIndex:Int;
    /** Index of the rendered chunk in the output */
    var chunkIndex:Int;
}

/**
 * Save sweep: for each test case of a file, saves and restores at every event of the
 * run (every dialogue, every choice), and checks that the output is the output of an
 * uninterrupted run with the saved event shown twice (the restore re-presents it).
 * Files with insertions also get every pair of saves (save, restore, save again later,
 * restore again).
 *
 * The expected output is always derived from the uninterrupted run, never from the
 * save/restore path under test.
 *
 * Not swept: cases that already save (saveAt*), restore on a modified script
 * (restoreFile), opt out with `saveSweep: false`, or use randomness (the random
 * generator is not part of save data, so a restored run can't match).
 */
@:keep
class SaveSweep {

    /** Total number of save/restore runs checked, across all files */
    public static var checkedRuns(default, null):Int = 0;

    /** Files skipped because they use randomness */
    public static final skippedFiles:Array<String> = [];

    /**
     * Sweeps every test case of a file.
     *
     * @param report Called once per test case with null (passed) or an error description
     */
    public static function sweepFile(
        filePath:String,
        content:String,
        script:Script,
        items:Array<Dynamic>,
        restoreInputs:Array<String>,
        makeOptions:(item:Dynamic)->InterpreterOptions,
        handleFile:ImportsFileHandler,
        report:(label:String, error:Null<String>)->Void
    ):Void {

        if (usesRandomness(script)) {
            skippedFiles.push(filePath);
            return;
        }

        final withPairs = hasInsertions(script);

        for (idx in 0...items.length) {
            final item:Dynamic = items[idx];
            if (item.saveAtChoice != null || item.saveAtDialogue != null) continue;
            if (restoreInputs[idx] != null) continue;
            if (item.saveSweep == false) continue;

            final choices:Array<Int> = item.choices;
            final label = filePath + ' ~ save sweep' + (choices != null && choices.length > 0 ? ' ~ [' + [for (c in choices) Std.string(c)].join(',') + ']' : '');
            final options = makeOptions(item);

            // Uninterrupted reference run
            final baseline = runCase(filePath, content, item, options, [], [], item.expected, handleFile);
            if (baseline.error != null || !baseline.passed) {
                // The regular test of this case already reports the failure
                continue;
            }

            final chunks = splitChunks(baseline.actual);
            final events = eventsOf(chunks);
            final failures:Array<String> = [];

            // One save at each event
            for (event in events) {
                checkSaves(filePath, content, item, options, chunks, [event], handleFile, failures);
            }

            // Every pair of saves, for files with insertions
            if (withPairs) {
                for (a in 0...events.length) {
                    for (b in (a + 1)...events.length) {
                        checkSaves(filePath, content, item, options, chunks, [events[a], events[b]], handleFile, failures);
                    }
                }
            }

            report(label, failures.length > 0 ? failures.join('\n') : null);
        }

    }

    static function checkSaves(
        filePath:String, content:String, item:Dynamic, options:InterpreterOptions,
        chunks:Array<String>, saves:Array<SweepEvent>, handleFile:ImportsFileHandler,
        failures:Array<String>
    ):Void {

        final saveAtDialogue:Array<Int> = [];
        final saveAtChoice:Array<Int> = [];
        final duplicated:Array<Int> = [];
        for (save in saves) {
            if (save.kind == 'choice') saveAtChoice.push(save.kindIndex);
            else saveAtDialogue.push(save.kindIndex);
            duplicated.push(save.chunkIndex);
        }

        // The saved events show twice: before the save, and re-presented after the restore
        final expectedParts:Array<String> = [];
        for (i in 0...chunks.length) {
            expectedParts.push(chunks[i]);
            if (duplicated.indexOf(i) != -1) expectedParts.push(chunks[i]);
        }
        final expected = expectedParts.join('\n\n');

        final result = runCase(filePath, content, item, options, saveAtChoice, saveAtDialogue, expected, handleFile);
        checkedRuns++;

        if (result.error != null || !result.passed) {
            final where = [for (save in saves) save.kind + ' #' + save.kindIndex].join(' then ');
            final line = TestRunner.compareOutput(expected, result.actual);
            final expectedLines = expected.trim().split('\n');
            final actualLines = result.actual.replace('\r\n', '\n').trim().split('\n');
            var detail = result.error != null ? 'error: ' + result.error : '';
            if (line != -1) {
                final need = line < expectedLines.length ? expectedLines[line] : '(end)';
                final got = line < actualLines.length ? actualLines[line] : '(end)';
                detail += (detail.length > 0 ? ', ' : '') + 'line ${line + 1}: got "$got", need "$need"';
            }
            failures.push('  > save at ' + where + ': ' + detail);
        }

    }

    static function runCase(
        filePath:String, content:String, item:Dynamic, options:InterpreterOptions,
        saveAtChoice:Array<Int>, saveAtDialogue:Array<Int>, expected:String,
        handleFile:ImportsFileHandler
    ):{passed:Bool, actual:String, error:Null<String>} {

        final testCase = new InterpreterTestCase(
            filePath, content, filePath,
            item.beat, item.choices, options,
            saveAtChoice, saveAtDialogue, null, expected
        );
        var outcome = {passed: false, actual: '', error: 'No result'};
        try {
            new TestRunner(handleFile).runTestCase(testCase, result -> {
                outcome = {
                    passed: result.passed,
                    actual: result.actualOutput,
                    error: result.error != null ? Std.string(result.error) : null
                };
            });
        }
        catch (e:Any) {
            outcome = {passed: false, actual: '', error: Std.string(e)};
        }
        return outcome;

    }

    /**
     * Splits a rendered output into its events: chunks separated by blank lines.
     */
    static function splitChunks(output:String):Array<String> {
        final chunks:Array<String> = [];
        final current:Array<String> = [];
        for (line in output.replace('\r\n', '\n').split('\n')) {
            if (line.trim().length == 0) {
                if (current.length > 0) {
                    chunks.push(current.join('\n'));
                    current.resize(0);
                }
            }
            else {
                current.push(line);
            }
        }
        if (current.length > 0) chunks.push(current.join('\n'));
        return chunks;
    }

    static function eventsOf(chunks:Array<String>):Array<SweepEvent> {
        final events:Array<SweepEvent> = [];
        var dialogues = 0;
        var choices = 0;
        for (i in 0...chunks.length) {
            // Choice options are rendered "+ text" or "- text", dialogues "~ text" or "Name: text"
            final isChoice = chunks[i].startsWith('+ ') || chunks[i].startsWith('- ');
            events.push({
                kind: isChoice ? 'choice' : 'dialogue',
                kindIndex: isChoice ? choices++ : dialogues++,
                chunkIndex: i
            });
        }
        return events;
    }

    static function hasInsertions(script:Script):Bool {
        return new Lens(script).getNodesOfType(NInsertion, true).length > 0;
    }

    /**
     * Whether the script relies on the random generator, which is not saved:
     * pick/shuffle alternatives, random built-ins, or random calls in functions.
     */
    static function usesRandomness(script:Script):Bool {
        final lens = new Lens(script);
        for (alt in lens.getNodesOfType(NAlternative, true)) {
            if (alt.mode == Pick || alt.mode == Shuffle) return true;
        }
        final randomNames = ['random', 'chance', 'random_float', 'seed_random', 'array_pick', 'array_shuffle'];
        for (access in lens.getNodesOfType(NAccess, true)) {
            if (randomNames.indexOf(access.name) != -1) return true;
            // `items.pick()` / `items.shuffle()` helpers
            if (access.target != null && (access.name == 'pick' || access.name == 'shuffle')) return true;
        }
        for (func in lens.getNodesOfType(NFunctionDecl, true)) {
            if (func.code == null) continue;
            for (name in randomNames.concat(['.pick(', '.shuffle('])) {
                if (func.code.indexOf(name) != -1) return true;
            }
        }
        return false;
    }

}
