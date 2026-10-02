package loreline.test;

import loreline.Interpreter;

using StringTools;

/**
 * Tests of the value rules that test files can't express: the ordering errors,
 * in scripts and in functions, and which texts are read as numbers, with
 * spaces, tabs and line breaks that a test file can't write in a text.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class ValuesTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'ordering other values is an error in scripts', fn: () -> testOrderingErrors(false)},
            {name: 'ordering other values is an error in functions', fn: () -> testOrderingErrors(true)},
            {name: 'texts read as numbers', fn: () -> testNumericTexts(true)},
            {name: 'texts not read as numbers', fn: () -> testNumericTexts(false)}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('values: ' + test.name);
            }
            catch (e:Any) {
                fail('values: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    /**
     * Plays a script with a host function `text` returning the given text, and
     * returns its dialogue lines, or the error message prefixed with "error: ".
     */
    static function play(source:String, ?text:String):Array<String> {
        final functions:FunctionsMap = #if loreline_functions_map_dynamic_access {} #else new Map<String, Any>() #end;
        #if loreline_auto_wrap_functions
        functions.set('text', (interp:Interpreter, args:Array<Any>) -> text);
        #else
        functions.set('text', () -> text);
        #end
        final seen:Array<String> = [];
        try {
            Loreline.play(parse(source), (interp, character, text, tags, advance) -> {
                seen.push(text);
                advance();
            }, (interp, options, select) -> {}, interp -> {}, null, ({functions: functions} : InterpreterOptions));
        }
        catch (e:Any) {
            seen.push('error: ' + ((e is loreline.Error) ? (cast e:loreline.Error).message : Std.string(e)));
        }
        return seen;
    }

    /** Pairs that can't be ordered: anything but numbers and texts written as numbers. */
    static final UNORDERED = [
        ['"a"', '"b"'],
        ['"5"', '"6"'],
        ['"abc"', '5'],
        ['5', '"abc"'],
        ['""', '0'],
        ['" "', '0'],
        ['true', '1'],
        ['true', 'false'],
        ['null', '1'],
        ['1', 'null'],
        ['[]', '1'],
        ['[1]', '[2]'],
        ['{ a: 1 }', '1']
    ];

    static final OPERATORS = ['<', '>', '<=', '>='];

    static function testOrderingErrors(inFunction:Bool):Void {
        final errors:Array<String> = [];
        for (pair in UNORDERED) {
            for (op in OPERATORS) {
                final lines = [
                    'state',
                    '  a: ' + pair[0],
                    '  b: ' + pair[1],
                    ''
                ];
                if (inFunction) {
                    lines.push('function order(x, y)');
                    lines.push('  return x $op y');
                    lines.push('');
                }
                lines.push('beat Start');
                lines.push("  Result is ${" + (inFunction ? 'order(a, b)' : 'a $op b') + "}.");
                final seen = play(lines.join('\n') + '\n');
                final last = seen.length > 0 ? seen[seen.length - 1] : '';
                if (!last.startsWith('error: ') || last.indexOf('Cannot compare') == -1) {
                    errors.push('${pair[0]} $op ${pair[1]}: expected a "Cannot compare" error, got ' + seen.join(', '));
                }
            }
        }
        if (errors.length > 0) throw errors.join('\n');
    }

    /** Texts read as numbers, with the number they are equal to. */
    static final NUMERIC:Array<{text:String, value:String}> = [
        {text: '5', value: '5'},
        {text: ' 5 ', value: '5'},
        {text: '\t5\n', value: '5'},
        {text: '\r\n5\r\n', value: '5'},
        {text: '+5', value: '5'},
        {text: '-5', value: '-5'},
        {text: '007', value: '7'},
        {text: '5.', value: '5'},
        {text: '.5', value: '0.5'},
        {text: '-.5', value: '-0.5'},
        {text: '5.25', value: '5.25'},
        {text: '5.0', value: '5'},
        {text: '1e3', value: '1000'},
        {text: '1E3', value: '1000'},
        {text: '1e+3', value: '1000'},
        {text: '2.5e-1', value: '0.25'},
        {text: '0', value: '0'},
        {text: '-0', value: '0'},
        {text: '123456789', value: '123456789'}
    ];

    /** Texts not read as numbers: equal to no number, not even 0. */
    static final NOT_NUMERIC = [
        '', ' ', '\t', 'abc', '5abc', 'abc5', '0x10', '0b1', 'Infinity', '-Infinity', 'NaN',
        '1e', 'e3', '.', '-', '+', '5 5', '1,5', '--5', '+-5', '5e3.5', '5..0', '1_000', 'five'
    ];

    static function testNumericTexts(numeric:Bool):Void {
        final errors:Array<String> = [];
        final source = (number:String) -> [
            'beat Start',
            "  Equal is ${text() == " + number + "}, reversed ${" + number + " == text()}, different ${text() != " + number + "}.",
            ''
        ].join('\n');
        if (numeric) {
            for (item in NUMERIC) {
                final seen = play(source(item.value), item.text);
                final expected = 'Equal is true, reversed true, different false.';
                if (seen.join(', ') != expected) errors.push('"${item.text.urlEncode()}" == ${item.value}: expected "$expected", got "' + seen.join(', ') + '"');
                // Ordered as that number
                final order = play("beat Start\n  Order is ${text() < " + item.value + " + 1} ${text() >= " + item.value + "}.\n", item.text);
                if (order.join(', ') != 'Order is true true.') errors.push('"${item.text.urlEncode()}" ordered with ${item.value}: got "' + order.join(', ') + '"');
            }
        }
        else {
            for (text in NOT_NUMERIC) {
                for (number in ['0', '5', '1000']) {
                    final seen = play(source(number), text);
                    final expected = 'Equal is false, reversed false, different true.';
                    if (seen.join(', ') != expected) errors.push('"${text.urlEncode()}" == $number: expected "$expected", got "' + seen.join(', ') + '"');
                }
            }
        }
        if (errors.length > 0) throw errors.join('\n');
    }

}
