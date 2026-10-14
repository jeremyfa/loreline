package loreline;

#if neko
import neko.Utf8;
#end
import haxe.ds.Vector;

#if loreline_utf8_vector
#error "loreline_utf8_vector is gone: Neko and PHP always scan a vector of code points"
#end

/**
 * Text operations indexed in the units of the target, those of every
 * `Position` (line, column, offset, length): UTF-16 units on JS, C#, Java and
 * C++, UTF-8 bytes on Lua, characters (code points) on Python, PHP, GDScript
 * and Neko (through `neko.Utf8`, although its strings hold bytes). The `u`
 * prefix means "units". Use with: using loreline.TextUnits;
 *
 * `uCharCodeAt` gives one unit. That is enough to compare with ASCII: a
 * trailing unit of a longer character (a low surrogate, a UTF-8 continuation
 * byte) is never below 0x80, so a scan that only compares with ASCII may step
 * one unit at a time. To read a character beyond ASCII, or to classify one
 * (`Identifiers.isStart`, `isPart`...), read it whole with `loreline.Chars`.
 */
class TextUnits {

    /** The length of a text, in units */
    public static inline function uLength(str:String):Int {
        #if neko
        return neko.Utf8.length(str);
        #else
        return str.length;
        #end
    }

    /** Part of a text, from a unit position, `len` units long */
    public static inline function uSubstr(str:String, pos:Int, ?len:Int):String {
        #if neko
        return neko.Utf8.sub(str, pos, len != null ? len : (neko.Utf8.length(str) - pos));
        #else
        return len != null ? str.substr(pos, len) : str.substr(pos);
        #end
    }

    /** Part of a text, between two unit positions */
    public static #if !neko inline #end function uSubstring(str:String, startIndex:Int, ?endIndex:Int):String {
        #if neko
        final len = neko.Utf8.length(str);
        final end = (endIndex != null) ? endIndex : len;
        return neko.Utf8.sub(str, startIndex, end - startIndex);
        #else
        return endIndex != null ? str.substring(startIndex, endIndex) : str.substring(startIndex);
        #end
    }

    /**
     * The unit at a position, or -1 past the end. On UTF-16 and UTF-8 targets
     * it can be half a character: `Chars.codeAt` reads a whole one.
     */
    public static #if (!neko && !python) inline #end function uCharCodeAt(str:String, pos:Int):Int {
        #if neko
        if (pos < 0 || pos >= neko.Utf8.length(str)) return -1;
        return neko.Utf8.charCodeAt(str, pos);
        #else
        final c = str.charCodeAt(pos);
        return c == null ? -1 : c;
        #end
    }

    /** Where a text first appears in another, in units, or -1 */
    public static #if !neko inline #end function uIndexOf(str:String, substr:String, ?startIndex:Int):Int {
        #if neko
        if (startIndex == null) startIndex = 0;
        final strLen = neko.Utf8.length(str);
        final subLen = neko.Utf8.length(substr);
        if (subLen == 0) return startIndex;
        if (startIndex < 0) startIndex = 0;
        if (startIndex >= strLen) return -1;

        for (i in startIndex...(strLen - subLen + 1)) {
            if (neko.Utf8.sub(str, i, subLen) == substr) return i;
        }
        return -1;
        #else
        return str.indexOf(substr, startIndex);
        #end
    }

    /** Where a text last appears in another, in units, or -1 */
    public static #if !neko inline #end function uLastIndexOf(str:String, substr:String, ?startIndex:Int):Int {
        #if neko
        final strLen = neko.Utf8.length(str);
        final subLen = neko.Utf8.length(substr);
        if (subLen == 0) return startIndex ?? strLen;
        if (startIndex == null || startIndex >= strLen) startIndex = strLen - subLen;
        if (startIndex < 0) return -1;

        var i = startIndex;
        while (i >= 0) {
            if (neko.Utf8.sub(str, i, subLen) == substr) return i;
            i--;
        }
        return -1;
        #else
        return str.lastIndexOf(substr, startIndex);
        #end
    }

    /** The unit at a position as a text, empty past the end */
    public static inline function uCharAt(str:String, pos:Int):String {
        #if neko
        if (pos < 0 || pos >= neko.Utf8.length(str)) return "";
        return neko.Utf8.sub(str, pos, 1);
        #else
        return str.charAt(pos);
        #end
    }

    /**
     * The code points of a text, one per slot, in a single pass. Only for
     * Neko and PHP, whose native units are code points but whose indexing is
     * O(n): the lexer and the scanners there index this vector in O(1).
     */
    #if (neko || php)
    public static function toCodes(str:String):Vector<Int> {
        #if neko
        final len = neko.Utf8.length(str);
        final v = new Vector<Int>(len);
        var i = 0;
        neko.Utf8.iter(str, function(c:Int) { v[i++] = c; });
        return v;
        #else
        final chars:php.NativeIndexedArray<String> = php.Syntax.code("mb_str_split({0})", str);
        final len = php.Global.count(chars);
        final v = new Vector<Int>(len);
        for (i in 0...len) {
            v[i] = chars[i].charCodeAt(0);
        }
        return v;
        #end
    }
    #end

}

#if neko
class TextUnitsBuf {
    public var length(get, never):Int;
    inline function get_length():Int {
        return codes.length;
    }
    final codes:Array<Int> = [];

    public function new() {}

    public inline function add(x:Dynamic):Void {
        final str = Std.string(x);
        final len = neko.Utf8.length(str);
        for (i in 0...len) {
            addChar(neko.Utf8.charCodeAt(str, i));
        }
    }

    public inline function addChar(c:Int):Void {
        codes.push(c);
    }

    public function toString():String {
        final buf = new neko.Utf8();
        for (code in codes) {
            buf.addChar(code);
        }
        return buf.toString();
    }
}
#elseif cpp
/**
 * A StringBuf that puts characters above U+FFFF back together. Readers that
 * go through a text unit by unit add the two UTF-16 surrogates of such a
 * character one after the other, and on hxcpp StringBuf.addChar makes each of
 * them alone a text with String.fromCharCode, which refuses surrogates and
 * gives U+FFFD instead (String.cpp, IsUtf16Surrogate).
 */
class TextUnitsBuf {
    public var length(get, never):Int;
    inline function get_length():Int {
        return buf.length + (pendingHigh != -1 ? 1 : 0);
    }
    final buf = new StringBuf();
    var pendingHigh:Int = -1;

    public function new() {}

    public function add(x:Dynamic):Void {
        flushPending();
        buf.add(x);
    }

    public function addChar(c:Int):Void {
        if (c >= 0xD800 && c <= 0xDBFF) {
            flushPending();
            pendingHigh = c;
        }
        else if (c >= 0xDC00 && c <= 0xDFFF && pendingHigh != -1) {
            buf.addChar(0x10000 + ((pendingHigh - 0xD800) << 10) + (c - 0xDC00));
            pendingHigh = -1;
        }
        else {
            flushPending();
            buf.addChar(c);
        }
    }

    function flushPending():Void {
        if (pendingHigh != -1) {
            buf.addChar(pendingHigh);
            pendingHigh = -1;
        }
    }

    public function toString():String {
        flushPending();
        return buf.toString();
    }
}
#else
typedef TextUnitsBuf = StringBuf;
#end
