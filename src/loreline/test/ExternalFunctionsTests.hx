package loreline.test;

import loreline.Interpreter;

using StringTools;

/**
 * Tests of functions declared without a body that the game doesn't provide:
 * calling one is an error, at the position of the call, wherever the call is.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class ExternalFunctionsTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'calling it as a statement is an error', fn: () -> testStatement()},
            {name: 'calling it in a text is an error', fn: () -> testInterpolation()},
            {name: 'calling it from function code is an error', fn: () -> testFunctionCode()},
            {name: 'using it as a when strategy is an error', fn: () -> testWhenStrategy()},
            {name: 'calling it from a child interpreter is an error', fn: () -> testChild()},
            {name: 'declaring it without calling it is fine', fn: () -> testNotCalled()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('external functions: ' + test.name);
            }
            catch (e:Any) {
                fail('external functions: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    /** Plays a script and returns its lines, then the error if any, with its line. */
    static function play(source:String, ?beatName:String):Array<String> {
        final seen:Array<String> = [];
        try {
            Loreline.play(parse(source), (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> select(0), interp -> {}, beatName);
        }
        catch (e:loreline.Error) {
            seen.push('error at ' + (e.pos != null ? e.pos.line : 0) + ': ' + e.message);
        }
        return seen;
    }

    static function expect(source:String, expected:Array<String>):Void {
        final seen = play(source);
        if (seen.join(' / ') != expected.join(' / ')) {
            throw 'expected "${expected.join(' / ')}", got "${seen.join(' / ')}"';
        }
    }

    static function testStatement():Void {
        expect(
            'function playExplosion()\n\nbeat Start\n  Before.\n\n  playExplosion()\n\n  After.\n',
            ['Before.', 'error at 6: playExplosion() is declared without a body, so the game must provide it']
        );
    }

    static function testInterpolation():Void {
        expect(
            "function roll(sides)\n\nbeat Start\n  You rolled ${roll(6)}.\n",
            ['error at 4: roll() is declared without a body, so the game must provide it']
        );
    }

    static function testFunctionCode():Void {
        expect(
            "function roll(sides)\n\nfunction twice()\n  return roll(6) + roll(6)\n\nbeat Start\n  You rolled ${twice()}.\n",
            ['error at 7: roll() is declared without a body, so the game must provide it']
        );
    }

    static function testWhenStrategy():Void {
        final seen = play('function pickRule(rules)\n\nbeat Start\n  when pickRule\n    true\n      Picked.\n');
        final last = seen[seen.length - 1];
        if (!last.startsWith('error') || last.indexOf('pickRule() is declared without a body, so the game must provide it') == -1) {
            throw 'expected the error of pickRule, got "${seen.join(' / ')}"';
        }
    }

    static function testChild():Void {
        final script = parse("function roll(sides)\n\nbeat Main\n  Root line.\n\nbeat Side\n  Side ${roll(6)}.\n");
        final seen:Array<String> = [];
        var pending:Null<()->Void> = null;
        final root = Loreline.play(script, (interp, character, text, tags, advance) -> {
            seen.push(text);
            pending = advance;
        }, (interp, options, select) -> select(0), interp -> {}, 'Main');
        var error:Null<loreline.Error> = null;
        try {
            final child = root.spawn('npc', (interp, character, text, tags, advance) -> seen.push(text), (interp, options, select) -> select(0), interp -> {});
            child.start('Side');
        }
        catch (e:loreline.Error) {
            error = e;
        }
        if (error == null || error.message.indexOf('roll() is declared without a body') == -1) {
            throw 'expected the error of roll in the child, got ' + (error != null ? error.message : 'none') + ' and ' + seen.join(' / ');
        }
    }

    static function testNotCalled():Void {
        expect('function roll(sides)\n\nbeat Start\n  No roll.\n', ['No roll.']);
    }

}
