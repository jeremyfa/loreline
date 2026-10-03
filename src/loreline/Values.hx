package loreline;

import Type.ValueType;
import loreline.Interpreter;

/**
 * The value rules of the language: equality, ordering and truthiness. Scripts,
 * function code and built-in functions all go through them, so they give the
 * same result on every target. A raw dynamic `==` between values of different
 * kinds can't be used for that: each target compiles it its own way (loose
 * coercion on JS, booleans as numbers on C++, C# and Python, strict elsewhere).
 */
class Values {

    /**
     * Equality, for `==`, `is` and the built-in functions that look for a value:
     * - two numbers compare by value, integers and decimals alike (`5 == 5.0`)
     * - two texts compare as written (`"5" == "5.0"` is false)
     * - a number and a text are equal when the text is written as that number
     *   (`5 == "5"`, `5 == " 5.0 "`), see numberOfText (`0 == ""` is false)
     * - `true` and `false` equal 1 and 0, and their texts "true" and "false"
     * - null equals only null
     * - a beat or a character reference equals a text holding its name, two
     *   beat references are equal when they name the same beat, a character
     *   reference equals its own fields
     * - arrays and objects are equal only to themselves
     */
    public static function equals(a:Any, b:Any):Bool {

        if (a == null || b == null) return a == null && b == null;

        if (a is String) {
            return (b is String) ? (a : String) == (b : String) : textEquals(a, b);
        }
        if (b is String) {
            return textEquals(b, a);
        }

        final typeA = Type.typeof(a);
        final typeB = Type.typeof(b);
        switch [typeA, typeB] {
            case [TInt | TFloat, TInt | TFloat]:
                return numberOf(a, typeA) == numberOf(b, typeB);
            case [TBool, TBool]:
                return (a : Bool) == (b : Bool);
            case [TBool, TInt | TFloat]:
                return ((a : Bool) ? 1.0 : 0.0) == numberOf(b, typeB);
            case [TInt | TFloat, TBool]:
                return numberOf(a, typeA) == ((b : Bool) ? 1.0 : 0.0);
            case [TInt | TFloat | TBool, _] | [_, TInt | TFloat | TBool]:
                return false;
            case _:
        }

        final beatA = RuntimeBeatRef.beatOf(a);
        final beatB = RuntimeBeatRef.beatOf(b);
        if (beatA != null || beatB != null) {
            return beatA != null && beatB != null && beatA.name == beatB.name;
        }

        if (RuntimeCharacterRef.characterOf(a) != null || RuntimeCharacterRef.characterOf(b) != null) {
            return same(RuntimeCharacterRef.fieldsOf(a), RuntimeCharacterRef.fieldsOf(b));
        }

        return same(a, b);

    }

    /**
     * Equality of a text with a value that is not a text (nor null).
     */
    static function textEquals(text:String, other:Any):Bool {

        switch Type.typeof(other) {
            case TBool:
                return text == ((other : Bool) ? 'true' : 'false');
            case TInt | TFloat:
                // NaN when the text is not a number: equal to nothing
                return numberOfText(text) == numberOf(other, Type.typeof(other));
            case _:
        }

        final beat = RuntimeBeatRef.beatOf(other);
        if (beat != null) return beat.name == text;

        final character = RuntimeCharacterRef.characterOf(other);
        if (character != null) return character.name == text;

        return false;

    }

    /**
     * Whether two arrays, objects or references are the same one.
     */
    static inline function same(a:Any, b:Any):Bool {
        #if python
        // Python's == compares lists and dicts by content
        return python.Syntax.code('({0} is {1})', a, b);
        #else
        return a == b;
        #end
    }

    /**
     * The number a value is ordered as: a number, or a text written as a
     * number. NaN for any other value.
     */
    static function orderNumberOf(value:Any):Float {
        if (value == null) return Math.NaN;
        if (value is String) return numberOfText(value);
        final type = Type.typeof(value);
        return switch type {
            case TInt | TFloat: numberOf(value, type);
            case _: Math.NaN;
        }
    }

    /**
     * Whether two values can be ordered: two numbers, or a number and a text
     * written as a number. Two texts can't, even written as numbers.
     */
    public static function canCompare(a:Any, b:Any):Bool {
        if (a is String) return !(b is String) && isNumber(b) && !Math.isNaN(numberOfText(a));
        if (b is String) return isNumber(a) && !Math.isNaN(numberOfText(b));
        return isNumber(a) && isNumber(b);
    }

    static inline function isNumber(value:Any):Bool {
        return value != null && switch Type.typeof(value) {
            case TInt | TFloat: true;
            case _: false;
        }
    }

    /**
     * Ordering, for `<`, `>`, `<=` and `>=`: -1, 0 or 1. The values must be
     * ones that canCompare accepts, which the caller checks to report the error.
     * A number that is NaN compares as neither smaller nor greater.
     */
    public static function compare(a:Any, b:Any):Int {
        final numberA = orderNumberOf(a);
        final numberB = orderNumberOf(b);
        return numberA < numberB ? -1 : (numberA > numberB ? 1 : 0);
    }

