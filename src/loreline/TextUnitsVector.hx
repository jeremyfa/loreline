package loreline;

import haxe.ds.Vector;
import loreline.TextUnits.TextUnitsBuf;

/**
 * Mirrors `loreline.TextUnits` over the vector of code points that
 * `TextUnits.toCodes` builds, so the lexer and the scanners on Neko and PHP
 * index characters in O(1). Only compiled there: on every other target, the
 * native units are the ones scanned.
 *
 * Use with: using loreline.TextUnitsVector;
 *
 * Method names, signatures and return types match `loreline.TextUnits`, so
 * call sites (`input.uCharCodeAt(pos)`, `input.uSubstr(...)`) resolve here or
 * there by the receiver type, with no other change.
 */
#if (neko || php)
class TextUnitsVector {

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

    public static function uIndexOf(v:Vector<Int>, substr:String, ?startIndex:Int):Int {
        final needle = TextUnits.toCodes(substr);
        final nlen = needle.length;
        if (nlen == 0) return startIndex != null ? startIndex : 0;
        var i = (startIndex != null && startIndex > 0) ? startIndex : 0;
        final last = v.length - nlen;
        while (i <= last) {
            var k = 0;
            while (k < nlen && v[i + k] == needle[k]) k++;
            if (k == nlen) return i;
            i++;
        }
        return -1;
    }

    static function slice(v:Vector<Int>, start:Int, end:Int):String {
        if (start < 0) start = 0;
        if (end > v.length) end = v.length;
        final buf = new TextUnitsBuf();
        var i = start;
        while (i < end) {
            buf.addChar(v[i]);
            i++;
        }
        return buf.toString();
    }

}
#end
