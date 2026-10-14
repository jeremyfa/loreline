package loreline.test;

import loreline.Identifiers;
import loreline.Texts;

using loreline.Utf8;

/**
 * Tests of whole characters read from a text in the units of the target: a
 * surrogate pair or a run of bytes is one character, counted and stepped over
 * as one. The expectations follow the units of the target, so the same tests
 * pass everywhere.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class CharsTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'a character is read whole, with its units', fn: () -> testCodeAt()},
            {name: 'past the end, nothing is read', fn: () -> testPastEnd()},
            {name: 'characters are counted, whatever the units', fn: () -> testCount()},
            {name: 'a step back lands on the start of a character', fn: () -> testStartBefore()},
            {name: 'a character is written with its units', fn: () -> testTextOf()},
            #if (neko || php)
            {name: 'a vector of code points holds one character per slot', fn: () -> testVector()},
            #end
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('chars: ' + test.name);
            }
            catch (e:Any) {
                fail('chars: ' + test.name, Std.string(e));
            }
        }

    }

    /** A character, its code point, and the units it takes on this target */
    static final CASES:Array<{text:String, code:Int, units:Int}> = [
        {text: 'a', code: 0x61, units: 1},
        {text: 'é', code: 0xE9, units: Identifiers.UNITS == 4 ? 2 : 1},
        {text: '国', code: 0x56FD, units: Identifiers.UNITS == 4 ? 3 : 1},
        {text: '😀', code: 0x1F600, units: Identifiers.UNITS}
    ];

    static final MIXED = 'aé国😀';

    static function testCodeAt():Void {
        for (item in CASES) {
            if (item.text.uLength() != item.units) throw '"${item.text}" takes ${item.text.uLength()} units, expected ${item.units}';
            final code = Identifiers.codeAt(item.text, 0);
            if (code != item.code) throw '"${item.text}": expected ${StringTools.hex(item.code)}, got ${StringTools.hex(code)}';
            final units = Identifiers.unitsAt(item.text, 0);
            if (units != item.units) throw '"${item.text}": expected ${item.units} units, got $units';
        }
        // Each character of a mixed text, at the unit where it starts
        var pos = 0;
        for (item in CASES) {
            final code = Identifiers.codeAt(MIXED, pos);
            if (code != item.code) throw 'at $pos: expected ${StringTools.hex(item.code)}, got ${StringTools.hex(code)}';
            pos += Identifiers.unitsAt(MIXED, pos);
        }
        if (pos != MIXED.uLength()) throw 'the characters end at $pos, the text at ${MIXED.uLength()}';
    }

    static function testPastEnd():Void {
        final len = MIXED.uLength();
        if (Identifiers.codeAt(MIXED, len) != -1) throw 'codeAt past the end should give -1';
        if (Identifiers.unitsAt(MIXED, len) != 0) throw 'unitsAt past the end should give 0';
        if (Identifiers.startBefore(MIXED, 0) != -1) throw 'startBefore at the start should give -1';
    }

    static function testCount():Void {
        if (Identifiers.characterCount(MIXED) != 4) throw 'expected 4 characters, got ${Identifiers.characterCount(MIXED)}';
        if (Identifiers.characterCount('') != 0) throw 'an empty text has no character';
        // The string builtins count the same characters by another route
        if (Identifiers.characterCount(MIXED) != Texts.length(MIXED)) throw 'characterCount and Texts.length disagree';
    }

    static function testStartBefore():Void {
        final len = MIXED.uLength();
        // Walking back lands on each character in turn
        var pos = len;
        var i = CASES.length;
        while (i > 0) {
            i--;
            pos = Identifiers.startBefore(MIXED, pos);
            final code = Identifiers.codeAt(MIXED, pos);
            if (code != CASES[i].code) throw 'stepping back to $pos: expected ${StringTools.hex(CASES[i].code)}, got ${StringTools.hex(code)}';
        }
        if (pos != 0) throw 'walking back should end at 0, got $pos';
        if (Identifiers.startBefore(MIXED, len) != len - Identifiers.UNITS) throw 'the last character starts ${Identifiers.UNITS} units before the end';
    }

    static function testTextOf():Void {
        for (item in CASES) {
            final text = Identifiers.textOf(item.code);
            if (text != item.text) throw 'textOf(${StringTools.hex(item.code)}): expected "${item.text}", got "$text"';
            if (text.uLength() != item.units) throw 'textOf(${StringTools.hex(item.code)}) takes ${text.uLength()} units, expected ${item.units}';
        }
    }

    #if (neko || php)
    static function testVector():Void {
        final codes = loreline.Utf8.toCodes(MIXED);
        if (codes.length != 4) throw 'expected 4 slots, got ${codes.length}';
        for (i in 0...CASES.length) {
            if (Identifiers.codeAt(codes, i) != CASES[i].code) throw 'slot $i: expected ${StringTools.hex(CASES[i].code)}';
            if (Identifiers.unitsAt(codes, i) != 1) throw 'slot $i should take one unit';
        }
        if (Identifiers.codeAt(codes, 4) != -1) throw 'past the end should give -1';
        if (Identifiers.startBefore(codes, 4) != 3) throw 'a step back is one slot';
    }
    #end

}
