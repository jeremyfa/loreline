package loreline.translation;

import loreline.AstUtils;
import loreline.Node;
import loreline.Printer;

using loreline.Utf8;

/**
 * Converts GNU gettext PO file content into a Loreline translation file body.
 *
 * Mapping:
 *   msgctxt "<key>"        → #<key> hash comment (preferred if present)
 *   msgid   "<source>"     → fallback for key if no msgctxt, else used as
 *                            `// <source>` reference comment
 *   msgstr  "<translated>" → the translation text line
 *
 * Empty `msgstr` → entry skipped.
 * Plural forms (`msgstr[N]`) → take `msgstr[0]`.
 * Multi-line msgid/msgstr (`msgid ""\n"line1"\n"line2"`) → concatenated.
 *
 * PO files are mono-locale by design; the `locale` parameter is accepted for
 * API uniformity with the other format converters but unused here.
 *
 * **msgstr must be valid Loreline body content** — its value is written
 * verbatim into the synthesised `.lor` and re-parsed by Loreline. See the
 * full rules in `loreline.translation.TranslationFormats`.
 */
class PoTranslation {

    public static function toLoreline(content:String, locale:String):String {
        final entries = parse(content);
        final buf = new Utf8Buf();
        var first = true;
        for (entry in entries) {
            if (entry.msgstr == null || entry.msgstr == "") continue;

            // Pick key: msgctxt if present, else msgid.
            final key = entry.msgctxt != null && entry.msgctxt != ""
                ? entry.msgctxt
                : entry.msgid;
            if (key == null || key == "") continue;

            if (!first) buf.add("\n");
            first = false;

            // #<key> // <source>
            buf.add("#");
            buf.add(key);
            // If msgctxt was the key, msgid is the source reference.
            // Otherwise msgid was the key, no extra reference.
            if (entry.msgctxt != null && entry.msgid != null && entry.msgid != "") {
                buf.add(" // ");
                buf.add(escapeLineForComment(entry.msgid));
            }
            buf.add("\n");

            // Translation text. Multi-line by `\n` literal: split + indent.
            // Loreline's parser treats consecutive non-blank lines as a single
            // multi-line text block, which matches PO multi-line semantics.
            buf.add(escapeLineForBody(entry.msgstr));
            buf.add("\n");
        }
        return buf.toString();
    }

    /**
     * Generates a PO file body for the given source `script`, suitable for the
     * given `locale`. If `existing` is provided, entries already present there
     * are preserved as the `msgstr` value; otherwise the `msgstr` defaults to
     * the source text (placeholder).
     */
    public static function fromScript(
        script:AstNode,
        existing:Null<Map<String, NStringLiteral>>,
        locale:String
    ):String {
        final entries = AstUtils.extractTranslatableEntries(script);
        final printer = new Printer();
        final buf = new Utf8Buf();

        // Header
        buf.add("msgid \"\"\n");
        buf.add("msgstr \"\"\n");
        buf.add("\"Content-Type: text/plain; charset=UTF-8\\n\"\n");
        buf.add("\"Language: ");
        buf.add(escapeForPoString(locale));
        buf.add("\\n\"\n");

        for (entry in entries) {
            buf.add("\n");
            final source = printer.printStringLiteralAsText(entry.str);
            final translation = (existing != null && existing.exists(entry.id))
                ? printer.printStringLiteralAsText(existing.get(entry.id))
                : source;

            buf.add("msgctxt \"");
            buf.add(escapeForPoString(entry.id));
            buf.add("\"\n");
            buf.add("msgid \"");
            buf.add(escapeForPoString(source));
            buf.add("\"\n");
            buf.add("msgstr \"");
            buf.add(escapeForPoString(translation));
            buf.add("\"\n");
        }

        return buf.toString();
    }

    /**
     * Escape a string for use inside a PO double-quoted string literal.
     * Escapes `\` → `\\` and `"` → `\"`. Other escapes (like `\n` from the
     * Loreline printer) round-trip correctly because they get re-applied by
     * the Loreline parser when the synthesized body is re-parsed.
     */
    static function escapeForPoString(s:String):String {
        var out = s.split("\\").join("\\\\");
        out = out.split("\"").join("\\\"");
        return out;
    }

    // ------------------------------------------------------------------------
    // PO parser
    // ------------------------------------------------------------------------

