package loreline;

#if neko
import neko.Utf8;
#end

/**
 * UTF-8 aware string operations that can be used as extension methods.
 * Use with: using loreline.Utf8;
 */
class Utf8 {

    /**
     * UTF-8 aware string length
     */
    public static inline function uLength(str:String):Int {
        #if neko
        return neko.Utf8.length(str);
        #else
        return str.length;
        #end
    }

    /**
     * UTF-8 aware substring extraction
     */
    public static inline function uSubstr(str:String, pos:Int, ?len:Int):String {
        #if neko
        return neko.Utf8.sub(str, pos, len != null ? len : (neko.Utf8.length(str) - pos));
        #else
        return len != null ? str.substr(pos, len) : str.substr(pos);
        #end
    }

    /**
     * UTF-8 aware substring with end position
     */
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
     * UTF-8 aware character code at position
     */
    public static #if !neko inline #end function uCharCodeAt(str:String, pos:Int):Null<Int> {
        #if neko
        if (pos < 0 || pos >= neko.Utf8.length(str)) return null;
        return neko.Utf8.charCodeAt(str, pos);
        #else
        return str.charCodeAt(pos);
        #end
    }

    /**
     * UTF-8 aware indexOf
     */
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

    /**
     * UTF-8 aware lastIndexOf
     */
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

    /**
     * UTF-8 aware string to char array
     */
    public static #if !neko inline #end function uToChars(str:String):Array<String> {
        #if neko
        final len = neko.Utf8.length(str);
        return [for (i in 0...len) neko.Utf8.sub(str, i, 1)];
        #else
        return str.split("");
        #end
    }

    /**
     * UTF-8 aware charAt
     */
    public static inline function uCharAt(str:String, pos:Int):String {
        #if neko
        if (pos < 0 || pos >= neko.Utf8.length(str)) return "";
        return neko.Utf8.sub(str, pos, 1);
        #else
        return str.charAt(pos);
        #end
    }

}

#if neko
class Utf8Buf {
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
#else
typedef Utf8Buf = StringBuf;
#end
