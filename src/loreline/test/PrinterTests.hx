package loreline.test;

import loreline.Lens;
import loreline.Loreline;
import loreline.Node;
import loreline.Printer;
import loreline.Script;

using StringTools;

/**
 * Tests of the printer on parentheses: a script prints back with exactly the
 * parentheses it was written with, directly and after a trip through JSON, and
 * a tree built without them still prints with the ones its meaning needs.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class PrinterTests {

    /**
     * Lines that must print back unchanged, each inside a beat.
     */
    static final LINES = [
        'if a and b and c',
        'if (a and b) and c',
        'if a or b and c',
        'if (a or b) and c',
        'if a and (b or c)',
        'if (a and b)',
        'if ((a))',
        'if (a) or b',
        'if !(a == b)',
        'x = (1 + 2) * 3',
        'x = 1 + 2 * 3',
        'x = -(a + b)',
        'x = a - (b - c)',
        'x = (a - b) - c',
        'x = (items).length',
        'Some text. if (a and b) or c',
        'Other text. if (a) and b',
        'bob: Hello. if (a or b) and c',
        "Total ${(n + 1) * 2}."
    ];

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'parentheses print back as written', fn: () -> testLines(false)},
            {name: 'parentheses print back as written after JSON', fn: () -> testLines(true)},
            {name: 'option condition prints back as written', fn: () -> testOptionCondition()},
            {name: 'needed parentheses are added to a tree built without them', fn: () -> testTreeWithoutParens()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('printer: ' + test.name);
            }
            catch (e:Any) {
                fail('printer: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError();
        return script;
    }

    static function wrap(line:String):String {
        return [
            'character bob',
            '  name: Bob',
            '',
            'beat Start',
            '  ' + line,
            line.startsWith('if ') ? '    Yes.' : '',
            ''
        ].join('\n');
    }

    static function throughJson(script:Script):Script {
        return Script.fromJson(haxe.Json.parse(haxe.Json.stringify(script.toJson())));
    }

    static function expectLine(printed:String, line:String, what:String):Void {
        for (printedLine in printed.replace('\r\n', '\n').split('\n')) {
            if (printedLine.trim() == line) return;
        }
        throw '$what: "$line" printed as:\n' + printed;
    }

    static function testLines(json:Bool):Void {
        final errors:Array<String> = [];
        for (line in LINES) {
            try {
                var script = parse(wrap(line));
                if (json) script = throughJson(script);
                expectLine(new Printer().print(script), line, json ? 'after JSON' : 'printed');
            }
            catch (e:Any) {
                errors.push(Std.string(e));
            }
        }
        if (errors.length > 0) throw errors.join('\n');
    }

    static function testOptionCondition():Void {
        final source = [
            'beat Start',
            '  choice',
            '    First if (a and b) and c',
            '      Picked.',
            '    Second if (a) or b',
            '      Picked.',
            ''
        ].join('\n');
        for (json in [false, true]) {
            var script = parse(source);
            if (json) script = throughJson(script);
            final printed = new Printer().print(script);
            expectLine(printed, 'First if (a and b) and c', json ? 'after JSON' : 'printed');
            expectLine(printed, 'Second if (a) or b', json ? 'after JSON' : 'printed');
        }
    }

    /**
     * Takes the parentheses off every expression, like a tree built by code or
     * read from JSON written before they were kept, and checks the printed
     * script still means the same.
     */
    static function testTreeWithoutParens():Void {
        final cases = [
            {source: 'x = (1 + 2) * 3', expected: 'x = (1 + 2) * 3'},
            {source: 'x = a - (b - c)', expected: 'x = a - (b - c)'},
            {source: 'x = ((a - b)) - c', expected: 'x = a - b - c'},
            {source: 'x = -(a + b)', expected: 'x = -(a + b)'},
            {source: 'if !(a == b)', expected: 'if !(a == b)'},
            {source: 'if (a or b) and c', expected: 'if (a or b) and c'},
            {source: 'if ((a and b))', expected: 'if (a and b)'},
            {source: 'x = (items).length', expected: 'x = items.length'}
        ];
        final errors:Array<String> = [];
        for (item in cases) {
            try {
                final script = parse(wrap(item.source));
                for (expr in new Lens(script).getNodesOfType(NExpr)) {
                    expr.parens = 0;
                }
                expectLine(new Printer().print(script), item.expected, 'without parentheses');
            }
            catch (e:Any) {
                errors.push(Std.string(e));
            }
        }
        if (errors.length > 0) throw errors.join('\n');
    }

}
