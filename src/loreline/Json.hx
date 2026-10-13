package loreline;

@:keep
class Json {

    public static function stringify(value:Any, pretty:Bool = false) {
        #if (cpp || lua)
        return SafeJsonPrinter.printValue(value, pretty ? '  ' : null);
        #else
        return haxe.Json.stringify(value, null, pretty ? '  ' : null);
        #end
    }

    public static function parse(json:String) {
        #if lua
        return new LuaJsonParser(json).parse();
        #else
        return haxe.Json.parse(json);
        #end
    }

}

#if (cpp || lua)
/**
 * haxe.format.JsonPrinter, with what it gets wrong on some targets:
 * - on hxcpp it adds a text unit by unit, and a UTF-16 surrogate added alone
 *   becomes U+FFFD (see loreline.Utf8.Utf8Buf): a character above U+FFFF in a
 *   saved text was lost. This printer adds such a character whole.
 * - on Lua it writes a decimal with Std.string, which fails on a decimal
 *   without an integer representation beyond 2^31 (the bit32 operations of
 *   Lua 5.4 refuse it). This printer writes decimals as the printer of the
 *   script writes number literals.
 */
private class SafeJsonPrinter extends haxe.format.JsonPrinter {

    public static function printValue(value:Dynamic, space:Null<String>):String {
        final printer = new SafeJsonPrinter(null, space);
        printer.write("", value);
        return printer.buf.toString();
    }

    #if lua
    override function write(k:Dynamic, v:Dynamic) {
        if (Type.typeof(v) == TFloat) {
            final number:Float = v;
            buf.add(Math.isFinite(number) ? Values.numberLiteral(number) : 'null');
            return;
        }
        super.write(k, v);
    }
    #end

    #if cpp
    override function quote(s:String) {
        buf.addChar('"'.code);
        var i = 0;
        final length = s.length;
        while (i < length) {
            final c = StringTools.fastCodeAt(s, i++);
            switch c {
                case '"'.code:
                    buf.add('\\"');
                case '\\'.code:
                    buf.add('\\\\');
                case '\n'.code:
                    buf.add('\\n');
                case '\r'.code:
                    buf.add('\\r');
                case '\t'.code:
                    buf.add('\\t');
                case 8:
                    buf.add('\\b');
                case 12:
                    buf.add('\\f');
                case _ if (c >= 0xD800 && c <= 0xDBFF && i < length):
                    final next = StringTools.fastCodeAt(s, i);
                    if (next >= 0xDC00 && next <= 0xDFFF) {
                        buf.addChar(0x10000 + ((c - 0xD800) << 10) + (next - 0xDC00));
                        i++;
                    }
                    else {
                        buf.addChar(c);
                    }
                default:
                    buf.addChar(c);
            }
        }
        buf.addChar('"'.code);
    }
    #end

}
#end

#if lua
/**
 * A JSON reader for Lua, which gives the same values as haxe.Json.parse.
 * haxe.format.JsonParser makes each number an Int with Std.int, and on Lua
 * Std.int fails on a decimal beyond 2^31 that is not whole (the bit32
 * operations of Lua 5.4 refuse it): a saved decimal like 3000000000.5 could
 * not be read back. Here, only whole numbers that fit in 32 bits become Ints.
 */
private class LuaJsonParser {

    final text:String;
    var pos:Int = 0;

    public function new(text:String) {
        this.text = text;
    }

    public function parse():Dynamic {
        final value = readValue();
        skipSpaces();
        if (pos < text.length) fail();
        return value;
    }

    function fail():Dynamic {
        throw 'Invalid JSON at position $pos';
    }

    inline function code(at:Int):Int {
        return StringTools.fastCodeAt(text, at);
    }

    function skipSpaces():Void {
        while (pos < text.length) {
            final c = code(pos);
            if (c != ' '.code && c != '\t'.code && c != '\n'.code && c != '\r'.code) break;
            pos++;
        }
    }

    function readValue():Dynamic {
        skipSpaces();
        if (pos >= text.length) return fail();
        return switch code(pos) {
            case '{'.code: readObject();
            case '['.code: readArray();
            case '"'.code: readString();
            case 't'.code: readWord('true', true);
            case 'f'.code: readWord('false', false);
            case 'n'.code: readWord('null', null);
            case _: readNumber();
        }
    }