    /**
     * Truthiness, wherever a value decides: false for false, null, 0, "" and an
     * empty array, true for anything else.
     */
    public static function isTruthy(value:Any):Bool {
        // Booleans first: most conditions give one
        if (value is Bool) return (value : Bool);
        if (value == null) return false;
        if (value is String) return (value : String).length > 0;
        if (Arrays.isArray(value)) return Arrays.arrayLength(value) > 0;
        final type = Type.typeof(value);
        return switch type {
            case TInt | TFloat: numberOf(value, type) != 0;
            case _: true;
        }
    }

    /**
     * The number a text is written as, or NaN when it is not written as a
     * number. Allowed: spaces, tabs and line breaks around, a sign, digits with
     * an optional decimal part (`5`, `5.`, `.5`), an optional exponent (`1e3`).
     * Not numbers: "", " ", "0x10", "Infinity", "1_000", "5abc".
     * The text is checked by hand and rewritten in a single form before being
     * parsed, as Std.parseFloat accepts other forms on some targets.
     */
    public static function numberOfText(text:String):Float {

        final length = text.length;
        var start = 0;
        var end = length;
        while (start < end && isSpace(StringTools.fastCodeAt(text, start))) start++;
        while (end > start && isSpace(StringTools.fastCodeAt(text, end - 1))) end--;
        if (start == end) return Math.NaN;

        var i = start;
        var negative = false;
        var c = StringTools.fastCodeAt(text, i);
        if (c == '+'.code || c == '-'.code) {
            negative = c == '-'.code;
            i++;
        }

        final intStart = i;
        while (i < end && isDigit(StringTools.fastCodeAt(text, i))) i++;
        final intEnd = i;

        var fracStart = i;
        var fracEnd = i;
        if (i < end && StringTools.fastCodeAt(text, i) == '.'.code) {
            i++;
            fracStart = i;
            while (i < end && isDigit(StringTools.fastCodeAt(text, i))) i++;
            fracEnd = i;
        }

        // At least one digit before or after the point
        if (intEnd == intStart && fracEnd == fracStart) return Math.NaN;

        var exponent = '';
        if (i < end) {
            c = StringTools.fastCodeAt(text, i);
            if (c != 'e'.code && c != 'E'.code) return Math.NaN;
            i++;
            var exponentNegative = false;
            if (i < end) {
                c = StringTools.fastCodeAt(text, i);
                if (c == '+'.code || c == '-'.code) {
                    exponentNegative = c == '-'.code;
                    i++;
                }
            }
            final exponentStart = i;
            while (i < end && isDigit(StringTools.fastCodeAt(text, i))) i++;
            if (i == exponentStart || i < end) return Math.NaN;
            exponent = 'e' + (exponentNegative ? '-' : '') + text.substring(exponentStart, i);
        }

        final normalized = (negative ? '-' : '')
            + (intEnd > intStart ? text.substring(intStart, intEnd) : '0')
            + (fracEnd > fracStart ? '.' + text.substring(fracStart, fracEnd) : '')
            + exponent;
        return Std.parseFloat(normalized);

    }

    static inline function isSpace(c:Int):Bool {
        return c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code;
    }

    static inline function isDigit(c:Int):Bool {
        return c >= '0'.code && c <= '9'.code;
    }

    /**
     * The number held by a value already known to be an Int or a Float.
     */
    public static inline function numberOf(value:Dynamic, type:ValueType):Float {
        return switch type {
            case TInt: (value : Int);
            case _: (value : Float);
        }
    }

    /**
     * The kind of a value as the word `type_of` gives: "number", "text",
     * "bool", "array", "object", "beat", "character", "function" or "null".
     * Integers and decimals are both "number": the difference depends on the
     * target, not on the script.
     */
    public static function typeOf(value:Any):String {
        if (value == null) return 'null';
        if (value is String) return 'text';
        if (Arrays.isArray(value)) return 'array';
        if (RuntimeBeatRef.beatOf(value) != null) return 'beat';
        if (RuntimeCharacterRef.characterOf(value) != null) return 'character';
        return switch Type.typeof(value) {
            case TBool: 'bool';
            case TInt | TFloat: 'number';
            case TFunction: 'function';
            case _: 'object';
        }
    }

    /**
     * A short name for the kind of a value, for error messages.
     */
    public static function kindOf(value:Any):String {
        if (value == null) return 'Null';
        if (value is String) return 'String';
        if (Arrays.isArray(value)) return 'Array';
        if (RuntimeBeatRef.beatOf(value) != null) return 'Beat';
        if (RuntimeCharacterRef.characterOf(value) != null) return 'Character';
        return switch Type.typeof(value) {
            case TInt: 'Int';
            case TFloat: 'Float';
            case TBool: 'Bool';
            case _: 'Object';
        }
    }

}
