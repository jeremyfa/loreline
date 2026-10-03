package loreline.test;

import loreline.Interpreter;
import loreline.Node;

using StringTools;

/**
 * Tests of Interpreter.prepareCaches and of the prepareCaches option: they build
 * the information of every when block, imported ones included, before the first
 * pick needs it, and never change what the script plays.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class PrepareCachesTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'every when block is prepared, imported ones included', fn: () -> testEveryBlock()},
            {name: 'the option prepares before the script starts', fn: () -> testOption()},
            {name: 'a second call keeps what is prepared', fn: () -> testIdempotent()},
            {name: 'prepared or not, the script plays the same', fn: () -> testSamePicks()},
            {name: 'string literal processors set after preparing empty the caches', fn: () -> testProcessorsEmptyCaches()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('prepare caches: ' + test.name);
            }
            catch (e:Any) {
                fail('prepare caches: ' + test.name, Std.string(e));
            }
        }

    }

    static final MAIN = [
        'import barks',
        '',
        'state',
        '  concept: "greet"',
        '  who: "ann"',
        '  gold: 20',
        '',
        'beat Start',
        '  Bark()',
        '  Bark()',
        '  who = "bob"',
        '  Bark()',
        '  concept = "leave"',
        '  Bark()',
        '  concept = "trade"',
        '  gold = 0',
        '  Bark()',
        '  Talk()',
        '  who = "ann"',
        '  Talk()',
        '',
        'beat Talk',
        '  when first',
        '    who is "ann"',
        '      Ann talks.',
        '    true',
        '      Someone talks.'
    ].join('\n');

    /** A block long enough to be grouped by `concept`. */
    static final BARKS = [
        'beat Bark',
        '  when',
        '    concept is "greet" and who is "ann" and gold > 10',
        '      Ann greets, rich.',
        '    concept is "greet" and who is "ann"',
        '      Ann greets.',
        '    concept is "greet" and who is "bob"',
        '      Bob greets.',
        '    concept is "greet"',
        '      Someone greets.',
        '    concept is "leave" and who is "ann"',
        '      Ann leaves.',
        '    concept is "leave" and who is "bob"',
        '      Bob leaves.',
        '    concept is "leave"',
        '      Someone leaves.',
        '    concept is "trade" and who is "ann"',
        '      Ann trades.',
        '    concept is "trade" and who is "bob" and gold > 10',
        '      Bob trades, rich.',
        '    concept is "trade" and who is "bob"',
        '      Bob trades.',
        '    concept is "trade"',
        '      Someone trades.',
        '    concept is "dance"',
        '      Someone dances.',
        '    concept is "sing"',
        '      Someone sings.',
        '    concept is "wait"',
        '      Someone waits.',
        '    who is "bob" and gold > 10',
        '      Bob, rich.',
        '    gold > 10',
        '      Rich.',
        '    true',
        '      Nothing.',
        '    true',
        '      Still nothing.'
    ].join('\n');

    static function parse():Script {
        final script = Loreline.parse(MAIN, 'main.lor', (path, callback) -> callback(BARKS));
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError();
        return script;
    }

    static function whenBlocksOf(script:Script):Array<NWhenStatement> {
        return new Lens(script).getNodesOfType(NWhenStatement, true);
    }

    static function create(script:Script, seen:Array<String>, ?options:InterpreterOptions, ?onLine:(interp:Interpreter)->Void):Interpreter {
        return new Interpreter(script, (interp, character, text, tags, advance) -> {
            seen.push(text);
            if (onLine != null) onLine(interp);
            advance();
        }, (interp, choiceOptions, select) -> {}, interp -> {}, options);
    }

    static function preparedCount(interp:Interpreter, blocks:Array<NWhenStatement>):Int {
        final prepared = @:privateAccess interp.context.whenBlocks;
        var count = 0;
        for (block in blocks) {
            if (prepared.get(block.id) != null) count++;
        }
        return count;
    }

    static function expectEqual(expected:Any, actual:Any, what:String):Void {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ' + Std.string(expected) + ', got ' + Std.string(actual);
        }
    }

    static function testEveryBlock():Void {
        final script = parse();
        final blocks = whenBlocksOf(script);
        expectEqual(2, blocks.length, 'when blocks in the script and its import');
        final interp = create(script, []);
        expectEqual(0, preparedCount(interp, blocks), 'prepared before the call');
        interp.prepareCaches();
        expectEqual(2, preparedCount(interp, blocks), 'prepared after the call');
        // The long block of the import is grouped by its fact
        final bark = blocks.filter(b -> b.rules.length > 16)[0];
        final info = @:privateAccess interp.context.whenBlocks.get(bark.id);
        final run = info.runs[0];
        expectEqual(true, run != null && run.index != null, 'grouping of the long block');
        expectEqual('concept', run.index.fact, 'fact of the grouping');
    }

    static function testOption():Void {
        final script = parse();
        final blocks = whenBlocksOf(script);
        final interp = create(script, [], ({prepareCaches: true} : InterpreterOptions));
        expectEqual(2, preparedCount(interp, blocks), 'prepared before start');
        final lazy = create(script, [], ({prepareCaches: false} : InterpreterOptions));
        expectEqual(0, preparedCount(lazy, blocks), 'nothing prepared without the option');
    }

    static function testIdempotent():Void {
        final script = parse();
        final blocks = whenBlocksOf(script);
        final interp = create(script, []);
        interp.prepareCaches();
        final first = [for (block in blocks) @:privateAccess interp.context.whenBlocks.get(block.id)];
        interp.prepareCaches();
        for (i in 0...blocks.length) {
            if (@:privateAccess interp.context.whenBlocks.get(blocks[i].id) != first[i]) throw 'block $i was built again';
        }
    }

    static function testSamePicks():Void {
        final script = parse();

        // Lazy, the reference
        final lazy = [];
        create(script, lazy).start();
        expectEqual(7, lazy.length, 'lines played lazily');
        final expected = lazy.join(',');

        // Option
        final option = [];
        create(script, option, ({prepareCaches: true} : InterpreterOptions)).start();
        expectEqual(expected, option.join(','), 'option');

        // Method before start
        final before = [];
        final interp = create(script, before);
        interp.prepareCaches();
        interp.start();
        expectEqual(expected, before.join(','), 'method before start');

        // Method in the middle of the play, after some blocks were built lazily
        final during = [];
        var calls = 0;
        create(script, during, null, interp -> {
            if (calls++ == 2) interp.prepareCaches();
        }).start();
        expectEqual(expected, during.join(','), 'method during the play');
    }

    static function testProcessorsEmptyCaches():Void {
        final script = parse();
        final blocks = whenBlocksOf(script);
        final lazy = [];
        create(script, lazy).start();
        final seen = [];
        final interp = create(script, seen);
        interp.prepareCaches();
        interp.stringLiteralProcessors = [str -> str];
        expectEqual(0, preparedCount(interp, blocks), 'prepared after setting processors');
        interp.prepareCaches();
        expectEqual(2, preparedCount(interp, blocks), 'prepared again');
        interp.start();
        expectEqual(lazy.join(','), seen.join(','), 'picks');
    }

}
