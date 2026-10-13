package loreline.test;

import loreline.Loreline;
import loreline.PluralRules;

/**
 * Tests of the plural rules of each language, and of the language
 * `Loreline.loadLocale` keeps with the translations it loads.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class PluralRulesTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'with no language, only one is singular', fn: () -> testNoLanguage()},
            {name: 'English and its family count one apart', fn: () -> testOneApart()},
            {name: 'French and Brazilian Portuguese count zero and one apart', fn: () -> testZeroAndOne()},
            {name: 'Russian and its family have three forms', fn: () -> testRussian()},
            {name: 'Polish, Czech, Lithuanian, Latvian and Romanian have three forms', fn: () -> testThreeForms()},
            {name: 'Slovenian, Irish and Arabic have four to six forms', fn: () -> testMoreForms()},
            {name: 'languages without plurals have one form', fn: () -> testOneForm()},
            {name: 'a fraction takes the last form, or the first in French below two', fn: () -> testFractions()},
            {name: 'missing forms are replaced by the last one', fn: () -> testFewerForms()},
            {name: 'a language tag is read by its language', fn: () -> testTags()},
            {name: 'loadLocale keeps the language of the translations', fn: () -> testLoadLocale()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('plural rules: ' + test.name);
            }
            catch (e:Any) {
                fail('plural rules: ' + test.name, Std.string(e));
            }
        }

    }

    /** The forms a language picks for each count, among `forms` forms */
    static function expectIndexes(language:Null<String>, forms:Int, counts:Array<Float>, expected:Array<Int>):Void {
        final actual = [for (count in counts) PluralRules.formIndex(language, count, forms)];
        if (actual.join(',') != expected.join(',')) {
            throw '$language: for ${counts.join(', ')}, expected ${expected.join(',')}, got ${actual.join(',')}';
        }
    }

    static function expectCount(language:Null<String>, expected:Int):Void {
        final actual = PluralRules.formCount(language);
        if (actual != expected) throw '$language: expected $expected forms, got $actual';
    }

    static function testNoLanguage():Void {
        expectIndexes(null, 2, [0, 1, 2, -1, 1.5], [1, 0, 1, 1, 1]);
        expectCount(null, 2);
    }

    static function testOneApart():Void {
        for (language in ['en', 'de', 'es', 'it', 'pt-PT']) {
            expectIndexes(language, 2, [0, 1, 2, -1, 21], [1, 0, 1, 0, 1]);
            expectCount(language, 2);
        }
    }

    static function testZeroAndOne():Void {
        for (language in ['fr', 'pt', 'pt-BR']) {
            expectIndexes(language, 2, [0, 1, 2, -1], [0, 0, 1, 0]);
            expectCount(language, 2);
        }
    }

    static function testRussian():Void {
        for (language in ['ru', 'uk', 'sr']) {
            expectIndexes(language, 3, [1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 111], [0, 1, 1, 2, 2, 2, 2, 0, 1, 2, 2]);
            expectCount(language, 3);
        }
    }

    static function testThreeForms():Void {
        expectIndexes('pl', 3, [1, 2, 5, 12, 21, 22, 25], [0, 1, 2, 2, 2, 1, 2]);
        expectIndexes('cs', 3, [1, 2, 4, 5, 22], [0, 1, 1, 2, 2]);
        expectIndexes('lt', 3, [1, 2, 10, 11, 21, 22], [0, 1, 2, 2, 0, 1]);
        expectIndexes('lv', 3, [0, 1, 2, 11, 21], [2, 0, 1, 1, 0]);
        expectIndexes('ro', 3, [0, 1, 2, 19, 20, 101], [1, 0, 1, 1, 2, 1]);
        for (language in ['pl', 'cs', 'sk', 'lt', 'lv', 'ro']) expectCount(language, 3);
    }

    static function testMoreForms():Void {
        expectIndexes('sl', 4, [1, 2, 3, 5, 101, 102], [0, 1, 2, 3, 0, 1]);
        expectCount('sl', 4);
        expectIndexes('ga', 5, [1, 2, 3, 7, 11], [0, 1, 2, 3, 4]);
        expectCount('ga', 5);
        expectIndexes('ar', 6, [0, 1, 2, 3, 10, 11, 99, 100, 102, 103], [0, 1, 2, 3, 3, 4, 4, 5, 5, 3]);
        expectCount('ar', 6);
    }

    static function testOneForm():Void {
        for (language in ['ja', 'zh', 'ko', 'vi', 'th']) {
            expectIndexes(language, 2, [0, 1, 2], [0, 0, 0]);
            expectCount(language, 1);
        }
    }

    static function testFractions():Void {
        expectIndexes('en', 2, [1.5, 0.5], [1, 1]);
        expectIndexes('fr', 2, [0.5, 1.5, 2.5], [0, 0, 1]);
        expectIndexes('pl', 3, [1.5], [2]);
    }

    static function testFewerForms():Void {
        expectIndexes('pl', 2, [1, 2, 5], [0, 1, 1]);
        expectIndexes('ar', 3, [0, 1, 2, 100], [0, 1, 2, 2]);
    }

    static function testTags():Void {
        expectIndexes('fr-CA', 2, [0], [0]);
        expectIndexes('FR', 2, [0], [0]);
        expectIndexes('pt_PT', 2, [0], [1]);
        expectIndexes('PT-pt', 2, [0], [1]);
        expectIndexes('PL', 3, [22], [1]);
        expectIndexes('zh-Hant-TW', 2, [2], [0]);
        expectIndexes('xx', 2, [0, 1], [1, 0]);
        expectCount('xx', 2);
    }

    static function testLoadLocale():Void {
        final files = [
            'story.lor' => 'beat Start\n  Hello. #hello\n',
            'story.fr.lor' => '#hello // Hello.\nBonjour.\n'
        ];
        final handleFile = (path:String, callback:(content:String)->Void) -> callback(files.get(path));
        final script = Loreline.parse(files.get('story.lor'), 'story.lor', handleFile);
        final translations = Loreline.loadLocale('fr', script, 'story.lor', handleFile);
        final locale = translations.get("$locale");
        if (locale == null) throw 'no $$locale in the translations';
        final text = switch locale.parts[0].partType {
            case Raw(text): text;
            case _: null;
        }
        if (text != 'fr') throw 'expected "fr", got "$text"';
        if (!translations.exists('.#hello')) throw 'the translation of #hello is missing';
    }

}
