package loreline.test;

import loreline.Loreline;
import loreline.Node;
import loreline.Script;

using StringTools;

/**
 * Tests of `public beat`: the mark is kept in the tree, in JSON and when
 * printed, and only top-level beats can carry it.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class PublicBeatTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'a public beat is marked in the tree', fn: () -> testMarked()},
            {name: 'a public beat prints back and goes through JSON', fn: () -> testPrintAndJson()},
            {name: 'a nested beat can\'t be public', fn: () -> testNested()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('public beats: ' + test.name);
            }
            catch (e:Any) {
                fail('public beats: ' + test.name, Std.string(e));
            }
        }

    }

    static final SOURCE = 'public beat EnterShop\n  Hello.\n\nbeat Inner\n  Hi.\n';

    static function parse(source:String):Script {
        final script = Loreline.parse(source);
        if (script == null) throw 'Failed to parse: ' + Loreline.lastError() + '\n' + source;
        return script;
    }

    static function beats(script:Script):Map<String, NBeatDecl> {
        final result = new Map<String, NBeatDecl>();
        script.each((node, parent) -> {
            if (node is NBeatDecl) result.set((cast node:NBeatDecl).name, cast node);
        });
        return result;
    }

    static function testMarked():Void {
        final found = beats(parse(SOURCE));
        if (!found.get('EnterShop').isPublic) throw 'EnterShop is not public';
        if (found.get('Inner').isPublic) throw 'Inner is public';
    }

    static function testPrintAndJson():Void {
        final script = parse(SOURCE);
        final printed = Loreline.print(script);
        if (printed.indexOf('public beat EnterShop') == -1) throw 'printed as:\n' + printed;
        if (printed.indexOf('public beat Inner') != -1) throw 'Inner printed as public:\n' + printed;
        final back = Script.fromJson(haxe.Json.parse(haxe.Json.stringify(script.toJson())));
        if (!beats(back).get('EnterShop').isPublic) throw 'the mark was lost through JSON';
        if (haxe.Json.stringify(parse('beat Inner\n  Hi.\n').toJson()).indexOf('isPublic') != -1) {
            throw 'the JSON of a beat that is not public holds the field';
        }
    }

    static function testNested():Void {
        var error:Null<loreline.Error> = null;
        final script = try Loreline.parse('beat Outer\n  public beat Inner\n    Hi.\n  Inner()\n') catch (e:loreline.Error) {
            error = e;
            null;
        }
        if (error == null) error = Loreline.lastError();
        if (script != null || error == null) throw 'expected an error';
        if (error.message.indexOf("A nested beat can't be public") == -1) throw 'got "${error.message}"';
        if (error.pos == null || error.pos.line != 2) throw 'expected the error on line 2, got ${error.pos}';
    }

}
