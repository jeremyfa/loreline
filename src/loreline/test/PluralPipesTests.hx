package loreline.test;

import loreline.PluralPipes;

/**
 * Tests of the plural pipes found in a text: their forms, where they start and
 * end, and the characters that mark them, which editors color.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class PluralPipesTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'two words around a pipe', fn: () -> testTwoWords()},
            {name: 'more forms, each after a pipe', fn: () -> testMoreForms()},
            {name: 'forms between parentheses may hold spaces', fn: () -> testParentheses()},
            {name: 'punctuation and quotes around stay out of the forms', fn: () -> testPunctuation()},
            {name: 'an escaped pipe or an empty form is no plural', fn: () -> testNotPlurals()},
            {name: 'several plurals in one text', fn: () -> testSeveral()},
            {name: 'positions count accented letters once', fn: () -> testAccents()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('plural pipes: ' + test.name);
            }
            catch (e:Any) {
                fail('plural pipes: ' + test.name, Std.string(e));
            }
        }

    }

    /** The pipes of a text, written as `start-end forms marks` */
    static function expect(text:String, expected:Array<String>):Void {
        final actual = [for (pipe in PluralPipes.scan(text)) pipe.start + '-' + pipe.end + ' ' + pipe.forms.join('/') + ' ' + pipe.marks.join(',')];
        if (actual.join(' ; ') != expected.join(' ; ')) {
            throw 'in "$text", expected [${expected.join(' ; ')}], got [${actual.join(' ; ')}]';
        }
    }

    static function testTwoWords():Void {
        expect(' coin|coins', ['1-11 coin/coins 5']);
        expect(' coin|coins left', ['1-11 coin/coins 5']);
    }

    static function testMoreForms():Void {
        expect(' plik|pliki|plików', ['1-18 plik/pliki/plików 5,11']);
    }

    static function testParentheses():Void {
        expect(' (cold drink|cold drinks) left', ['1-25 cold drink/cold drinks 1,12,24']);
        expect(' (a|b|c)', ['1-8 a/b/c 1,3,5,7']);
    }

    static function testPunctuation():Void {
        expect(' coin|coins.', ['1-11 coin/coins 5']);
        expect(' coin|coins?!', ['1-11 coin/coins 5']);
        expect(' «coin|coins»', ['2-12 coin/coins 6']);
        expect(' "coin|coins", then', ['2-12 coin/coins 6']);
        expect(" dog's|dogs'", ["1-12 dog's/dogs' 6"]);
    }

    static function testNotPlurals():Void {
        expect(' a literal \\| pipe', []);
        expect(' a||b', []);
        expect(' a| b', []);
        expect(' (|b)', []);
    }

    static function testSeveral():Void {
        expect(' cat|cats and dog|dogs', ['1-9 cat/cats 4', '14-22 dog/dogs 17']);
    }

    static function testAccents():Void {
        expect(' été|étés left', ['1-9 été/étés 4']);
    }

}
