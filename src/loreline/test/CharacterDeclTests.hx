package loreline.test;

import loreline.Loreline;
import loreline.Node;
import loreline.Script;

using StringTools;

/**
 * Tests of a character declared by its identifier alone, `character Barista`,
 * with no body: where the file ends right after it, and how it prints back.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class CharacterDeclTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'a character with no body at the end of the file', fn: () -> testEndOfFile()},
            {name: 'a character with no body and CRLF line ends', fn: () -> testCrlf()},
            {name: 'a character with empty braces still parses', fn: () -> testEmptyBraces()},
            {name: 'a character with no body prints on one line', fn: () -> testPrint()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('character declarations: ' + test.name);
            }
            catch (e:Any) {
                fail('character declarations: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    /** The characters declared at the top of a script, by name, with their number of fields */
    static function characters(script:Script):String {
        return [for (node in script.body) if (node is NCharacterDecl) {
            final character:NCharacterDecl = cast node;
            character.name + ':' + character.fields.length;
        }].join(',');
    }

    static function testEndOfFile():Void {
        for (source in ['beat Start\n  Hi.\n\ncharacter Barista', 'beat Start\n  Hi.\n\ncharacter Barista\n', 'character Barista']) {
            final found = characters(parse(source));
            if (found != 'Barista:0') throw 'expected Barista:0, got "$found" for ${haxe.Json.stringify(source)}';
        }
    }

    static function testCrlf():Void {
        final found = characters(parse('character Barista\r\ncharacter Client\r\n\r\nbeat Start\r\n  Barista: Hi.\r\n'));
        if (found != 'Barista:0,Client:0') throw 'expected Barista:0,Client:0, got "$found"';
    }

    static function testEmptyBraces():Void {
        final found = characters(parse('character Barista {}\n\nbeat Start\n  Barista: Hi.\n'));
        if (found != 'Barista:0') throw 'expected Barista:0, got "$found"';
    }

    static function testPrint():Void {
        final printed = Loreline.print(parse('character Barista\ncharacter Client\n  name: Sam\n\nbeat Start\n  Barista: Hi.\n'));
        if (printed.indexOf('character Barista\n\ncharacter Client\n  name: Sam\n') == -1) throw 'printed as:\n' + printed;
        // Printing again gives the same text
        if (Loreline.print(parse(printed)) != printed) throw 'a second print changed the text:\n' + Loreline.print(parse(printed));
    }

}
