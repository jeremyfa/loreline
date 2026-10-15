package loreline;

using loreline.TextUnits;

/**
 * A plural written with pipes in a text: `coin|coins`, `plik|pliki|plików`,
 * or forms holding spaces between parentheses, `(cold drink|cold drinks)`.
 */
typedef PluralPipe = {

    /** Where the plural starts in the text */
    var start:Int;

    /** Where it ends, excluded: punctuation after it is not part of it */
    var end:Int;

    /** Its forms, in order */
    var forms:Array<String>;

    /** The characters marking it, which editors color: its pipes and parentheses */
    var marks:Array<Int>;

}

/**
 * Finds the plurals written with pipes in the raw text of a string literal,
 * the same way for the interpreter and for the editors that color them.
 * Positions are units of `loreline.TextUnits`, those of node positions. The
 * scans compare with ASCII and step unit by unit; only the quotes and the
 * ellipsis around a plural are read whole, with `Chars.codeAt`.
 */
class PluralPipes {

    /**
     * The plurals of a raw text, in order. A plural only counts after an
     * expression of the literal: callers check that.
     */
    public static function scan(text:String):Array<PluralPipe> {

        final result:Array<PluralPipe> = [];
        final len = text.uLength();
        // Where the previous plural ended: the next one can't start before
        var minStart = 0;
        var i = 0;

        while (i < len) {
            final c = text.uCharCodeAt(i);

            // An escaped character, like \|, is no pipe. Two units may land
            // inside a longer character, which is safe: nothing below matches
            // one of its trailing units.
            if (c == '\\'.code) {
                i += 2;
                continue;
            }

            if (c == '('.code) {
                final found = scanParentheses(text, i, len);
                if (found != null) {
                    result.push(found);
                    i = found.end;
                    minStart = i;
                    continue;
                }
            }

            if (c == '|'.code) {
                final found = scanWords(text, i, len, minStart);
                if (found != null) {
                    result.push(found);
                    i = found.end;
                    minStart = i;
                    continue;
                }
            }

            i++;
        }

        return result;

    }

    /** `(a|b|c)` opening at `open`, or null when the parentheses hold no plural */
    static function scanParentheses(text:String, open:Int, len:Int):Null<PluralPipe> {

        final pipes:Array<Int> = [];
        var close = -1;
        var j = open + 1;
        while (j < len) {
            final c = text.uCharCodeAt(j);
            if (c == '\\'.code) {
                j += 2;
                continue;
            }
            if (c == '|'.code) {
                pipes.push(j);
            }
            else if (c == ')'.code) {
                close = j;
                break;
            }
            j++;
        }
        if (close == -1 || pipes.length == 0) return null;

        final forms:Array<String> = [];
        var formStart = open + 1;
        for (pipe in pipes.concat([close])) {
            if (pipe == formStart) return null;
            forms.push(text.uSubstring(formStart, pipe));
            formStart = pipe + 1;
        }
        return {
            start: open,
            end: close + 1,
            forms: forms,
            marks: [open].concat(pipes).concat([close])
        };

    }

    /** `a|b|c` around the pipe at `pipe`, or null when a form is empty */
    static function scanWords(text:String, pipe:Int, len:Int, minStart:Int):Null<PluralPipe> {

        var start = pipe;
        while (start > minStart) {
            final before = Chars.startBefore(text, start);
            if (before < minStart || isWordEnd(text.uCharCodeAt(before))) break;
            start = before;
        }
        // Quotes before the first form are beyond ASCII: read whole
        while (start < pipe && isOpeningMark(Chars.codeAt(text, start))) start += Chars.unitsAt(text, start);
        if (start == pipe) return null;

        final forms = [text.uSubstring(start, pipe)];
        final pipes = [pipe];
        var formStart = pipe + 1;
        while (true) {
            var k = formStart;
            while (k < len) {
                final c = text.uCharCodeAt(k);
                if (c == '\\'.code) {
                    k += 2;
                    continue;
                }
                if (isWordEnd(c)) break;
                k++;
            }
            if (k > len) k = len;
            if (k < len && text.uCharCodeAt(k) == '|'.code) {
                if (k == formStart) return null;
                forms.push(text.uSubstring(formStart, k));
                pipes.push(k);
                formStart = k + 1;
                continue;
            }
            // The last form leaves out the punctuation after it, read whole:
            // the quotes and the ellipsis are beyond ASCII
            var end = k;
            while (end > formStart) {
                final before = Chars.startBefore(text, end);
                if (before < formStart || !isClosingMark(Chars.codeAt(text, before))) break;
                end = before;
            }
            if (end == formStart) return null;
            forms.push(text.uSubstring(formStart, end));
            return {start: start, end: end, forms: forms, marks: pipes};
        }

    }

    /** Where a form written without parentheses stops */
    static function isWordEnd(c:Int):Bool {
        return c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code
            || c == '|'.code || c == '('.code || c == ')'.code;
    }

    /** Quotes before a plural, which are not part of its first form */
    static function isOpeningMark(c:Int):Bool {
        return c == '"'.code || c == 0xAB || c == 0x201C;
    }

    /** Punctuation and quotes after a plural, which are not part of its last form */
    static function isClosingMark(c:Int):Bool {
        return c == '.'.code || c == ','.code || c == ';'.code || c == ':'.code
            || c == '!'.code || c == '?'.code || c == 0x2026
            || c == '"'.code || c == 0xBB || c == 0x201D;
    }

}
