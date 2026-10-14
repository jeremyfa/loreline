package loreline;

/**
 * Which plural form a count takes in each language, after the plural forms of
 * gettext: the forms are written in the order of the table below, and the
 * rules apply to the count without its sign.
 *
 * With no language, only the number one takes the first form: the rule plural
 * texts have always followed.
 */
class PluralRules {

    /**
     * The index of the form to show for a count, among the `forms` forms given.
     * When the language would pick a form past the last one given, the last one
     * is shown.
     * @param language A language tag, like `fr`, `pt-BR` or `zh-Hant`, or null
     * @param count The count the forms are about
     * @param forms How many forms are given, at least one
     */
    public static function formIndex(language:Null<String>, count:Float, forms:Int):Int {

        final index = if (language == null) {
            count == 1 ? 0 : 1;
        }
        else {
            ruleIndex(familyOf(language), Math.abs(count));
        }
        return index < forms ? index : forms - 1;

    }

    /** How many forms a language uses, two with no language or an unknown one */
    public static function formCount(language:Null<String>):Int {
        return formsOf(familyOf(language));
    }

    static function formsOf(family:PluralFamily):Int {

        return switch family {
            case NoPlural: 1;
            case OneApart | ZeroAndOne: 2;
            case Russian | Polish | Czech | Lithuanian | Latvian | Romanian: 3;
            case Slovenian: 4;
            case Irish: 5;
            case Arabic: 6;
        }

    }

    static function ruleIndex(family:PluralFamily, n:Float):Int {

        // A fraction takes the last form, except where zero and one go together
        if (n != Math.ffloor(n)) {
            return switch family {
                case ZeroAndOne: n < 2 ? 0 : 1;
                case _: formsOf(family) - 1;
            }
        }

        final mod10 = n % 10;
        final mod100 = n % 100;
        return switch family {
            case NoPlural: 0;
            case OneApart: n == 1 ? 0 : 1;
            case ZeroAndOne: n < 2 ? 0 : 1;
            case Russian:
                mod10 == 1 && mod100 != 11 ? 0
                : mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20) ? 1
                : 2;
            case Polish:
                n == 1 ? 0
                : mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20) ? 1
                : 2;
            case Czech: n == 1 ? 0 : n >= 2 && n <= 4 ? 1 : 2;
            case Lithuanian:
                mod10 == 1 && mod100 != 11 ? 0
                : mod10 >= 2 && (mod100 < 10 || mod100 >= 20) ? 1
                : 2;
            case Latvian: mod10 == 1 && mod100 != 11 ? 0 : n != 0 ? 1 : 2;
            case Romanian: n == 1 ? 0 : n == 0 || (mod100 > 0 && mod100 < 20) ? 1 : 2;
            case Slovenian: mod100 == 1 ? 0 : mod100 == 2 ? 1 : mod100 == 3 || mod100 == 4 ? 2 : 3;
            case Irish: n == 1 ? 0 : n == 2 ? 1 : n < 7 ? 2 : n < 11 ? 3 : 4;
            case Arabic:
                n == 0 ? 0 : n == 1 ? 1 : n == 2 ? 2
                : mod100 >= 3 && mod100 <= 10 ? 3
                : mod100 >= 11 ? 4
                : 5;
        }

    }

    /** The rule of a language tag, English for an unknown or null one */
    static function familyOf(language:Null<String>):PluralFamily {

        if (language == null) return OneApart;
        final tag = StringTools.replace(language.toLowerCase(), '_', '-');
        final dash = tag.indexOf('-');
        final primary = dash == -1 ? tag : tag.substr(0, dash);
        // Portugal counts zero apart, Brazil, the default, with one
        if (primary == 'pt') return StringTools.startsWith(tag, 'pt-pt') ? OneApart : ZeroAndOne;

        return switch primary {
            case 'ja' | 'zh' | 'ko' | 'vi' | 'th' | 'id' | 'ms' | 'lo' | 'km' | 'my': NoPlural;
            case 'fr' | 'hy': ZeroAndOne;
            case 'ru' | 'uk' | 'be' | 'sr' | 'hr' | 'bs': Russian;
            case 'pl': Polish;
            case 'cs' | 'sk': Czech;
            case 'lt': Lithuanian;
            case 'lv': Latvian;
            case 'ro': Romanian;
            case 'sl': Slovenian;
            case 'ga': Irish;
            case 'ar': Arabic;
            case _: OneApart;
        }

    }

}

/** The languages that share a plural rule (numbers, which every target handles alike) */
private enum abstract PluralFamily(Int) {
    var NoPlural = 0;
    var OneApart = 1;
    var ZeroAndOne = 2;
    var Russian = 3;
    var Polish = 4;
    var Czech = 5;
    var Lithuanian = 6;
    var Latvian = 7;
    var Romanian = 8;
    var Slovenian = 9;
    var Irish = 10;
    var Arabic = 11;
}
