package loreline;

import haxe.ds.Vector;
import loreline.Utf8.Utf8Buf;

/**
 * Mirrors the loreline.Utf8 extension API but over a Vector<Int> of code
 * points, so a lexer/scanner whose source buffer is a Vector<Int> can index
 * characters in O(1) on every target. Enabled via -D loreline_utf8_vector.
 *
 * Use with: using loreline.Utf8Vector;
 *
 * Method names, signatures and return types match loreline.Utf8, so call
 * sites (input.uCharCodeAt(pos), input.uSubstr(...), ...) resolve here or on
 * loreline.Utf8 purely by the receiver type, with no other change.
 */
class Utf8Vector {

    public static inline function uLength(v:Vector<Int>):Int {
        return v.length;
    }

    public static inline function uCharCodeAt(v:Vector<Int>, pos:Int):Int {
        return (pos < 0 || pos >= v.length) ? -1 : v[pos];
    }

    public static inline function uSubstr(v:Vector<Int>, pos:Int, ?len:Int):String {
        return slice(v, pos, len != null ? pos + len : v.length);
    }

    public static inline function uSubstring(v:Vector<Int>, startIndex:Int, ?endIndex:Int):String {
        return slice(v, startIndex, endIndex != null ? endIndex : v.length);
    }

    public static inline function uCharAt(v:Vector<Int>, pos:Int):String {
        return (pos < 0 || pos >= v.length) ? "" : slice(v, pos, pos + 1);
    }

    static function slice(v:Vector<Int>, start:Int, end:Int):String {
        if (start < 0) start = 0;
        if (end > v.length) end = v.length;
        final buf = new Utf8Buf();
        var i = start;
        while (i < end) {
            buf.addChar(v[i]);
            i++;
        }
        return buf.toString();
    }

}
