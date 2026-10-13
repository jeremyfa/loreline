package loreline.test;

import loreline.Loreline;
import loreline.i18n.I18n;

using StringTools;

/**
 * Tests of the texts the tools show in English or in French: templates and
 * their parameters, plurals, and errors, whose message stays in English for
 * games while the tools show them in French.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class I18nTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        loreline.i18n.Fr.register();

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'a template takes its parameters', fn: () -> testParams()},
            {name: 'braces and unknown parameters stay as written', fn: () -> testBraces()},
            {name: 'a context after § is left out of the English', fn: () -> testContext()},
            {name: 'a key given as a parameter is translated', fn: () -> testKey()},
            {name: 'plurals follow each language', fn: () -> testCount()},
            {name: 'a language tag gives its locale', fn: () -> testFromTag()},
            {name: 'a parse error keeps its English message and shows in French', fn: () -> testParseError()},
            {name: 'a runtime error keeps its English message and shows in French', fn: () -> testRuntimeError()},
            {name: 'a value described with its article reads as a sentence in French', fn: () -> testOperandWithArticle()},
            {name: 'an error in function code shows in French', fn: () -> testFunctionCodeError()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('i18n: ' + test.name);
            }
            catch (e:Any) {
                fail('i18n: ' + test.name, Std.string(e));
            }
        }

    }

    static function expect(actual:String, expected:String):Void {
        if (actual != expected) throw 'expected "$expected", got "$actual"';
    }

    static function testParams():Void {
        expect(I18n.t('Unknown variable: {name}', {name: 'gold'}, 'en'), 'Unknown variable: gold');
        expect(I18n.t('Unknown variable: {name}', {name: 'gold'}, 'fr'), 'Variable inconnue : gold');
        expect(I18n.t('Array index out of bounds: {index}', {index: 3.0}, 'en'), 'Array index out of bounds: 3');
    }

    static function testBraces():Void {
        // `{{` and `}}` are braces, and `{ after $` isn't a parameter
        expect(I18n.format("write ${{{before}}}{after}", {before: 'a', after: 'b'}, 'en'), "write ${a}b");
        expect(I18n.t("Expected identifier or { after $", null, 'en'), "Expected identifier or { after $");
        expect(I18n.format('Missing {thing}', null, 'en'), 'Missing {thing}');
    }

    static function testContext():Void {
        expect(I18n.format('number§value', null, 'en'), 'number');
        expect(I18n.format('number§value', null, 'fr'), 'un nombre');
    }

    static function testKey():Void {
        final params = {a: I18n.key('text§value'), b: I18n.key('number§value')};
        expect(I18n.t('Cannot add {a} and {b}', params, 'en'), 'Cannot add text and number');
        expect(I18n.t('Cannot add {a} and {b}', params, 'fr'), 'Impossible d\'additionner un texte et un nombre');
    }

    static function testCount():Void {
        expect(I18n.count(1, '{n} argument', '{n} arguments', null, 'en'), '1 argument');
        expect(I18n.count(0, '{n} argument', '{n} arguments', null, 'en'), '0 arguments');
        expect(I18n.count(2, '{n} argument', '{n} arguments', null, 'en'), '2 arguments');
        expect(I18n.count(0, '{n} argument', '{n} arguments', null, 'fr'), '0 argument');
        expect(I18n.count(1, '{n} argument', '{n} arguments', null, 'fr'), '1 argument');
        expect(I18n.count(2, '{n} argument', '{n} arguments', null, 'fr'), '2 arguments');
    }

    static function testFromTag():Void {
        expect(I18n.fromTag('fr'), 'fr');
        expect(I18n.fromTag('fr-CA'), 'fr');
        expect(I18n.fromTag('FR'), 'fr');
        expect(I18n.fromTag('en-US'), 'en');
        expect(I18n.fromTag('de'), 'en');
        expect(I18n.fromTag(null), 'en');
    }

    static function testParseError():Void {
        var error:Null<loreline.Error> = null;
        try {
            Loreline.parse('beat Start\n  -> \n\nbeat Start(a, a)\n  Hi.\n');
        }
        catch (e:loreline.Error) {
            error = e;
        }
        error ??= Loreline.lastError();
        if (error == null) throw 'expected a parse error';
        if (error.template == null) throw 'the error has no template: ' + error.message;
        expect(I18n.errorText(error, 'en'), error.message);
        if (I18n.errorText(error, 'fr') == error.message) throw 'the French of "${error.message}" is the English';
    }

    static function testRuntimeError():Void {
        final script = Loreline.parse('beat Start\n  x = "abc" - 1\n  Hi.\n');
        var error:Null<loreline.Error> = null;
        try {
            Loreline.play(script, (interp, character, text, tags, advance) -> advance(), (interp, options, select) -> select(0), interp -> {});
        }
        catch (e:loreline.Error) {
            error = e;
        }
        if (error == null) throw 'expected a runtime error';
        expect(error.message, 'Cannot subtract "abc" and number');
        expect(I18n.errorText(error, 'fr'), 'Impossible de soustraire un nombre à "abc"');
    }

    /** A value described with its article reads as a sentence wherever the template puts it */
    static function testOperandWithArticle():Void {
        expect(I18n.errorText(runtimeError('x = 3 - "abc"'), 'fr'), 'Impossible de soustraire "abc" à un nombre');
        expect(I18n.errorText(runtimeError('x = 3 % "abc"'), 'fr'), 'Impossible de calculer un nombre modulo "abc"');
        expect(I18n.errorText(runtimeError('x = -"abc"'), 'fr'), 'Impossible d\'appliquer le signe moins à "abc"');
    }

    static function runtimeError(line:String):loreline.Error {
        final script = Loreline.parse('beat Start\n  ' + line + '\n  Hi.\n');
        try {
            Loreline.play(script, (interp, character, text, tags, advance) -> advance(), (interp, options, select) -> select(0), interp -> {});
        }
        catch (e:loreline.Error) {
            return e;
        }
        throw 'expected a runtime error from ' + line;
    }

    static function testFunctionCodeError():Void {
        final script = Loreline.parse("function broken()\n  return 1 < [1]\n\nbeat Start\n  Value is ${broken()}.\n");
        var error:Null<loreline.Error> = null;
        try {
            Loreline.play(script, (interp, character, text, tags, advance) -> advance(), (interp, options, select) -> select(0), interp -> {});
        }
        catch (e:loreline.Error) {
            error = e;
        }
        if (error == null) throw 'expected an error in function code';
        if (I18n.errorText(error, 'fr') == error.message) throw 'the French of "${error.message}" is the English';
    }

}
