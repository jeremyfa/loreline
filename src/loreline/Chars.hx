package loreline;

using loreline.TextUnits;

/**
 * Whole characters over the units of `loreline.TextUnits`. `codeAt` gives the
 * code point at a unit position (a surrogate pair or two to four bytes read as
 * one), `unitsAt` its length in units, `startBefore` steps back over one,
 * `count` counts them, `textOf` writes one. Positions stay in units: nothing
 * here converts a position to characters.
 *
 * Call these qualified (`Chars.codeAt(text, pos)`), not as extensions: at a
 * call site, a character read must not look like a unit read.
 *
 * On Neko, `codeAt` on a String is O(pos), as `neko.Utf8.charCodeAt` walks the
 * bytes from the start: the scanners there work on a vector of code points.
 */
class Chars {

    /**
     * An emoji, in a variable rather than a constant: the compiler would compute
     * the length of a constant with its own encoding, not with the one of the target.
     */
    static var emoji:String = "\u{1F600}";

    /**
     * How many units `uCharCodeAt` reads for an emoji: 1 for characters, 2 for
     * UTF-16 units, 4 for UTF-8 bytes. On Neko, `uCharCodeAt` reads characters
     * through neko.Utf8 although strings hold bytes.
     */
    public static final UNITS:Int = #if neko 1 #else emoji.length #end;

    /**
     * How many characters a text holds, whatever the units of the target: an
     * emoji or a Chinese character is one character.
     */
    public static function count(text:String):Int {
        final length = text.uLength();
        if (UNITS == 1) return length;
        var count = 0;
        var pos = 0;
        while (pos < length) {
            pos += stringUnitsAt(text, pos);
            count++;
        }
        return count;
    }

    /**
     * A character as a text, on every target: added unit by unit, as UTF-8 bytes
     * or UTF-16 surrogates when the target's texts hold those.
     */
    public static function textOf(c:Int):String {
        final buf = new loreline.TextUnits.TextUnitsBuf();
        if (UNITS == 4 && c >= 0x80) {
            if (c < 0x800) {
                buf.addChar(0xC0 | (c >> 6));
            }
            else if (c < 0x10000) {
                buf.addChar(0xE0 | (c >> 12));
                buf.addChar(0x80 | ((c >> 6) & 0x3F));
            }
            else {
                buf.addChar(0xF0 | (c >> 18));
                buf.addChar(0x80 | ((c >> 12) & 0x3F));
                buf.addChar(0x80 | ((c >> 6) & 0x3F));
            }
            buf.addChar(0x80 | (c & 0x3F));
        }
        else if (UNITS == 2 && c >= 0x10000) {
            buf.addChar(0xD800 + ((c - 0x10000) >> 10));
            buf.addChar(0xDC00 + ((c - 0x10000) & 0x3FF));
        }
        else {
            buf.addChar(c);
        }
        return buf.toString();
    }

    /**
     * The whole character at the given position of a text read with
     * `uCharCodeAt`, or -1 past its end.
     */
    public static overload extern inline function codeAt(text:String, pos:Int):Int {
        return stringCodeAt(text, pos);
    }

    /**
     * How many units the character at the given position takes (0 past the end).
     */
    public static overload extern inline function unitsAt(text:String, pos:Int):Int {
        return stringUnitsAt(text, pos);
    }

    /**
     * Where the character that ends right before the given position starts.
     */
    public static overload extern inline function startBefore(text:String, pos:Int):Int {
        return stringStartBefore(text, pos);
    }

    #if (neko || php)

    public static overload extern inline function codeAt(codes:haxe.ds.Vector<Int>, pos:Int):Int {
        return pos >= 0 && pos < codes.length ? codes[pos] : -1;
    }

    public static overload extern inline function unitsAt(codes:haxe.ds.Vector<Int>, pos:Int):Int {
        return pos >= 0 && pos < codes.length ? 1 : 0;
    }

    public static overload extern inline function startBefore(codes:haxe.ds.Vector<Int>, pos:Int):Int {
        return pos - 1;
    }

    #end

    static function stringCodeAt(text:String, pos:Int):Int {
        final c = text.uCharCodeAt(pos);
        if (c < 0x80) return c;
        if (UNITS == 2) {
            if (c >= 0xD800 && c <= 0xDBFF) {
                final next = text.uCharCodeAt(pos + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) {
                    return 0x10000 + ((c - 0xD800) << 10) + (next - 0xDC00);
                }
            }
            return c;
        }
        if (UNITS == 4) {
            final count = utf8Length(c);
            if (count == 1) return 0xFFFD;
            var code = c & (count == 2 ? 0x1F : count == 3 ? 0x0F : 0x07);
            for (i in 1...count) {
                final b = text.uCharCodeAt(pos + i);
                if (b < 0x80 || b > 0xBF) return 0xFFFD;
                code = (code << 6) | (b & 0x3F);
            }
            return code;
        }
        return c;
    }

    static function stringUnitsAt(text:String, pos:Int):Int {
        final c = text.uCharCodeAt(pos);
        if (c < 0) return 0;
        if (c < 0x80 || UNITS == 1) return 1;
        if (UNITS == 2) {
            if (c >= 0xD800 && c <= 0xDBFF) {
                final next = text.uCharCodeAt(pos + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) return 2;
            }
            return 1;
        }
        // UTF-8: as many bytes as the lead byte says, if they are all there
        final count = utf8Length(c);
        for (i in 1...count) {
            final b = text.uCharCodeAt(pos + i);
            if (b < 0x80 || b > 0xBF) return i;
        }
        return count;
    }

    static function stringStartBefore(text:String, pos:Int):Int {
        if (pos <= 0) return pos - 1;
        if (UNITS == 1) return pos - 1;
        final c = text.uCharCodeAt(pos - 1);
        if (UNITS == 2) {
            if (c >= 0xDC00 && c <= 0xDFFF && pos >= 2) {
                final prev = text.uCharCodeAt(pos - 2);
                if (prev >= 0xD800 && prev <= 0xDBFF) return pos - 2;
            }
            return pos - 1;
        }
        // UTF-8: step back over the continuation bytes, up to a lead byte
        var p = pos - 1;
        while (p > 0 && pos - p < 4) {
            final b = text.uCharCodeAt(p);
            if (b < 0x80 || b > 0xBF) break;
            p--;
        }
        return p;
    }

    /** How many bytes a UTF-8 character takes, from its lead byte (1 for a stray continuation byte) */
    static inline function utf8Length(lead:Int):Int {
        return lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
    }

}