    function readWord(word:String, value:Dynamic):Dynamic {
        if (text.substr(pos, word.length) != word) return fail();
        pos += word.length;
        return value;
    }

    function readObject():Dynamic {
        final result:Dynamic = {};
        pos++;
        skipSpaces();
        if (pos < text.length && code(pos) == '}'.code) {
            pos++;
            return result;
        }
        while (true) {
            skipSpaces();
            if (pos >= text.length || code(pos) != '"'.code) return fail();
            final key = readString();
            skipSpaces();
            if (pos >= text.length || code(pos) != ':'.code) return fail();
            pos++;
            Reflect.setField(result, key, readValue());
            skipSpaces();
            if (pos >= text.length) return fail();
            final c = code(pos++);
            if (c == '}'.code) return result;
            if (c != ','.code) return fail();
        }
    }

    function readArray():Dynamic {
        final result:Array<Dynamic> = [];
        pos++;
        skipSpaces();
        if (pos < text.length && code(pos) == ']'.code) {
            pos++;
            return result;
        }
        while (true) {
            result.push(readValue());
            skipSpaces();
            if (pos >= text.length) return fail();
            final c = code(pos++);
            if (c == ']'.code) return result;
            if (c != ','.code) return fail();
        }
    }

    function readString():String {
        // The text is UTF-8 bytes on Lua: runs without escapes are copied as
        // they are, escapes are written as UTF-8 too
        pos++;
        final buf = new StringBuf();
        var start = pos;
        while (true) {
            if (pos >= text.length) return fail();
            final c = code(pos);
            if (c == '"'.code) {
                buf.add(text.substr(start, pos - start));
                pos++;
                return buf.toString();
            }
            if (c != '\\'.code) {
                pos++;
                continue;
            }
            buf.add(text.substr(start, pos - start));
            pos++;
            if (pos >= text.length) return fail();
            final escaped = code(pos++);
            switch escaped {
                case 'n'.code: buf.add('\n');
                case 'r'.code: buf.add('\r');
                case 't'.code: buf.add('\t');
                case 'b'.code: buf.addChar(8);
                case 'f'.code: buf.addChar(12);
                case 'u'.code:
                    var point = readHex();
                    // A surrogate pair stands for one character above U+FFFF
                    if (point >= 0xD800 && point <= 0xDBFF && text.substr(pos, 2) == '\\u') {
                        pos += 2;
                        final low = readHex();
                        point = 0x10000 + ((point - 0xD800) << 10) + (low - 0xDC00);
                    }
                    addUtf8(buf, point);
                case _: buf.addChar(escaped);
            }
            start = pos;
        }
    }

    function readHex():Int {
        final value = Std.parseInt('0x' + text.substr(pos, 4));
        if (value == null) return fail();
        pos += 4;
        return value;
    }

    static function addUtf8(buf:StringBuf, point:Int):Void {
        if (point < 0x80) {
            buf.addChar(point);
        }
        else if (point < 0x800) {
            buf.addChar(0xC0 | (point >> 6));
            buf.addChar(0x80 | (point & 63));
        }
        else if (point < 0x10000) {
            buf.addChar(0xE0 | (point >> 12));
            buf.addChar(0x80 | ((point >> 6) & 63));
            buf.addChar(0x80 | (point & 63));
        }
        else {
            buf.addChar(0xF0 | (point >> 18));
            buf.addChar(0x80 | ((point >> 12) & 63));
            buf.addChar(0x80 | ((point >> 6) & 63));
            buf.addChar(0x80 | (point & 63));
        }
    }

    function readNumber():Dynamic {
        final start = pos;
        var whole = true;
        while (pos < text.length) {
            final c = code(pos);
            if (c == '.'.code || c == 'e'.code || c == 'E'.code) whole = false;
            else if (!((c >= '0'.code && c <= '9'.code) || c == '-'.code || c == '+'.code)) break;
            pos++;
        }
        if (pos == start) return fail();
        final number = Std.parseFloat(text.substr(start, pos - start));
        if (Math.isNaN(number)) return fail();
        // An Int only when it fits in one, as haxe.Json.parse gives for those
        if (whole && number >= -2147483648 && number <= 2147483647) return Std.int(number);
        return number;
    }

}
#end
