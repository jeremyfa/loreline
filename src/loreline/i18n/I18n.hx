package loreline.i18n;

#if macro
import haxe.macro.Expr;
#end

/**
 * The texts the Loreline tools show, in English or in French: hovers, checks,
 * errors as an editor shows them. Games never see French: the runtime keeps
 * its English messages, and only the tools load a table and pick a locale.
 *
 * A text is written as its English template, which is also its key in the
 * tables: `I18n.t('Unknown name: {name}', {name: name})`. `{name}` is a
 * parameter, `{{` and `}}` are braces. When the same English needs two French
 * forms, the key carries a context after `§`, like `'Metadata§key'`, which the
 * English text leaves out.
 *
 * `t`, `text`, `count` and `key` are macros: they record each template, and a
 * build with a table of the locale fails when a template has no translation.
 */
@:expose
class I18n {

    /** The locale of the tools: `en` or `fr`. Games never change it. */
    public static var locale:String = 'en';

    /** The tables registered for each locale other than English */
    static final tables:Map<String, Map<String, String>> = new Map();

    /**
     * The locale for a language tag: `fr`, `fr-CA` or `FR` give `fr`, and
     * anything else, or nothing, gives `en`.
     */
    public static function fromTag(tag:Null<String>):String {
        if (tag == null) return 'en';
        final lower = tag.toLowerCase();
        return (lower == 'fr' || lower.indexOf('fr-') == 0 || lower.indexOf('fr_') == 0) ? 'fr' : 'en';
    }

    /** Adds the translations of a table, read by `format` for that locale */
    public static function register(locale:String, table:Map<String, String>):Void {
        var all = tables.get(locale);
        if (all == null) {
            all = new Map();
            tables.set(locale, all);
        }
        for (key => value in table) all.set(key, value);
    }

    /**
     * Adds the translations of a table given as a plain object, `{english: translated}`,
     * like `js/loreline-fr.js` on JavaScript.
     */
    public static function registerObject(locale:String, table:Dynamic):Void {
        final map = new Map<String, String>();
        for (key in Reflect.fields(table)) map.set(key, Reflect.field(table, key));
        register(locale, map);
    }

    /** A word looked up in the table when it's given as a parameter, from a name known only when running */
    public static function keyOf(word:String):I18nKey {
        return new I18nKey(word);
    }

    /**
     * A template in a locale, its parameters filled. A template with no
     * translation gives its English.
     * @param template The English template, which is also its key
     * @param params The values of its parameters, by name
     * @param locale The locale, or the current one
     */
    public static function format(template:String, ?params:Dynamic, ?locale:String):String {
        final loc = locale ?? I18n.locale;
        return fill(translate(template, loc), params, loc);
    }

    /**
     * The singular or the plural of a template, by a number given to it as
     * `{n}`, with the plural rules of stories (see loreline.PluralRules): in
     * English the singular is for 1 only, in French for 0 and 1.
     */
    public static function formatCount(n:Float, one:String, many:String, ?params:Dynamic, ?locale:String):String {
        final loc = locale ?? I18n.locale;
        final singular = loreline.PluralRules.formIndex(loc, n, 2) == 0;
        final all:Dynamic = {};
        if (params != null) {
            for (field in Reflect.fields(params)) Reflect.setField(all, field, Reflect.field(params, field));
        }
        Reflect.setField(all, 'n', n);
        return format(singular ? one : many, all, loc);
    }

    /**
     * The message of an error in a locale: from its template and parameters
     * when it has them, its English message otherwise.
     */
    public static function errorText(error:Null<loreline.Error>, ?locale:String):Null<String> {
        if (error == null) return null;
        return error.template != null ? format(error.template, error.params, locale) : error.message;
    }

    /** The text of a template in a locale, before its parameters are filled */
    static function translate(template:String, loc:String):String {
        if (loc != 'en') {
            final table = tables.get(loc);
            if (table != null) {
                final translated = table.get(template);
                if (translated != null) return translated;
            }
        }
        final context = template.lastIndexOf('§');
        return context != -1 ? template.substr(0, context) : template;
    }

    /** A text with its `{name}` parameters filled, and its `{{` and `}}` turned into braces */
    static function fill(text:String, params:Dynamic, loc:String):String {
        if (text.indexOf('{') == -1 && text.indexOf('}') == -1) return text;
        final buf = new StringBuf();
        var i = 0;
        final length = text.length;
        while (i < length) {
            final open = text.indexOf('{', i);
            final close = text.indexOf('}', i);
            if (open == -1 && close == -1) {
                buf.add(text.substr(i));
                break;
            }
            if (close != -1 && (open == -1 || close < open)) {
                // A lone `}`, or `}}` for one
                buf.add(text.substring(i, close + 1));
                i = close + (text.substr(close, 2) == '}}' ? 2 : 1);
                continue;
            }
            buf.add(text.substring(i, open));
            if (text.substr(open, 2) == '{{') {
                buf.add('{');
                i = open + 2;
                continue;
            }
            final end = text.indexOf('}', open);
            final name = end != -1 ? text.substring(open + 1, end) : null;
            if (name == null || !isParamName(name)) {
                buf.add('{');
                i = open + 1;
                continue;
            }
            buf.add(paramText(params, name, loc));
            i = end + 1;
        }
        return buf.toString();
    }

    /** Whether a text between braces names a parameter: letters, digits and `_` */
    static function isParamName(name:String):Bool {
        if (name.length == 0) return false;
        for (i in 0...name.length) {
            final c = name.charCodeAt(i);
            final letter = (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || c == '_'.code;
            if (!letter && !(i > 0 && c >= '0'.code && c <= '9'.code)) return false;
        }
        return true;
    }

    /**
     * A parameter as text: a key, a text or an error in the locale, a number
     * without a useless `.0`, or the value as is.
     */
    static function paramText(params:Dynamic, name:String, loc:String):String {
        if (params == null || !Reflect.hasField(params, name)) return '{' + name + '}';
        final value:Dynamic = Reflect.field(params, name);
        if (value == null) return 'null';
        if (value is I18nKey) return translate((value:I18nKey).word, loc);
        if (value is I18nText) return (value:I18nText).format(loc);
        if (value is loreline.Error) return errorText(value, loc);
        if (value is loreline.lorscript.Expr.Error) return loreline.lorscript.Printer.errorToString(value, loc);
        if (value is Float && !(value is Int)) {
            final number:Float = value;
            if (number == Math.ffloor(number) && Math.abs(number) < 2147483647) return Std.string(Std.int(number));
        }
        return Std.string(value);
    }

    /** A template in the current locale (or the one given), its parameters filled */
    public static macro function t(template:ExprOf<String>, ?params:Expr, ?locale:Expr):Expr {
        return loreline.i18n.I18nMacro.t(template, params, locale);
    }

    /** The singular or the plural of a template, the number given to it as `{n}` */
    public static macro function count(n:Expr, one:ExprOf<String>, many:ExprOf<String>, ?params:Expr, ?locale:Expr):Expr {
        return loreline.i18n.I18nMacro.count(n, one, many, params, locale);
    }

    /** A template with its parameters, kept to be shown later in any locale: for errors */
    public static macro function text(template:ExprOf<String>, ?params:Expr):Expr {
        return loreline.i18n.I18nMacro.text(template, params);
    }

    /** A word looked up in the table when it's given as a parameter */
    public static macro function key(word:ExprOf<String>):Expr {
        return loreline.i18n.I18nMacro.key(word);
    }

}
