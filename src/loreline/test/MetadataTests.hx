package loreline.test;

import loreline.Loreline;
import loreline.Script;

using StringTools;

/**
 * Tests of the `metadata` block: the values a script gives its story, read
 * by the app running it with `script.getMetadataField`, and of `Ifid`, which
 * makes and writes the IFID of a story.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class MetadataTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'fields are read from the script', fn: () -> testFields()},
            {name: 'a missing field or block gives null', fn: () -> testMissing()},
            {name: 'a second block is an error', fn: () -> testSecondBlock()},
            {name: 'a value that is not constant is an error', fn: () -> testNotConstant()},
            {name: 'metadata stays a name elsewhere', fn: () -> testName()},
            {name: 'the block prints back and goes through JSON', fn: () -> testPrintAndJson()},
            {name: 'the metadata can\'t be changed by the script', fn: () -> testReadOnly()},
            {name: 'an IFID is an uppercase UUID, new each time', fn: () -> testIfidGenerate()},
            {name: 'an IFID replaces the one of the block', fn: () -> testIfidReplace()},
            {name: 'an IFID is added to a block without one', fn: () -> testIfidAddToBlock()},
            {name: 'an IFID creates the block when there is none', fn: () -> testIfidNewBlock()},
            {name: 'a new block goes after the comments at the top', fn: () -> testIfidAfterHeader()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('metadata: ' + test.name);
            }
            catch (e:Any) {
                fail('metadata: ' + test.name, Std.string(e));
            }
        }

    }

    static final SOURCE = 'metadata\n  title: The Coffee Shop\n  author: [Ana, Bob]\n  version: 1.2\n  credits: { music: Cleo }\n\nbeat Start\n  Hello.\n';

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    /** The error parsing a source gives, or null */
    static function parseError(source:String):Null<loreline.Error> {
        var error:Null<loreline.Error> = null;
        final script = try Loreline.parse(source) catch (e:loreline.Error) {
            error = e;
            null;
        }
        if (error == null && script == null) error = Loreline.lastError();
        return script == null ? error : null;
    }

    static function testFields():Void {
        final script = parse(SOURCE);
        if (script.getMetadataField('title') != 'The Coffee Shop') throw 'title: ' + script.getMetadataField('title');
        if (script.getMetadataField('version') != 1.2) throw 'version: ' + script.getMetadataField('version');
        final author:Any = script.getMetadataField('author');
        if (Arrays.arrayLength(author) != 2 || Arrays.arrayGet(author, 1) != 'Bob') throw 'author: ' + author;
        final credits:Any = script.getMetadataField('credits');
        if (Objects.getField(null, credits, 'music') != 'Cleo') throw 'credits: ' + credits;
    }

    static function testMissing():Void {
        if (parse(SOURCE).getMetadataField('genre') != null) throw 'expected null for a missing field';
        if (parse('beat Start\n  Hello.\n').getMetadataField('title') != null) throw 'expected null without a block';
    }

    static function testSecondBlock():Void {
        final error = parseError('metadata\n  title: One\n\nmetadata\n  title: Two\n\nbeat Start\n  Hi.\n');
        if (error == null) throw 'expected an error';
        if (error.message.indexOf('only one metadata block') == -1) throw 'got "${error.message}"';
        if (error.pos == null || error.pos.line != 4) throw 'expected the error on line 4, got ${error.pos}';
    }

    static function testNotConstant():Void {
        for (value in ['Hello $$name', 'floor(2.5)', '$${1 + 2}']) {
            final error = parseError('metadata\n  title: $value\n\nbeat Start\n  Hi.\n');
            if (error == null) throw 'expected an error for $value';
            if (error.message.indexOf('constant') == -1) throw 'got "${error.message}" for $value';
        }
    }

    static function testName():Void {
        final script = parse('state\n  metadata: 1\n\nbeat metadata\n  Hi.\n\nbeat Start\n  -> metadata\n');
        if (script.getMetadataField('title') != null) throw 'a state field named metadata became a block';
    }

    static function testPrintAndJson():Void {
        final script = parse(SOURCE);
        final printed = Loreline.print(script);
        if (printed.indexOf('metadata\n  title: The Coffee Shop\n') == -1) throw 'printed as:\n' + printed;
        if (parse(printed).getMetadataField('version') != 1.2) throw 'the printed script lost its metadata:\n' + printed;
        final back = Script.fromJson(haxe.Json.parse(haxe.Json.stringify(script.toJson())));
        if (back.getMetadataField('title') != 'The Coffee Shop') throw 'the metadata was lost through JSON';
    }

    static function testReadOnly():Void {
        for (line in ['metadata = 3', 'metadata.title = "Other"']) {
            final script = parse('metadata\n  title: One\n\nbeat Start\n  $line\n  Hi.\n');
            var error:Null<loreline.Error> = null;
            try {
                Loreline.play(script, (interp, character, text, tags, advance) -> advance(), (interp, options, select) -> select(0), interp -> {});
            }
            catch (e:loreline.Error) {
                error = e;
            }
            if (error == null || error.message.indexOf("metadata can't be changed") == -1) {
                throw 'expected an error for $line, got ' + (error != null ? error.message : 'none');
            }
        }
    }

    static final IFID = '448E73DF-2D2F-47E7-A494-A46B40D4CFB3';

    static function testIfidGenerate():Void {
        final first = Ifid.generate();
        if (!~/^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/.match(first)) throw 'not an uppercase UUID v4: $first';
        if (Ifid.generate() == first) throw 'two IFIDs are the same: $first';
    }

    static function expectWrite(source:String, expected:String):Void {
        final written = Ifid.write(source, IFID);
        if (written != expected) throw 'wrote:\n$written\nexpected:\n$expected';
        // Writing it again changes nothing more
        if (Ifid.write(written, IFID) != expected) throw 'a second write changed the file:\n' + Ifid.write(written, IFID);
    }

    static function testIfidReplace():Void {
        expectWrite(
            'metadata\n  title: Shop\n  ifid: 11111111-2222-4333-8444-555555555555 // the old one\n\nbeat Start\n  Hi.\n',
            'metadata\n  title: Shop\n  ifid: $IFID // the old one\n\nbeat Start\n  Hi.\n'
        );
    }

    static function testIfidAddToBlock():Void {
        expectWrite(
            'metadata\n    title: Shop\n    author: Ana\n\nbeat Start\n  Hi.\n',
            'metadata\n    title: Shop\n    author: Ana\n    ifid: $IFID\n\nbeat Start\n  Hi.\n'
        );
    }

    static function testIfidNewBlock():Void {
        expectWrite(
            'beat Start\n  Hi.\n',
            'metadata\n  ifid: $IFID\n\nbeat Start\n  Hi.\n'
        );
    }

    static function testIfidAfterHeader():Void {
        expectWrite(
            '// The coffee shop, a short story\n// by Ana\n\nimport characters\n\nbeat Start\n  Hi.\n',
            '// The coffee shop, a short story\n// by Ana\n\nmetadata\n  ifid: $IFID\n\nimport characters\n\nbeat Start\n  Hi.\n'
        );
    }

}
