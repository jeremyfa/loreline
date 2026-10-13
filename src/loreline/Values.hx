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
     * A number as text, the same on every target: up to 15 significant digits,
     * so that `0.1 + 0.2` reads `0.3`, without trailing zeros (`5.0` reads `5`),
     * and without exponent between 0.000001 and 10^21. Outside of that range,
     * the exponent form of JavaScript (`1e+21`, `1e-7`). `NaN`, `Infinity` and
     * `-Infinity` for the special values, `0` for -0.
     * The digits are computed with the basic operations of IEEE 754 doubles,
     * which give the same results on every target, instead of the conversion
     * of each target, which differ (`0.30000000000000004`, `1e+15`, `1.0E15`).
     */
    public static function numberText(n:Float):String {
        return formatNumber(n, 15, false);
    }

    /**
     * A number as a literal of the script, for the printer: in plain decimal
     * notation, which the lexer reads, with the fewest significant digits (15
     * to 17) that read back as the same number.
     */
    public static function numberLiteral(n:Float):String {
        if (Math.isNaN(n) || !Math.isFinite(n)) return numberText(n);
        for (digits in 15...17) {
            final text = formatNumber(n, digits, true);
            if (numberOfText(text) == n) return text;
        }
        return formatNumber(n, 17, true);
    }

    /**
     * A number written with up to `significant` digits, without trailing
     * zeros. With `plain`, never with an exponent.
     */
    static function formatNumber(n:Float, significant:Int, plain:Bool):String {

        if (Math.isNaN(n)) return 'NaN';
        if (!Math.isFinite(n)) return n > 0 ? 'Infinity' : '-Infinity';
        if (n == 0) return '0';

        final negative = n < 0;
        final a = negative ? -n : n;

        // Whole numbers that hold in 15 digits: their digits as they are
        if (a < 1e15 && Math.ffloor(a) == a) {
            final text = wholeDigits(a);
            return negative ? '-' + text : text;
        }

        // The exponent, estimated with a logarithm (which may differ by one
        // unit between targets), then settled with exact comparisons
        final low = POWERS_OF_TEN[significant - 1];
        final high = POWERS_OF_TEN[significant];
        var e = Math.floor(Math.log(a) / Math.log(10));
        var scaled = scaleByPowerOfTen(a, significant - 1 - e);
        if (scaled >= high) {
            e++;
            scaled = scaleByPowerOfTen(a, significant - 1 - e);
        }
        else if (scaled < low) {
            e--;
            scaled = scaleByPowerOfTen(a, significant - 1 - e);
        }
        var m = Math.ffloor(scaled + 0.5);
        if (m >= high) {
            m = low;
            e++;
        }

        // The digits, without the zeros at the end
        var digits = wholeDigits(m);
        var end = digits.length;
        while (end > 1 && StringTools.fastCodeAt(digits, end - 1) == '0'.code) end--;
        digits = digits.substr(0, end);

        final text = if (!plain && (e >= 21 || e < -6)) {
            digits.charAt(0) + (digits.length > 1 ? '.' + digits.substr(1) : '') + 'e' + (e > 0 ? '+' : '-') + wholeDigits(Math.abs(e));
        }
        else if (e >= 0) {
            digits.length <= e + 1 ? digits + zeros(e + 1 - digits.length) : digits.substr(0, e + 1) + '.' + digits.substr(e + 1);
        }
        else {
            '0.' + zeros(-e - 1) + digits;
        }
        return negative ? '-' + text : text;

    }

    /** The digits of a whole number, written by hand. */
    static function wholeDigits(n:Float):String {
        if (n == 0) return '0';
        final buf = new StringBuf();
        final codes:Array<Int> = [];
        var rest = n;
        while (rest > 0) {
            final digit = rest % 10;
            codes.push('0'.code + Std.int(digit));
            rest = (rest - digit) / 10;
        }
        var i = codes.length - 1;
        while (i >= 0) {
            buf.addChar(codes[i]);
            i--;
        }
        return buf.toString();
    }

    static function zeros(count:Int):String {
        final buf = new StringBuf();
        for (_ in 0...count) buf.addChar('0'.code);
        return buf.toString();
    }

    /** The exact powers of ten that a double holds. */
    static final POWERS_OF_TEN:Array<Float> = [
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
        1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
    ];

    /**
     * `a * 10^k`, through exact powers of ten only, so that every target does
     * the same rounded operations.
     */
    static function scaleByPowerOfTen(a:Float, k:Int):Float {
        var result = a;
        if (k >= 0) {
            while (k > 22) {
                result *= 1e22;
                k -= 22;
            }
            return result * POWERS_OF_TEN[k];
        }
        k = -k;
        while (k > 22) {
            result /= 1e22;
            k -= 22;
        }
        return result / POWERS_OF_TEN[k];
    }

    /**
     * A value as text, as interpolation, concatenation, `string()` and
     * `array_join` write it: a text as it is, numbers with numberText, `true`
     * and `false`, `null`, arrays and objects with their items (cycles written
     * `...`), a beat by its name, a character by its `name` field.
     */
    public static function textOf(value:Any, interpreter:Null<Interpreter>):String {
        return textOfImpl(value, interpreter, null);
    }

    static function textOfImpl(value:Any, interpreter:Null<Interpreter>, seen:Null<Array<Any>>):String {

        if (value == null) return 'null';
        if (value is String) return (value : String);

        final type = Type.typeof(value);
        switch type {
            case TBool: return (value : Bool) ? 'true' : 'false';
            case TInt | TFloat: return numberText(numberOf(value, type));
            case _:
        }

        // Cycle detection for reference types (arrays and fields)
        if (seen == null) seen = [];
        for (s in seen) {
            if (same(s, value)) return '...';
        }
        seen.push(value);

        if (Arrays.isArray(value)) {
            final len = Arrays.arrayLength(value);
            final buf = new StringBuf();
            buf.add('[');
            for (i in 0...len) {
                if (i > 0) buf.add(', ');
                buf.add(textOfImpl(Arrays.arrayGet(value, i), interpreter, seen));
            }
            buf.add(']');
            seen.pop();
            return buf.toString();
        }

        final asBeat = RuntimeBeatRef.beatOf(value);
        if (asBeat != null) {
            seen.pop();
            return asBeat.name;
        }

        final asCharacter = RuntimeCharacterRef.characterOf(value);
        if (asCharacter != null) {
            final nameValue = Objects.getField(interpreter, asCharacter.fields, 'name');
            seen.pop();
            return nameValue != null ? textOfImpl(nameValue, interpreter, null) : asCharacter.name;
        }

        if (Objects.isFields(value)) {
            final keys = Objects.getFields(interpreter, value);
            keys.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
            final buf = new StringBuf();
            buf.add('{');
            for (i in 0...keys.length) {
                if (i > 0) buf.add(', ');
                buf.add(keys[i]);
                buf.add(': ');
                buf.add(textOfImpl(Objects.getField(interpreter, value, keys[i]), interpreter, seen));
            }
            buf.add('}');
            seen.pop();
            return buf.toString();
        }

        // Anything else: a function, a value of the host
        seen.pop();
        return Std.string(value);

    }

    /**
     * A text argument of a built-in function: a text as it is, a number or a
     * boolean as textOf writes it. Anything else is an error naming the
     * function, as there is no text that could stand for it.
     */
    public static function textArg(value:Any, functionName:String):String {
        if (value is String) return (value : String);
        final type = value == null ? TNull : Type.typeof(value);
        return switch type {
            case TBool | TInt | TFloat: textOf(value, null);
            case _: throw new RuntimeError('$functionName() expects a text, got ${describeForError(value)}');
        }
    }

    /**
     * A number argument of a built-in function: a number, or a text written
     * as a number (see numberOfText). Anything else is an error naming the
     * function.
     */
    public static function numberArg(value:Any, functionName:String):Float {
        if (value != null) {
            final type = Type.typeof(value);
            switch type {
                case TInt | TFloat: return numberOf(value, type);
                case _:
            }
            if (value is String) {
                final number = numberOfText(value);
                if (!Math.isNaN(number)) return number;
            }
        }
        throw new RuntimeError('$functionName() expects a number, got ${describeForError(value)}');
    }

    /** A value in an error message: a text quoted, anything else by its kind. */
    static function describeForError(value:Any):String {
        return (value is String) ? '"' + (value : String) + '"' : typeOf(value);
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
