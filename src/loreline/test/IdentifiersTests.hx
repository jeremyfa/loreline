package loreline.test;

import loreline.Identifiers;
import loreline.Lens;
import loreline.Node;
import loreline.Loreline;
import loreline.Script;

using StringTools;
using loreline.Utf8;

/**
 * Tests of names in any language: which characters make a name, how a name is
 * read whatever the units of the target, where errors point after a name
 * beyond ASCII, the messages on full-width marks typed by input methods, and
 * the printer keeping the braces of `${name}` when a name character follows.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class IdentifiersTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'characters that start or continue a name', fn: () -> testClassification()},
            {name: 'a name is read whole, whatever the units', fn: () -> testNameEnd()},
            {name: 'tables are sorted and do not overlap', fn: () -> testTables()},
            {name: 'errors point after a name beyond ASCII', fn: () -> testErrorPositions()},
            {name: 'full-width marks give a clear error in fields', fn: () -> testFieldErrors()},
            {name: 'full-width marks give a clear error in functions', fn: () -> testFunctionErrors()},
            {name: 'the printer keeps the braces a name needs', fn: () -> testPrinterBraces()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('identifiers: ' + test.name);
            }
            catch (e:Any) {
                fail('identifiers: ' + test.name, Std.string(e));
            }
        }

    }

    /** How many units a character from U+0800 to U+FFFF takes on this target */
    static function unitsOfBmp():Int {
        return Identifiers.UNITS == 4 ? 3 : 1;
    }

    static function testClassification():Void {
        final errors:Array<String> = [];
        inline function check(text:String, start:Bool, part:Bool) {
            final c = Identifiers.codeAt(text, 0);
            if (Identifiers.isStart(c) != start) errors.push('$text (U+${StringTools.hex(c, 4)}) start: expected $start');
            if (Identifiers.isPart(c) != part) errors.push('$text (U+${StringTools.hex(c, 4)}) part: expected $part');
        }
        // Letters of any language, `_`, emoji and flags start a name
        for (text in ['a', 'Z', '_', 'é', 'Ж', 'λ', '国', 'ー', '々', 'ラ', '한', 'Ａ', '𠀀', '🐉', '⭐', '❤', '🇫']) {
            check(text, true, true);
        }
        // Digits, marks, middle dots and the pieces of emoji sequences only continue it
        for (text in ['0', '9', '٣', '·', '・', '\u0301', '\u200D', '\uFE0F', '🏽', '\u{E0067}']) {
            check(text, false, true);
        }
        // Punctuation, spaces and symbols are not part of a name
        for (text in [' ', ':', '：', '，', '（', '。', '-', '$', '#', '©', '™', '‼', '↔', '\u20E3', '\u3000']) {
            check(text, false, false);
        }
        // ASCII punctuation and operators, punctuation of other languages, the
        // wavy dash and the alternation mark (pictographic, but punctuation in
        // Japanese text), and the em and en dashes
        final punctuation = '!?.,;:()[]{}<>+-*/%=&|~^@#\'"`\\';
        for (i in 0...punctuation.length) {
            check(punctuation.charAt(i), false, false);
        }
        for (text in ['！', '？', '、', '；', '）', '「', '」', '『', '』', '《', '》', '【', '】', '…', '«', '»', '“', '”', '‘', '’', '¿', '¡', '〜', '〰', '〽', Identifiers.textOf(0x2014), Identifiers.textOf(0x2013)]) {
            check(text, false, false);
        }
        if (Identifiers.scriptOf(Identifiers.codeAt('a', 0)) != 'Latin') errors.push('a is Latin');
        if (Identifiers.scriptOf(Identifiers.codeAt('é', 0)) != 'Latin') errors.push('é is Latin');
        if (Identifiers.scriptOf(Identifiers.codeAt('а', 0)) != 'Cyrillic') errors.push('а is Cyrillic');
        if (Identifiers.scriptOf(Identifiers.codeAt('ο', 0)) != 'Greek') errors.push('ο is Greek');
        if (Identifiers.scriptOf(Identifiers.codeAt('国', 0)) != null) errors.push('国 has no lookalike alphabet');
        if (Identifiers.scriptOf(Identifiers.codeAt('_', 0)) != null) errors.push('_ is no letter');
        if (!Identifiers.isUpperCase(Identifiers.codeAt('É', 0))) errors.push('É is upper case');
        if (!Identifiers.isLowerCase(Identifiers.codeAt('ж', 0))) errors.push('ж is lower case');
        if (Identifiers.isLowerCase(Identifiers.codeAt('国', 0)) || Identifiers.isUpperCase(Identifiers.codeAt('国', 0))) errors.push('国 has no case');
        if (errors.length > 0) throw errors.join('\n');
    }

    static function testNameEnd():Void {
        final errors:Array<String> = [];
        // Each case: a text, and the part of it that is a name
        final cases = [
            ['coins💰 left', 'coins💰'],
            ['👨‍👩‍👧x!', '👨‍👩‍👧x'],
            ['👍🏽!', '👍🏽'],
            ['🏴󠁧󠁢󠁥󠁮󠁧󠁿.', '🏴󠁧󠁢󠁥󠁮󠁧󠁿'],
            ['国王：你好', '国王'],
            ['𠀀𠀁 text', '𠀀𠀁'],
            ['café.', 'café'],
            ['Brand™', 'Brand'],
            ['角色1说', '角色1说']
        ];
        for (item in cases) {
            final text = item[0];
            final end = Identifiers.nameEnd(text, 0);
            final name = text.uSubstr(0, end);
            if (name != item[1]) errors.push('"$text": expected "${item[1]}", got "$name"');
        }
        // Stepping back over a whole character
        final text = 'a𠀀';
        final before = Identifiers.startBefore(text, text.uLength());
        if (Identifiers.codeAt(text, before) != 0x20000) errors.push('startBefore: expected the start of 𠀀');
        if (errors.length > 0) throw errors.join('\n');
    }

    static function testTables():Void {
        for (table in Identifiers.tables()) {
            if (table.length % 2 != 0) throw 'A table has an odd length';
            var previous = -1;
            var i = 0;
            while (i < table.length) {
                if (table[i] > table[i + 1]) throw 'Range ${StringTools.hex(table[i])}..${StringTools.hex(table[i + 1])} is reversed';
                if (table[i] <= previous) throw 'Range ${StringTools.hex(table[i])} overlaps or is out of order';
                previous = table[i + 1];
                i += 2;
            }
        }
    }

    /** The error of a script that doesn't parse */
    static function parseError(source:String):loreline.Error {
        var thrown:Null<loreline.Error> = null;
        final script = try Loreline.parse(source) catch (e:loreline.Error) {
            thrown = e;
            null;
        }
        if (script != null) throw 'Expected an error for:\n' + source;
        final error = thrown != null ? thrown : Loreline.lastError();
        if (error == null) throw 'No error for:\n' + source;
        return error;
    }

    static function expectError(source:String, message:String, line:Int, column:Int):Void {
        final error = parseError(source);
        if (message != null && error.message.indexOf(message) == -1) {
            throw 'Expected "$message", got "${error.message}" for:\n$source';
        }
        if (error.pos == null || error.pos.line != line || error.pos.column != column) {
            final got = error.pos == null ? 'no position' : '${error.pos.line}:${error.pos.column}';
            throw 'Expected the error at $line:$column, got $got ("${error.message}") for:\n$source';
        }
    }

    static function testErrorPositions():Void {
        // The `)` comes after two Chinese characters
        expectError('beat Start\n  国王 = )\n', null, 2, 6 + 2 * unitsOfBmp());
    }

    static function testFieldErrors():Void {
        final u = unitsOfBmp();
        expectError('state\n  金币：10\n', '"：" looks like ":" but isn\'t', 2, 3 + 2 * u);
        expectError('character 国王\n  name：路易斯\n', '"：" looks like ":" but isn\'t', 2, 7);
        expectError('state\n  金币（: 10\n', '"（" looks like "(" but isn\'t', 2, 3 + 2 * u);
    }

    /**
     * The error found in the code of the first function of a script, the way
     * editors see it.
     */
    static function functionError(source:String):loreline.Error {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        final lens = new Lens(script);
        final func = lens.getNodesOfType(NFunctionDecl, false)[0];
        final error = lens.getFuncLorscript(func).error;
        if (error == null || error.pos == null) throw 'Expected an error in the function of:\n' + source;
        return error;
    }

    static function expectFunctionError(source:String, message:String, line:Int, column:Int):Void {
        final error = functionError(source);
        if (message != null && error.message.indexOf(message) == -1) {
            throw 'Expected "$message", got "${error.message}" for:\n$source';
        }
        if (error.pos == null || error.pos.line != line || error.pos.column != column) {
            final got = error.pos == null ? 'no position' : '${error.pos.line}:${error.pos.column}';
            throw 'Expected the error at $line:$column, got $got ("${error.message}") for:\n$source';
        }
    }

    static function testFunctionErrors():Void {
        final u = unitsOfBmp();
        expectFunctionError('function f()\n  return { 国王：1 }\n', '"：" looks like ":" but isn\'t', 2, 12 + 2 * u);
        expectFunctionError('function f()\n  return f（1)\n', '"（" looks like "(" but isn\'t', 2, 11);
        expectFunctionError('function f()\n  return 1 → 2\n', 'Unexpected character: →', 2, 12);
        #if !neko
        // An error of the function parser after a name beyond U+FFFF lands where
        // it does after a one letter name, moved by the extra units of `𠀀`. On
        // Neko, that parser counts bytes while the conversion counts characters,
        // which shifts its positions after a character beyond ASCII.
        final ascii = functionError('function f(a)\n  return a + )\n');
        final astral = Identifiers.UNITS == 1 ? 1 : (Identifiers.UNITS == 2 ? 2 : 4);
        expectFunctionError('function f(𠀀)\n  return 𠀀 + )\n', ascii.message, 2, ascii.pos.column + astral - 1);
        #end
    }

    static function testPrinterBraces():Void {
        final source = [
            'state',
            '  name: "Bob"',
            '  国王: "Louis"',
            '  hp: 3',
            '',
            'beat Start',
            "  Hello ${name}s, ${国王}说, ${hp}💖, ${name}! and ${name}.",
            ''
        ].join('\n');
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError();
        final printed = Loreline.print(script);
        final expected = "Hello ${name}s, ${国王}说, ${hp}💖, $name! and $name.";
        if (printed.indexOf(expected) == -1) throw 'Expected "$expected" in:\n' + printed;
    }

}
