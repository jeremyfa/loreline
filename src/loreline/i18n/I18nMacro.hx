package loreline.i18n;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

/**
 * The macros behind `I18n.t`, `I18n.count`, `I18n.text` and `I18n.key`, and the
 * check of the tables: each template a build uses is recorded, and a build
 * with a table of a locale fails when a template has no translation in it.
 *
 * A table is a class with a `TABLE` map literal and
 * `@:build(loreline.i18n.I18nMacro.table('fr', 'core'))`. With
 * `-D loreline_i18n_strict=core,lsp`, the tables named there must also have
 * no entry that no template uses.
 */
class I18nMacro {

    /** The templates the build uses, each with where it is first written */
    static final templates:Map<String, Position> = new Map();

    /** The tables the build has */
    static final tables:Array<{locale:String, name:String, entries:Map<String, String>, pos:Position}> = [];

    static var checking = false;

    public static function t(template:Expr, params:Expr, locale:Expr):Expr {
        final text = record(template);
        return macro loreline.i18n.I18n.format($v{text}, $params, $locale);
    }

    public static function count(n:Expr, one:Expr, many:Expr, params:Expr, locale:Expr):Expr {
        final oneText = record(one);
        final manyText = record(many);
        return macro loreline.i18n.I18n.formatCount($n, $v{oneText}, $v{manyText}, $params, $locale);
    }

    public static function text(template:Expr, params:Expr):Expr {
        final text = record(template);
        return macro new loreline.i18n.I18nText($v{text}, $params);
    }

    public static function key(word:Expr):Expr {
        final text = record(word);
        return macro new loreline.i18n.I18nKey($v{text});
    }

    /** Records a template written as a literal, and gives its text */
    static function record(template:Expr):String {
        final text = switch template.expr {
            case EConst(CString(s, kind)):
                // In single quotes, a `$` would make Haxe read the template as code
                if (kind == SingleQuotes && s.indexOf('$') != -1) {
                    Context.error('A template holding $ is written in double quotes', template.pos);
                }
                s;
            case _:
                Context.error('The template of a text must be a literal', template.pos);
        }
        if (!templates.exists(text)) templates.set(text, template.pos);
        startChecking();
        return text;
    }

    /**
     * Reads a table: the entries of its `TABLE` map literal, whose parameters
     * must be the same in both languages.
     */
    public static function table(locale:String, name:String):Array<Field> {
        final fields = Context.getBuildFields();
        final entries = new Map<String, String>();
        for (field in fields) {
            if (field.name != 'TABLE') continue;
            final value = switch field.kind {
                case FVar(_, e) | FProp(_, _, _, e): e;
                case _: null;
            }
            if (value == null) continue;
            switch value.expr {
                case EArrayDecl(values):
                    for (entry in values) {
                        switch entry.expr {
                            case EBinop(OpArrow, {expr: EConst(CString(key, _))}, {expr: EConst(CString(translated, _)), pos: translatedPos}):
                                if (entries.exists(key)) Context.error('"$key" is translated twice', entry.pos);
                                if (params(key).join(',') != params(translated).join(',')) {
                                    Context.error('The parameters of "$translated" differ from those of "$key"', translatedPos);
                                }
                                entries.set(key, translated);
                            case _:
                                Context.error('A table entry is \'English\' => \'translation\'', entry.pos);
                        }
                    }
                case _:
                    Context.error('TABLE is a map literal', value.pos);
            }
        }
        tables.push({locale: locale, name: name, entries: entries, pos: Context.currentPos()});
        startChecking();
        return fields;
    }

    /** The names of the parameters of a template, sorted */
    static function params(template:String):Array<String> {
        final names:Array<String> = [];
        final pattern = ~/\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
        var rest = template.replace('{{', '').replace('}}', '');
        while (pattern.match(rest)) {
            final name = pattern.matched(1);
            if (!names.contains(name)) names.push(name);
            rest = pattern.matchedRight();
        }
        names.sort(Reflect.compare);
        return names;
    }

    static function startChecking():Void {
        if (checking) return;
        checking = true;
        Context.onGenerate(_ -> check());
    }

    /** Fails the build when a template has no translation, or a strict table has an unused entry */
    static function check():Void {
        for (locale in [for (table in tables) table.locale]) {
            final translated = new Map<String, Bool>();
            for (table in tables) {
                if (table.locale != locale) continue;
                for (key in table.entries.keys()) translated.set(key, true);
            }
            final missing = [for (template => pos in templates) if (!translated.exists(template)) template];
            if (missing.length > 0) {
                missing.sort(Reflect.compare);
                Context.fatalError('Templates without a translation in "$locale":\n' + missing.join('\n'), templates.get(missing[0]));
            }
        }
        final strict = Context.definedValue('loreline_i18n_strict');
        if (strict != null && strict != '1') {
            final names = [for (name in strict.split(',')) name.trim()];
            for (table in tables) {
                if (!names.contains(table.name)) continue;
                final unused = [for (key in table.entries.keys()) if (!templates.exists(key)) key];
                if (unused.length > 0) {
                    unused.sort(Reflect.compare);
                    Context.fatalError('Entries of the "${table.name}" table that no template uses:\n' + unused.join('\n'), table.pos);
                }
            }
        }
    }

}
#end