    static function parse(content:String):Array<PoEntry> {
        final lines = content.split("\n");
        final entries:Array<PoEntry> = [];
        var current:PoEntry = null;

        var i = 0;
        while (i < lines.length) {
            // Trim trailing \r (for CRLF files)
            var line = lines[i];
            if (line.uLength() > 0 && line.uCharCodeAt(line.uLength() - 1) == "\r".code) {
                line = line.uSubstr(0, line.uLength() - 1);
            }
            final trimmed = trimLeft(line);

            if (trimmed == "") {
                // Blank line ends current entry
                if (current != null) {
                    entries.push(current);
                    current = null;
                }
                i++;
                continue;
            }
            if (trimmed.uCharCodeAt(0) == "#".code) {
                // Comment line, skip
                i++;
                continue;
            }

            if (current == null) current = new PoEntry();

            // Parse `keyword "..."` line, then accumulate continuation lines.
            final keyword = readKeyword(trimmed);
            if (keyword == null) {
                i++;
                continue;
            }

            final firstString = readQuotedString(trimmed, keyword.uLength());
            var combined = firstString != null ? firstString : "";

            // Continuation lines: `"..."` directly under the keyword
            var j = i + 1;
            while (j < lines.length) {
                var next = lines[j];
                if (next.uLength() > 0 && next.uCharCodeAt(next.uLength() - 1) == "\r".code) {
                    next = next.uSubstr(0, next.uLength() - 1);
                }
                final nextTrim = trimLeft(next);
                if (nextTrim.uLength() == 0 || nextTrim.uCharCodeAt(0) != "\"".code) break;
                final more = readQuotedString(nextTrim, 0);
                if (more != null) combined += more;
                j++;
            }

            switch (keyword) {
                case "msgctxt": current.msgctxt = combined;
                case "msgid":   current.msgid   = combined;
                case "msgstr":  current.msgstr  = combined;
                case _: // Including msgstr[0] etc. — take msgstr[0] only.
                    if (keyword == "msgstr[0]") current.msgstr = combined;
            }
            i = j;
        }
        if (current != null) entries.push(current);
        return entries;
    }

    static function readKeyword(line:String):String {
        // Reads a keyword followed by a space or `[` (for `msgstr[0]`).
        var end = 0;
        final len = line.uLength();
        while (end < len) {
            final c = line.uCharCodeAt(end);
            if (c == " ".code || c == "\t".code) break;
            end++;
        }
        if (end == 0) return null;
        return line.uSubstr(0, end);
    }

    /**
     * Reads `"..."` starting at character offset `from` in `line`. Skips leading
     * whitespace. Returns the unescaped content, or null if not a quoted string.
     */
    static function readQuotedString(line:String, from:Int):String {
        var i = from;
        final len = line.uLength();
        // Skip whitespace
        while (i < len) {
            final c = line.uCharCodeAt(i);
            if (c != " ".code && c != "\t".code) break;
            i++;
        }
        if (i >= len || line.uCharCodeAt(i) != "\"".code) return null;
        i++; // skip opening quote

        final buf = new Utf8Buf();
        while (i < len) {
            final c = line.uCharCodeAt(i);
            if (c == "\\".code && i + 1 < len) {
                final esc = line.uCharCodeAt(i + 1);
                switch (esc) {
                    case "n".code: buf.addChar("\n".code);
                    case "r".code: buf.addChar("\r".code);
                    case "t".code: buf.addChar("\t".code);
                    case "\"".code: buf.addChar("\"".code);
                    case "\\".code: buf.addChar("\\".code);
                    case _: buf.addChar(esc);
                }
                i += 2;
            } else if (c == "\"".code) {
                return buf.toString();
            } else {
                buf.addChar(c);
                i++;
            }
        }
        // Reached end-of-line without seeing the closing `"`. The PO file is malformed.
        throw new loreline.Error("Invalid PO: unterminated quoted string");
    }

    static inline function trimLeft(s:String):String {
        var i = 0;
        final len = s.uLength();
        while (i < len) {
            final c = s.uCharCodeAt(i);
            if (c != " ".code && c != "\t".code) break;
            i++;
        }
        return i == 0 ? s : s.uSubstr(i);
    }

    /**
     * Escape a string for use as a Loreline `// ...` line comment.
     * Replaces newlines with spaces (line comments can't span lines).
     */
    static function escapeLineForComment(s:String):String {
        return s.split("\n").join(" ").split("\r").join("");
    }

    /**
     * Escape a string for use as a Loreline text body line.
     * Real newlines stay (Loreline groups consecutive non-blank lines into a
     * single multi-line text block). The `$` character is doubled to avoid
     * triggering interpolation in the synthesized `.lor` content.
     */
    static function escapeLineForBody(s:String):String {
        // Note: we intentionally do NOT escape `$` here so PO files can carry
        // Loreline interpolation syntax (`$var`, `${expr}`) intact. PO authors
        // who want a literal `$` should use `$$` in their msgstr, same rule
        // as in `.lor` source.
        return s;
    }

}

private class PoEntry {
    public var msgctxt:String;
    public var msgid:String;
    public var msgstr:String;
    public function new() {}
}
