package loreline.test;

import loreline.Interpreter;
import loreline.Loreline;
import loreline.Node;
import loreline.SaveData;
import loreline.Script;
import loreline.test.SpawnTests.FlowHost;

using StringTools;

/**
 * Checks the execution stack after picking an option that comes from an
 * insertion (`+ Beat` in a choice): each epilogue must run with its own beat
 * scope on top, and saves taken there (even after a previous restore) must
 * resume at the right place.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class InsertionScopeTests {

    static final SCRIPT = [
        'beat Start',
        '  new state',
        '    label: "start"',
        '  choice',
        '    Start option',
        '      Picked at start.',
        '    + Level1',
        '  Back at start with $$label.',
        '  label = label + "+"',
        '',
        '  Start done with $$label.',
        '',
        'beat Level1',
        '  new state',
        '    label: "level1"',
        '  choice',
        '    Level1 option',
        '      Picked at level1.',
        '    + Level2',
        '  Back at level1 with $$label.',
        '',
        'beat Level2',
        '  new state',
        '    label: "level2"',
        '  choice',
        '    Level2 option',
        '      Picked at level2.',
        '  Back at level2 with $$label.'
    ].join('\n');

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'stack after a local option (control)', fn: () -> testStackAfterOption(0)},
            {name: 'stack after an inserted option', fn: () -> testStackAfterOption(1)},
            {name: 'stack after a nested inserted option', fn: () -> testStackAfterOption(2)},
            {name: 'save in the parent epilogue after restore and inserted option', fn: () -> testSaveAfterRestoreAndInsertedOption(1)},
            {name: 'save in the parent epilogue after restore and nested inserted option', fn: () -> testSaveAfterRestoreAndInsertedOption(2)}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('insertion scope: ' + test.name);
            }
            catch (e:Any) {
                fail('insertion scope: ' + test.name, (e is loreline.Error) ? (cast e:loreline.Error).toString() : Std.string(e));
            }
        }

    }

    static function parse():Script {
        final script = Loreline.parse(SCRIPT);
        if (script == null) throw 'Failed to parse script: ' + Loreline.lastError();
        return script;
    }

    static function describeScope(scope:RuntimeScope):String {
        if (scope == null) return 'null';
        final node:Node = cast scope.node;
        final nodeName = node is NBeatDecl ? 'beat ' + (cast node:NBeatDecl).name : (node != null ? node.type() : 'null');
        return '{node: $nodeName}';
    }

    static function describeStack(interpreter:Interpreter):String {
        final stack = @:privateAccess interpreter.stack;
        return '[' + [for (scope in stack) describeScope(scope)].join(', ') + ']';
    }

    /**
     * The beat declaration an epilogue line belongs to must be the scope on top of
     * the stack while that line is displayed, and the stack must be as deep as a
     * normal run of that beat body.
     */
    static function checkEpilogueScope(interpreter:Interpreter, expectedBeat:String, expectedDepth:Int):Null<String> {
        final stack = @:privateAccess interpreter.stack;
        final top = stack[stack.length - 1];
        final topNode:Node = cast top.node;
        final topIsBeat = topNode is NBeatDecl && (cast topNode:NBeatDecl).name == expectedBeat;
        if (!topIsBeat || stack.length != expectedDepth) {
            return 'epilogue of $expectedBeat: expected beat $expectedBeat on top at depth $expectedDepth, got ' + describeStack(interpreter);
        }
        return null;
    }

    static function drive(host:FlowHost):Void {
        var guard = 0;
        while (host.hasPendingDialogue('root') && guard++ < 50) {
            host.next('root');
        }
    }

    static function testStackAfterOption(index:Int):Void {

        final script = parse();
        final host = new FlowHost();
        final errors:Array<String> = [];
        final seen:Array<String> = [];

        final root = host.play(script, 'Start');

        // The choice is presented: the stack holds the Start beat scope only
        final depthAtChoice = @:privateAccess root.stack.length;

        host.afterDialogue = (interpreter, text) -> {
            var error:Null<String> = null;
            if (text.startsWith('Back at start')) {
                seen.push('Start');
                error = checkEpilogueScope(interpreter, 'Start', depthAtChoice);
            }
            else if (text.startsWith('Back at level1')) {
                seen.push('Level1');
                error = checkEpilogueScope(interpreter, 'Level1', depthAtChoice + 1);
            }
            else if (text.startsWith('Back at level2')) {
                seen.push('Level2');
                error = checkEpilogueScope(interpreter, 'Level2', depthAtChoice + 2);
            }
            if (error != null) errors.push(error);
        };

        host.choose('root', index);
        drive(host);

        if (seen.indexOf('Start') == -1) throw 'Start epilogue not reached: ' + host.log;
        if (errors.length > 0) throw errors.join(' | ');

    }

    static function testSaveAfterRestoreAndInsertedOption(index:Int):Void {

        final script = parse();

        // 1. Save while the choice is presented
        final host = new FlowHost();
        final root = host.play(script, 'Start');
        final atChoice:SaveData = haxe.Json.parse(haxe.Json.stringify(root.save()));

        // 2. Restore, pick the inserted option, and save again on the first
        //    line of the parent epilogue
        final restoredHost = new FlowHost();
        var inEpilogue:SaveData = null;
        var headError:String = null;
        restoredHost.afterDialogue = (interpreter, text) -> {
            if (inEpilogue == null && text.startsWith('Back at start')) {
                // The scope of Start, on the stack, must know it is now on this line:
                // that is what the save records as the point to resume from
                final stack = @:privateAccess interpreter.stack;
                final head:Node = cast stack[stack.length - 1].head;
                if (!(head is NTextStatement)) {
                    headError = 'head of the Start scope while its epilogue runs: expected Text, got ' + (head != null ? head.type() : 'null');
                }
                inEpilogue = haxe.Json.parse(haxe.Json.stringify(interpreter.save()));
            }
        };
        restoredHost.resume(script, atChoice);
        restoredHost.choose('root', index);
        drive(restoredHost);
        if (inEpilogue == null) throw 'Start epilogue not reached after the first restore: ' + restoredHost.log;
        if (headError != null) throw headError;

        // 3. Restore that second save: it must continue right after the saved line,
        //    with the temporary state of Start
        final finalHost = new FlowHost();
        finalHost.resume(script, inEpilogue);
        drive(finalHost);

        final expected = [
            'root: Back at start with start.',
            'root: Start done with start+.',
            'root: <end>'
        ];
        if (finalHost.log.join('\n') != expected.join('\n')) {
            throw '\n  expected:\n    ' + expected.join('\n    ') + '\n  got:\n    ' + finalHost.log.join('\n    ');
        }

    }

}
