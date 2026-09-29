package loreline.test;

import loreline.AstUtils;
import loreline.Lens;
import loreline.Loreline;
import loreline.Node;
import loreline.Printer;
import loreline.Script;

using StringTools;

/**
 * Tests of the printer on parentheses: a script prints back with exactly the
 * parentheses it was written with, directly and after a trip through JSON, and
 * a tree built without them still prints with the ones its meaning needs. Also
 * no space at the end of the printed lines.
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
        "Total ${(n + 1) * 2}.",
        'if mood is "angry"',
        'if mood is not "angry"',
        'if not ready',
        'if not (a or b)',
        'if a is (not b)',
        'if a == not b',
        'if not a and b is c',
        'Shown if a is not b',
        'bob: Hi. if not a'
    ];

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'parentheses print back as written', fn: () -> testLines(false)},
            {name: 'parentheses print back as written after JSON', fn: () -> testLines(true)},
            {name: 'option condition prints back as written', fn: () -> testOptionCondition()},
            {name: 'needed parentheses are added to a tree built without them', fn: () -> testTreeWithoutParens()},
            {name: 'word and symbol operators convert both ways', fn: () -> testWordOperatorConversion()},
            {name: 'no space at the end of a line', fn: () -> testNoTrailingSpaces()}
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

    /**
     * Headers followed by an indented block, keys followed by a nested object,
     * and block comments ending a line: a space is only written when something
     * follows it on the line, such as an opening brace.
     */
    static function testNoTrailingSpaces():Void {
        final source = [
            'state',
            '  menu:',
            '    price: 5',
            '    stats:',
            '      str: 1',
            '',
            'character bob',
            '  name: Bob',
            '',
            'beat Start',
            '  new state',
            '    count: 0',
            '  Hello. /* note */',
            '  choice',
            '    Yes',
            '      Ok.',
            '',
            'beat Braced {',
            '  choice {',
            '    Go {',
            '      Went.',
            '    }',
            '  }',
            '}',
            ''
        ].join('\n');
        final printed = new Printer().print(parse(source)).replace('\r\n', '\n');
        final lines = printed.split('\n');
        for (i in 0...lines.length) {
            final line = lines[i];
            if (line.endsWith(' ') || line.endsWith('\t')) {
                throw 'line ${i + 1} ends with a space: "$line" in:\n' + printed;
            }
        }
        for (expected in ['beat Braced {', 'choice {']) {
            expectLine(printed, expected, 'braced form');
        }
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
     * useWordOperators / useSymbolOperators keep the meaning: `a == !b` in words
     * must not print as `a is not b`, which reads back as `a != b`.
     */
    static function testWordOperatorConversion():Void {
        final cases = [
            {source: 'if a == !b and c != d', words: 'if a is (not b) and c is not d', symbols: 'if a == (!b) && c != d'},
            {source: 'if not a or b is c', words: 'if not a or b is c', symbols: 'if !a || b == c'}
        ];
        final errors:Array<String> = [];
        for (item in cases) {
            try {
                final script = parse(wrap(item.source));
                AstUtils.useWordOperators(script);
                final words = new Printer().print(script);
                expectLine(words, item.words, 'in words');
                // Read back in words, then converted to symbols
                final reparsed = parse(words);
                AstUtils.useSymbolOperators(reparsed);
                expectLine(new Printer().print(reparsed), item.symbols, 'in symbols');
            }
            catch (e:Any) {
                errors.push(Std.string(e));
            }
        }
        if (errors.length > 0) throw errors.join('\n');
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
