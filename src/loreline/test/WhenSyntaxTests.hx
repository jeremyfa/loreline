package loreline.test;

import loreline.Arrays;
import loreline.AstUtils;
import loreline.Fields;
import loreline.Interpreter;
import loreline.Objects;
import loreline.Lens;
import loreline.Loreline;
import loreline.Node;
import loreline.Printer;
import loreline.Script;
import loreline.test.SpawnTests.FlowHost;

using StringTools;

/**
 * Fields object of a beat state that claims to hold the fact `concept`, as a host
 * could with its own fields: the interpreter has to ask it, and cannot assume
 * from the script which names a scope holds.
 */
@:keep
class ShadowFields implements Fields {

    final values:haxe.ds.StringMap<Any> = new haxe.ds.StringMap();

    public function new() {}

    public function lorelineCreate(interpreter:Interpreter):Void {}

    public function lorelineGet(interpreter:Interpreter, key:String):Any {
        return key == 'concept' ? 'shout' : values.get(key);
    }

    public function lorelineSet(interpreter:Interpreter, key:String, value:Any):Void {
        values.set(key, value);
    }

    public function lorelineRemove(interpreter:Interpreter, key:String):Bool {
        return values.remove(key);
    }

    public function lorelineExists(interpreter:Interpreter, key:String):Bool {
        return key == 'concept' || values.exists(key);
    }

