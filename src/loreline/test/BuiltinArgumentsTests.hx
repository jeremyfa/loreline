package loreline.test;

import loreline.Interpreter;

using StringTools;

/**
 * Tests of the errors of built-in functions given an argument they can't use:
 * the same message on every target, naming the function and what it got, in a
 * beat as in the code of a function.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class BuiltinArgumentsTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'wrong arguments are errors in a beat', fn: () -> testErrors(false)},
            {name: 'wrong arguments are errors in a function', fn: () -> testErrors(true)},
            {name: 'a wrong argument of wait is an error', fn: () -> testWait()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('builtin arguments: ' + test.name);
            }
            catch (e:Any) {
                fail('builtin arguments: ' + test.name, Std.string(e));
            }
        }

    }

    /** Calls, and the message of the error each one gives. */
    static final CASES:Array<{call:String, error:String}> = [
        // Numbers
        {call: 'floor("abc")', error: 'floor() expects a number, got "abc"'},
        {call: 'floor(null)', error: 'floor() expects a number, got null'},
        {call: 'floor(true)', error: 'floor() expects a number, got bool'},
        {call: 'floor([1])', error: 'floor() expects a number, got array'},
        {call: 'floor({ a: 1 })', error: 'floor() expects a number, got object'},
        {call: 'ceil("")', error: 'ceil() expects a number, got ""'},
        {call: 'round(" ")', error: 'round() expects a number, got " "'},
        {call: 'abs(null)', error: 'abs() expects a number, got null'},
        {call: 'min(1, "x")', error: 'min() expects a number, got "x"'},
        {call: 'max(null, 1)', error: 'max() expects a number, got null'},
        {call: 'clamp(1, null, 2)', error: 'clamp() expects a number, got null'},
        {call: 'pow("a", 2)', error: 'pow() expects a number, got "a"'},
        {call: 'random("a", 2)', error: 'random() expects a number, got "a"'},
        {call: 'random_float(null, 1)', error: 'random_float() expects a number, got null'},
        {call: 'chance(null)', error: 'chance() expects a number, got null'},
        {call: 'seed_random("x")', error: 'seed_random() expects a number, got "x"'},
        {call: 'string_sub("abc", "x")', error: 'string_sub() expects a number, got "x"'},
        {call: 'string_sub("abc", 0, [1])', error: 'string_sub() expects a number, got array'},
        {call: 'string_repeat("a", null)', error: 'string_repeat() expects a number, got null'},
        // Texts
        {call: 'string_length(null)', error: 'string_length() expects a text, got null'},
        {call: 'string_upper([1])', error: 'string_upper() expects a text, got array'},
        {call: 'string_lower({ a: 1 })', error: 'string_lower() expects a text, got object'},
        {call: 'string_sub(null, 1)', error: 'string_sub() expects a text, got null'},
        {call: 'string_index("abc", null)', error: 'string_index() expects a text, got null'},
        {call: 'string_split(null, ",")', error: 'string_split() expects a text, got null'},
        {call: 'string_replace("a", null, "b")', error: 'string_replace() expects a text, got null'},
        {call: 'string_contains(null, "a")', error: 'string_contains() expects a text, got null'},
        {call: 'string_starts("a", [1])', error: 'string_starts() expects a text, got array'},
        {call: 'string_ends(null, "a")', error: 'string_ends() expects a text, got null'},
        {call: 'string_trim(null)', error: 'string_trim() expects a text, got null'},
        {call: 'string_repeat(null, 2)', error: 'string_repeat() expects a text, got null'},
        {call: 'plural(1, null, "x")', error: 'plural() expects a text, got null'},
        {call: 'array_join([1], null)', error: 'array_join() expects a text, got null'},
        {call: 'map_get({ a: 1 }, null)', error: 'map_get() expects a text, got null'},
        {call: 'map_has({ a: 1 }, [1])', error: 'map_has() expects a text, got array'},
        {call: 'map_set({ a: 1 }, null, 2)', error: 'map_set() expects a text, got null'},
        {call: 'map_remove({ a: 1 }, null)', error: 'map_remove() expects a text, got null'}
    ];

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    /** Plays a script and returns its lines, or the message of its error prefixed with "error: ". */
    static function play(source:String):Array<String> {
        final seen:Array<String> = [];
        try {
            Loreline.play(parse(source), (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> {}, interp -> {});
        }
        catch (e:Any) {
            seen.push('error: ' + ((e is loreline.Error) ? (cast e:loreline.Error).message : Std.string(e)));
        }
        return seen;
    }

    static function testErrors(inFunction:Bool):Void {
        final errors:Array<String> = [];
        for (item in CASES) {
            // Double quotes: Haxe would read ${...} in single quotes
            final source = inFunction
                ? "function check()\n  return " + item.call + "\n\nbeat Start\n  Value is ${check()}.\n"
                : "beat Start\n  Value is ${" + item.call + "}.\n";
            final seen = play(source);
            final expected = 'error: ' + item.error;
            if (seen.join(' / ') != expected) {
                errors.push(item.call + ': expected "' + item.error + '", got "' + seen.join(' / ') + '"');
            }
        }
        if (errors.length > 0) throw errors.join('\n');
    }

    static function testWait():Void {
        final seen = play('beat Start\n  Before.\n  wait("soon")\n  After.\n');
        final expected = 'Before. / error: wait() expects a number, got "soon"';
        if (seen.join(' / ') != expected) throw 'expected "' + expected + '", got "' + seen.join(' / ') + '"';
    }

}
