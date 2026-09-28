package loreline.test;

import loreline.AstUtils;
import loreline.Lens;
import loreline.Loreline;
import loreline.Node;
import loreline.Printer;
import loreline.Script;
import loreline.test.SpawnTests.FlowHost;

using StringTools;

/**
 * Tests of the syntax of when blocks (parsing, printing, JSON). Their behavior is
 * tested by the test/When-*.lor files.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class WhenSyntaxTests {

    /**
     * Scripts that must print back as written (blank lines aside).
     */
    static final SOURCES = [
        [
            'beat Start',
            '  when',
            '    mood is "angry" and gold > 3',
            '      Get out!',
            '    - met_before',
            '      Oh, it is you again.',
            '    always',
            '      Hello.'
        ],
        [
            'beat Start',
            '  when first',
            '    gold > 100',
            '      You are rich.',
            '    (gold > 10) and not broke',
            '      You are fine.',
            '    always',
            '      You are broke.'
        ],
        [
            'beat Start',
            '  when pick {',
            '    ready {',
            '      Go.',
            '    }',
            '    - always {',
            '      Wait.',
            '    }',
            '  }'
        ],
        [
            'beat Start',
            '  when',
            '    + Greetings',
            '    + Rumors if (visits > 2)',
            '    always',
            '      Nothing to say.',
            '',
            'beat Greetings',
            '  when',
            '    always',
            '      Hi.',
            '',
            'beat Rumors',
            '  when',
            '    always',
            '      Did you hear?'
        ],
        [
            'beat Start',
            '  when',
            '    ready',
            '      when my_strategy',
            '        -x > 0',
            '          Negative.',
            '        always',
            '          Other.'
        ]
    ];

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'structure of when blocks', fn: () -> testStructure()},
            {name: 'rule scores', fn: () -> testScores()},
            {name: 'when blocks print back as written', fn: () -> testPrint(false)},
            {name: 'when blocks print back as written after JSON', fn: () -> testPrint(true)},
            {name: 'narration starting with when stays text', fn: () -> testNarration()},
            {name: 'an unknown strategy is an error', fn: () -> testUnknownStrategy()},
            {name: 'the history is shared with child interpreters', fn: () -> testSharedHistory()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('when syntax: ' + test.name);
            }
            catch (e:Any) {
                fail('when syntax: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    static function whenBlocks(script:Script):Array<NWhenStatement> {
        return new Lens(script).getNodesOfType(NWhenStatement);
    }

    static function expectEqual(expected:Any, actual:Any, what:String):Void {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ' + Std.string(expected) + ', got ' + Std.string(actual);
        }
    }

    static function testStructure():Void {

        // A header read as text would still print back the same: check its kind
        for (lines in SOURCES) {
            for (block in whenBlocks(parse(lines.join('\n')))) {
                for (rule in block.rules) {
                    if (rule.condition is NStringLiteral) {
                        throw 'rule header read as text: ' + new Printer().print(rule.condition).trim();
                    }
                }
            }
        }

        final first = whenBlocks(parse(SOURCES[0].join('\n')))[0];
        expectEqual(null, first.strategy, 'default strategy');
        expectEqual(3, first.rules.length, 'rule count');
        expectEqual(false, first.rules[0].once, 'first rule once');
        expectEqual(true, first.rules[1].once, 'second rule once');
        expectEqual(null, first.rules[2].condition, 'always has no condition');
        expectEqual(1, first.rules[2].body.length, 'always body');

        final second = whenBlocks(parse(SOURCES[1].join('\n')))[0];
        expectEqual('first', second.strategy, 'strategy first');

        final third = whenBlocks(parse(SOURCES[2].join('\n')))[0];
        expectEqual('pick', third.strategy, 'strategy pick');
        expectEqual('Braces', third.style.toString(), 'brace style');
        expectEqual(true, third.rules[1].once, 'once always');
        expectEqual(null, third.rules[1].condition, 'once always has no condition');
        expectEqual(true, third.rules[0].condition is NAccess, 'brace rule header is an expression');

        final fourth = whenBlocks(parse(SOURCES[3].join('\n')))[0];
        expectEqual(true, fourth.rules[0].insertion != null, 'insertion');
        expectEqual(null, fourth.rules[0].insertionCondition, 'insertion without guard');
        expectEqual(true, fourth.rules[1].insertionCondition != null, 'insertion guard');
        expectEqual('Parens', fourth.rules[1].insertionConditionStyle.toString(), 'insertion guard style');

        // A `-` glued to the condition is a unary minus, not the once marker
        final nested = whenBlocks(parse(SOURCES[4].join('\n')));
        expectEqual(2, nested.length, 'nested when blocks');
        final inner = nested[0].strategy == 'my_strategy' ? nested[0] : nested[1];
        expectEqual('my_strategy', inner.strategy, 'custom strategy name');
        expectEqual(false, inner.rules[0].once, 'glued minus is not once');
        expectEqual(true, inner.rules[0].condition is NBinary, 'glued minus stays in the condition');

    }

    static function testScores():Void {
        final cases = [
            {header: 'a', score: 1},
            {header: 'a and b', score: 2},
            {header: 'a and b and c', score: 3},
            {header: '(a and b) and c', score: 2},
            {header: 'a or b', score: 1},
            {header: 'a and (b or c)', score: 2},
            {header: 'not a', score: 1},
            {header: 'not a and b is c', score: 2},
            {header: 'always', score: 0}
        ];
        final errors:Array<String> = [];
        for (item in cases) {
            final script = parse(['beat Start', '  when', '    ' + item.header, '      Yes.'].join('\n'));
            final rule = whenBlocks(script)[0].rules[0];
            final score = AstUtils.whenRuleScore(rule);
            if (score != item.score) errors.push('"${item.header}": expected ${item.score}, got $score');
        }
        if (errors.length > 0) throw errors.join('\n');
    }

    /** Lines of a script, right trimmed, without blank lines. */
    static function significantLines(text:String):Array<String> {
        return [for (line in text.replace('\r\n', '\n').split('\n')) if (line.trim().length > 0) line.rtrim()];
    }

    static function testPrint(json:Bool):Void {
        final errors:Array<String> = [];
        for (lines in SOURCES) {
            var script = parse(lines.join('\n'));
            if (json) script = Script.fromJson(haxe.Json.parse(haxe.Json.stringify(script.toJson())));
            final printed = significantLines(new Printer().print(script));
            final expected = significantLines(lines.join('\n'));
            if (printed.join('\n') != expected.join('\n')) {
                errors.push('expected:\n  ' + expected.join('\n  ') + '\ngot:\n  ' + printed.join('\n  '));
            }
        }
        if (errors.length > 0) throw errors.join('\n\n');
    }

    static function testNarration():Void {
        final lines = [
            'when you are ready, come back.',
            'when she arrives, it rains.',
            'when',
            'when first light comes',
            'when ready then'
        ];
        final errors:Array<String> = [];
        for (line in lines) {
            final script = parse(['beat Start', '  ' + line, '', '  After.'].join('\n'));
            if (whenBlocks(script).length > 0) {
                errors.push('"$line" was read as a when block');
                continue;
            }
            final texts = new Lens(script).getNodesOfType(NTextStatement);
            if (texts.length == 0) errors.push('"$line" was not read as text');
        }
        if (errors.length > 0) throw errors.join('\n');
    }

    static function testUnknownStrategy():Void {
        final script = parse(['beat Start', '  Before.', '', '  when no_such_strategy', '    always', '      Inside.'].join('\n'));
        final seen:Array<String> = [];
        var error:String = null;
        try {
            Loreline.play(script, (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> {}, interp -> {});
        }
        catch (e:Any) {
            // The message, not Std.string(e): on GDScript that prints the object reference
            error = (e is loreline.Error) ? (cast e:loreline.Error).message : Std.string(e);
        }
        if (error == null || error.indexOf('no_such_strategy') == -1) {
            throw 'expected an error naming the strategy, got ' + (error ?? 'none') + ' after ' + seen;
        }
        if (seen.join(',') != 'Before.') throw 'the rule should not play: ' + seen;
    }


    /**
     * A child shares the node states of its root, so a when block played by both
     * goes on with the same rotation.
     */
    static function testSharedHistory():Void {
        final script = parse([
            'state',
            '  ready: true',
            '',
            'beat Greet',
            '  when',
            '    ready',
            '      First.',
            '    ready',
            '      Second.',
            '    ready',
            '      Third.'
        ].join('\n'));
        final host = new FlowHost();
        final root = host.play(script, 'Greet');
        final npc = host.spawn(root, 'npc');
        npc.start('Greet');
        host.next('root');
        final again = host.spawn(root, 'again');
        again.start('Greet');
        final expected = ['root: First.', 'npc: Second.', 'root: <end>', 'again: Third.'];
        if (host.log.join(' | ') != expected.join(' | ')) {
            throw 'expected ' + expected.join(' | ') + ', got ' + host.log.join(' | ');
        }
    }

}
