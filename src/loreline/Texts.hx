package loreline;

/**
 * Text operations that count characters, the same on every target.
 *
 * Targets hold texts in UTF-8 bytes (Neko, Lua), in UTF-16 units (JS, C#,
 * Java, C++) or in characters (Python, PHP, GDScript), and their native
 * length, indexOf and substr count these units. Here a character counts for
 * one, an accented letter or an emoji included: the units where each
 * character starts are found first (charOffsets), then the native operations
 * are used between them.
 *
 * Upper and lower case follow a table of their own, the same everywhere: the
 * Latin letters of European languages, Greek and Cyrillic. `ß` becomes `SS` in
 * upper case, as in Unicode. Other characters stay as they are.
 */
class Texts {

    /**
     * An emoji, in a variable rather than a constant: the compiler would
     * compute the length of a constant with its own encoding (in characters),
     * not with the one of the target.
     */
    static var emoji:String = "\u{1F600}";

    /**
     * How many units of the target an emoji takes: 4 for UTF-8 bytes, 2 for
     * UTF-16 units, 1 for characters.
     */
    static final UNITS_PER_EMOJI:Int = emoji.length;

    /**
     * The offsets, in units of the target, where each character of a text
     * starts, followed by the length of the text in units.
     */
    public static function charOffsets(text:String):Array<Int> {
        final length = text.length;
        final offsets:Array<Int> = [];
        if (UNITS_PER_EMOJI == 1) {
            for (i in 0...length) offsets.push(i);
        }
        else if (UNITS_PER_EMOJI == 2) {
            var i = 0;
            while (i < length) {
                offsets.push(i);
                final c = StringTools.fastCodeAt(text, i);
                // A high surrogate and its low surrogate make one character
                if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length) {
                    final next = StringTools.fastCodeAt(text, i + 1);
                    i += (next >= 0xDC00 && next <= 0xDFFF) ? 2 : 1;
                }
                else {
                    i++;
                }
            }
        }
        else {
            var i = 0;
            while (i < length) {
                offsets.push(i);
                final c = StringTools.fastCodeAt(text, i);
                // The lead byte of a UTF-8 sequence tells its length
                i += c < 0xC0 ? 1 : (c < 0xE0 ? 2 : (c < 0xF0 ? 3 : 4));
            }
        }
        offsets.push(length);
        return offsets;
    }

    /** The number of characters of a text. */
    public static function length(text:String):Int {
        return charOffsets(text).length - 1;
    }

    /** The characters of a text, each one as a text. */
    public static function chars(text:String):Array<String> {
        final offsets = charOffsets(text);
        return [for (i in 0...offsets.length - 1) text.substr(offsets[i], offsets[i + 1] - offsets[i])];
    }

    /**
     * Part of a text, in characters: from `start` (from the end when
     * negative), `length` characters or up to the end when null. Empty when
     * nothing is left.
     */
    public static function sub(text:String, start:Int, ?length:Int):String {
        final offsets = charOffsets(text);
        final count = offsets.length - 1;
        if (start < 0) start = start + count < 0 ? 0 : start + count;
        if (start >= count) return '';
        var end = length == null ? count : start + length;
        if (end > count) end = count;
        if (end <= start) return '';
        return text.substr(offsets[start], offsets[end] - offsets[start]);
    }

    /** The position in characters of the first `needle` in a text, or -1. */
    public static function indexOf(text:String, needle:String):Int {
        final unit = text.indexOf(needle);
        if (unit <= 0) return unit;
        final offsets = charOffsets(text);
        // The character that starts at that unit (UTF-8 and UTF-16 can't
        // match in the middle of a character)
        var low = 0;
        var high = offsets.length - 1;
        while (low < high) {
            final mid = (low + high) >> 1;
            if (offsets[mid] < unit) low = mid + 1 else high = mid;
        }
        return low;
    }

    /** A text in upper case, see the table of this class. */
    public static function upper(text:String):String {
        return convertCase(text, true);
    }

    /** A text in lower case, see the table of this class. */
    public static function lower(text:String):String {
        return convertCase(text, false);
    }

    static function convertCase(text:String, toUpper:Bool):String {
        final table = toUpper ? upperTable() : lowerTable();
        final buf = new StringBuf();
        final offsets = charOffsets(text);
        for (i in 0...offsets.length - 1) {
            final char = text.substr(offsets[i], offsets[i + 1] - offsets[i]);
            final converted = table.get(char);
            buf.add(converted != null ? converted : char);
        }
        return buf.toString();
    }

    /** The letters that have an upper case, and their upper case, in the same order. */
    static final LOWER_LETTERS = "abcdefghijklmnopqrstuvwxyzàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿāăąćĉċčďđēĕėęěĝğġģĥħĩīĭįĳĵķŋōŏőœŕŗřśŝşšţťŧũūŭůűųŵŷĺļľŀłńņňźżžαβγδεζηθικλμνξοπρστυφχψωάέήίόύώабвгдежзийклмнопрстуфхцчшщъыьэюяѐёђѓєѕіїјљњћќѝўџ";
    static final UPPER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸĀĂĄĆĈĊČĎĐĒĔĖĘĚĜĞĠĢĤĦĨĪĬĮĲĴĶŊŌŎŐŒŔŖŘŚŜŞŠŢŤŦŨŪŬŮŰŲŴŶĹĻĽĿŁŃŅŇŹŻŽΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩΆΈΉΊΌΎΏАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЀЁЂЃЄЅІЇЈЉЊЋЌЍЎЏ";

    static var upperByLower:Null<Map<String, String>> = null;
    static var lowerByUpper:Null<Map<String, String>> = null;

    static function upperTable():Map<String, String> {
        if (upperByLower == null) buildTables();
        return upperByLower;
    }

    static function lowerTable():Map<String, String> {
        if (lowerByUpper == null) buildTables();
        return lowerByUpper;
    }

    static function buildTables():Void {
        final lowers = chars(LOWER_LETTERS);
        final uppers = chars(UPPER_LETTERS);
        final toUpper = new Map<String, String>();
        final toLower = new Map<String, String>();
        for (i in 0...lowers.length) {
            toUpper.set(lowers[i], uppers[i]);
            toLower.set(uppers[i], lowers[i]);
        }
        // Upper case only: the sharp s, the final sigma, the dotless i
        toUpper.set("\u00DF", "SS");
        toUpper.set("\u03C2", "\u03A3");
        toUpper.set("\u0131", "I");
        upperByLower = toUpper;
        lowerByUpper = toLower;
    }

}