    public function lorelineFields(interpreter:Interpreter):Array<String> {
        return ['concept'].concat([for (key in values.keys()) key]);
    }

}

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
            '    true',
            '      Hello.'
        ],
        [
            'beat Start',
            '  when first',
            '    gold > 100',
            '      You are rich.',
            '    (gold > 10) and not broke',
            '      You are fine.',
            '    true',
            '      You are broke.'
        ],
        [
            'beat Start',
            '  when pick {',
            '    ready {',
            '      Go.',
            '    }',
            '    - true {',
            '      Wait.',
            '    }',
            '  }'
        ],
        [
            'beat Start',
            '  when',
            '    + Greetings',
            '    + Rumors if (visits > 2)',
            '    true',
            '      Nothing to say.',
            '',
            'beat Greetings',
            '  when',
            '    true',
            '      Hi.',
            '',
            'beat Rumors',
            '  when',
            '    true',
            '      Did you hear?'
        ],
        [
            'beat Start',
            '  when',
            '    ready',
            '      when my_strategy',
            '        -x > 0',
            '          Negative.',
            '        true',
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
            {name: 'the history is shared with child interpreters', fn: () -> testSharedHistory()},
            {name: 'a host function can be a strategy', fn: () -> testHostStrategy()},
            {name: 'a strategy must return -1 or an eligible index', fn: () -> testStrategyErrors()},
            {name: 'editor warnings', fn: () -> testWarnings()},
            {name: 'a child interpreter resolves names from its own stack', fn: () -> testChildLocalScope()},
            {name: 'an undefined name in the winning rules is an error in strict mode', fn: () -> testStrictUndefined()},
            {name: 'a fact set by the host between two picks is read by the next one', fn: () -> testHostSetsFact()},
            {name: 'host fields of a local state can shadow a fact', fn: () -> testCustomFieldsShadow()},
            {name: 'names only the root state can hold', fn: () -> testRootOnlyNames()}
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
        expectEqual(true, AstUtils.isLiteralTrue(first.rules[2].condition), 'true is a condition');
        expectEqual(1, first.rules[2].body.length, 'true body');

        final second = whenBlocks(parse(SOURCES[1].join('\n')))[0];
        expectEqual('first', second.strategy, 'strategy first');

        final third = whenBlocks(parse(SOURCES[2].join('\n')))[0];
        expectEqual('pick', third.strategy, 'strategy pick');
        expectEqual('Braces', third.style.toString(), 'brace style');
        expectEqual(true, third.rules[1].once, 'once true');
        expectEqual(true, AstUtils.isLiteralTrue(third.rules[1].condition), 'once true is a condition');
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
            // `true` requires nothing, alone or among other clauses
            {header: 'true', score: 0},
            {header: '(true)', score: 0},
            {header: 'true and ready', score: 1},
            // Not a keyword: a variable
            {header: 'always', score: 1}
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
        final script = parse(['beat Start', '  Before.', '', '  when no_such_strategy', '    true', '      Inside.'].join('\n'));
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


    /**
     * Two beats with the same local state name insert the same beat: the root
     * interpreter and a child each resolve `tone` from their own stack, while the
     * history of the inserted rules is shared.
     */
    static function testChildLocalScope():Void {
        final script = parse([
            'beat Calm',
            '  state',
            '    tone: "calm"',
            '  when',
            '    + Mood',
            '',
            'beat Angry',
            '  state',
            '    tone: "angry"',
            '  when',
            '    + Mood',
            '',
            'beat Mood',
            '  when',
            '    - tone is "calm"',
            '      Calm once.',
            '    tone is "calm"',
            '      Calm again.',
            '    tone is "angry"',
            '      Angry word.'
        ].join('\n'));
        final host = new FlowHost();
        final root = host.play(script, 'Calm');
        final npc = host.spawn(root, 'npc');
        npc.start('Angry');
        host.next('root');
        host.next('npc');
        final again = host.spawn(root, 'again');
        again.start('Calm');
        final expected = ['root: Calm once.', 'npc: Angry word.', 'root: <end>', 'npc: <end>', 'again: Calm again.'];
        expectEqual(expected.join(' | '), host.log.join(' | '), 'log');
    }

    /**
     * In strict mode, an undefined name in the condition of the most specific
     * rule is an error, whatever the other rules would have played.
     */
    static function testStrictUndefined():Void {
        final script = parse([
            'state',
            '  gold: 20',
            '',
            'beat Start',
            '  when',
            '    gold > 10 and unknown_fact',
            '      Rich unknown.',
            '    gold > 10',
            '      Rich.'
        ].join('\n'));
        var error = '';
        final seen = [];
        try {
            Loreline.play(script, (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> {}, interp -> {}, null, ({strictAccess: true} : InterpreterOptions));
        }
        catch (e:Any) {
            error = (e is loreline.Error) ? (cast e:loreline.Error).message : Std.string(e);
        }
        expectEqual('', seen.join(','), 'nothing played');
        expectEqual(true, error.indexOf('Undefined variable: unknown_fact') != -1, 'error: ' + error);
    }

    /**
     * The host changes a fact between two picks of the same block: each pick
     * reads the value of the moment.
     */
    static function testHostSetsFact():Void {
        final script = parse([
            'state',
            '  concept: "greet"',
            '',
            'beat Bark',
            '  when',
            '    concept is "greet"',
            '      Greeting.',
            '    concept is "leave"',
            '      Farewell.'
        ].join('\n'));
        final seen = [];
        final interp = Loreline.play(script, (interp, character, text, tags, advance) -> {
            seen.push(text);
            advance();
        }, (interp, options, select) -> {}, interp -> {}, 'Bark');
        interp.setStateField('concept', 'leave');
        interp.start('Bark');
        interp.setTopLevelStateField('concept', 'greet');
        interp.start('Bark');
        expectEqual('Greeting.,Farewell.,Greeting.', seen.join(','), 'picks');
    }

    /**
     * With `customCreateFields`, the fields of a beat state come from the host
     * (asked with the beat as node), and may hold names the script never declared
     * there: here the fields of `Local` claim the fact `concept`. The block inserted by that beat reads the fact from those fields, the
     * one inserted by a plain beat reads the root fact.
     */
    static function testCustomFieldsShadow():Void {
        final script = parse([
            'state',
            '  concept: "greet"',
            '',
            'beat Plain',
            '  when',
            '    + Lines',
            '',
            'beat Local',
            '  state',
            '    other: 1',
            '  when',
            '    + Lines',
            '',
            'beat Lines',
            '  when',
            '    concept is "greet"',
            '      Greeting.',
            '    concept is "shout"',
            '      Shout.'
        ].join('\n'));
        final options:InterpreterOptions = {
            customCreateFields: (interpreter:Interpreter, type:String, node:Node) -> {
                final beat:NBeatDecl = (node != null && node is NBeatDecl) ? cast node : null;
                return beat != null && beat.name == 'Local' ? new ShadowFields() : null;
            }
        };
        final seen = [];
        final interp = Loreline.play(script, (interp, character, text, tags, advance) -> {
            seen.push(text);
            advance();
        }, (interp, options, select) -> {}, interp -> {}, 'Plain', options);
        interp.start('Local');
        interp.start('Plain');
        expectEqual('Greeting.,Shout.,Greeting.', seen.join(','), 'picks');
    }

    /**
     * The lens tells which names no scope can shadow: not the fields of a beat
     * state or of a temporary state, not the parameters of a beat, not the
     * fields the interpreter keeps on nodes.
     */
    static function testRootOnlyNames():Void {
        final script = parse([
            'state',
            '  gold: 1',
            '  tone: "root"',
            '  mood: "calm"',
            '',
            'beat A(who)',
            '  state',
            '    tone: "a"',
            '  new state',
            '    temp: 2',
            '  choice',
            '    Pick',
            '      state',
            '        picked: true',
            '      Picked.',
            '  when',
            '    gold > 0',
            '      Ok.'
        ].join('\n'));
        final lens = new Lens(script);
        for (name in ['gold', 'mood', 'unknown']) {
            expectEqual(true, lens.isRootOnlyName(name), name);
        }
        for (name in ['tone', 'who', 'temp', 'picked', '_played', '_lastPlayed', '_whenTick']) {
            expectEqual(false, lens.isRootOnlyName(name), name);
        }
    }

    static final STRATEGY_SCRIPT = [
        'state',
        '  ready: true',
        '',
        'beat Start',
        '  when chooser',
        '    ready',
        '      Zero.',
        '    not ready',
        '      One.',
        '    true',
        '      Two.',
        '  End.'
    ].join('\n');

    /**
     * Plays STRATEGY_SCRIPT with a host function `chooser`, and returns the dialogue
     * lines, or the error message prefixed with "error: ".
     */
    static function playWithChooser(chooser:(records:Any)->Any):Array<String> {
        final functions:FunctionsMap = #if loreline_functions_map_dynamic_access {} #else new Map<String, Any>() #end;
        #if loreline_auto_wrap_functions
        functions.set('chooser', (interp:Interpreter, args:Array<Any>) -> chooser(args[0]));
        #else
        functions.set('chooser', (records:Any) -> chooser(records));
        #end
        final seen:Array<String> = [];
        try {
            Loreline.play(parse(STRATEGY_SCRIPT), (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> {}, interp -> {}, null, ({functions: functions} : InterpreterOptions));
        }
        catch (e:Any) {
            seen.push('error: ' + ((e is loreline.Error) ? (cast e:loreline.Error).message : Std.string(e)));
        }
        return seen;
    }

    static function testHostStrategy():Void {
        var summary = '';
        final seen = playWithChooser(records -> {
            final parts = [];
            for (i in 0...Arrays.arrayLength(records)) {
                final record = Arrays.arrayGet(records, i);
                parts.push(Objects.getField(null, record, 'index') + ':' + Objects.getField(null, record, 'eligible'));
            }
            summary = parts.join(' ');
            return 2;
        });
        expectEqual('0:true 1:false 2:true', summary, 'records seen by the host');
        expectEqual('Two.,End.', seen.join(','), 'played rule');
    }

    static function testStrategyErrors():Void {
        final errors:Array<String> = [];
        for (item in [
            {result: (5:Any), what: 'out of range'},
            {result: (1:Any), what: 'not eligible'},
            {result: ('zero':Any), what: 'not a number'},
            {result: (0.5:Any), what: 'not an integer'}
        ]) {
            final seen = playWithChooser(records -> item.result);
            final last = seen.length > 0 ? seen[seen.length - 1] : '';
            if (!last.startsWith('error: ') || last.indexOf('chooser') == -1) {
                errors.push('${item.what}: expected an error naming the strategy, got ' + seen);
            }
        }
        final none = playWithChooser(records -> -1);
        if (none.join(',') != 'End.') errors.push('-1 should play nothing, got ' + none);
        if (errors.length > 0) throw errors.join('\n');
    }


    /**
     * What Lens.getWhenWarnings reports for a when block: each case lists the
     * start of every expected message, `!` in front for a warning.
     */
    static function testWarnings():Void {
        final cases:Array<{lines:Array<String>, expected:Array<String>}> = [
            // Nothing to say
            {lines: ['  when', '    ready', '      Go.', '    true', '      Wait.'], expected: []},
            // No rule always eligible: deliberate, nothing reported
            {lines: ['  when', '    ready', '      Go.'], expected: []},
            {lines: ['  when', '    - true', '      Once.'], expected: []},
            {lines: ['  when', '    + Other', '    ready', '      Go.'], expected: []},
            // Unknown strategy
            {lines: ['  when chooser', '    true', '      Go.'], expected: ['!Unknown strategy: chooser']},
            // Known strategies, and a function declared by the script (or for the host)
            {lines: ['  when first', '    true', '      Go.'], expected: []},
            {lines: ['  when declared', '    true', '      Go.'], expected: []},
            // A minus sign glued to the condition
            {lines: ['  when', '    -gold > 0', '      Debt.', '    true', '      Fine.'], expected: ['!This `-` is a minus sign']},
            // With a space it is the mark of a rule played once
            {lines: ['  when', '    - gold > 0', '      Once.', '    true', '      Fine.'], expected: []},
            // Thresholds with the default strategy
            {lines: ['  when', '    gold > 100', '      Rich.', '    gold > 10', '      Fine.', '    true', '      Broke.'], expected: ['!Rules comparing `gold`']},
            // With first, thresholds are fine
            {lines: ['  when first', '    gold > 100', '      Rich.', '    gold > 10', '      Fine.', '    true', '      Broke.'], expected: []},
            // Different numbers of criteria don't tie
            {lines: ['  when', '    gold > 100 and ready', '      Rich.', '    gold > 10', '      Fine.', '    true', '      Broke.'], expected: []}
        ];
        final errors:Array<String> = [];
        for (item in cases) {
            final source = ['function declared(rules)', '', 'beat Start'].concat(item.lines).concat(['', 'beat Other', '  when', '    true', '      Other.']).join('\n');
            final script = parse(source);
            final lens = new Lens(script);
            final block = whenBlocks(script)[0];
            final got = [for (w in lens.getWhenWarnings(block)) (w.isWarning ? '!' : '') + w.message];
            var ok = got.length == item.expected.length;
            if (ok) {
                for (i in 0...got.length) {
                    if (!got[i].startsWith(item.expected[i])) ok = false;
                }
            }
            if (!ok) errors.push(item.lines.join(' / ') + '\n  expected ' + item.expected + '\n  got ' + got);
        }
        if (errors.length > 0) throw errors.join('\n');
    }

}
