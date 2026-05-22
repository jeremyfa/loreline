package loreline.translation;

import loreline.AstUtils;
import loreline.Node;
import loreline.Printer;

using loreline.Utf8;

/**
 * Converts CSV/TSV file content into a Loreline translation file body.
 *
 * Requires a header row. Recognized columns (case-insensitive):
 *   - "key" (required, used as `#key` in the synthesized .lor)
 *   - "source" / "en" / "original" (optional, used as `// <source>` reference)
 *   - the column whose header equals `locale` = the translation
 *     → a single multi-locale CSV (`key, source, en, fr, es, de`) can serve
 *     every locale.
 *
 * Fallback: if no column header matches `locale`, the last column is used as
 * the translation (legacy 2-column shape `key, value`).
 *
 * Quoting follows RFC 4180: values containing the separator, quotes, or newlines
 * must be wrapped in double-quotes; literal quotes are doubled (`""`).
 *
 * **The locale-column value must be valid Loreline body content** — it is
 * written verbatim into the synthesised `.lor` and re-parsed by Loreline.
 * See the full rules in `loreline.translation.TranslationFormats`.
 */
class CsvTranslation {

    public static function toLoreline(content:String, locale:String):String {
        return convert(content, ",".code, locale);
    }

    public static function tsvToLoreline(content:String, locale:String):String {
        return convert(content, "\t".code, locale);
    }

    static function convert(content:String, sep:Int, locale:String):String {
        final rows = parseRows(content, sep);
        if (rows.length < 1) throw new loreline.Error("Invalid CSV: header row required");
        if (rows.length < 2) return ""; // valid header but no data rows = empty translation set

        final header = rows[0];
        final keyCol = findColumn(header, ["key"]);
        if (keyCol < 0) throw new loreline.Error("Invalid CSV: 'key' column not found in header");

        final sourceCol = findColumn(header, ["source", "en", "original"]);

        // Find the translation column: match the locale (case-insensitive,
        // primary subtag tolerated, e.g. "fr" matches "fr-FR").
        var transCol = findLocaleColumn(header, locale);
        if (transCol < 0) {
            // Fallback to the last column (2-column shape: key, value).
            // Skip if the last column is the key itself (single-column file).
            if (header.length >= 2) transCol = header.length - 1;
            else return "";
        }

        final buf = new Utf8Buf();
        var first = true;
        for (i in 1...rows.length) {
            final row = rows[i];
            if (row.length <= keyCol) continue;
            final key = row[keyCol];
            if (key == null || key == "") continue;
            if (row.length <= transCol) continue;
            final translation = row[transCol];
            if (translation == null || translation == "") continue;

            final src = (sourceCol >= 0 && row.length > sourceCol) ? row[sourceCol] : null;

            if (!first) buf.add("\n");
            first = false;

            buf.add("#");
            buf.add(key);
            if (src != null && src != "") {
                buf.add(" // ");
                buf.add(escapeLineForComment(src));
            }
            buf.add("\n");
            buf.add(translation);
            buf.add("\n");
        }
        return buf.toString();
    }

    /**
     * Generates a CSV file body for the given source `script` and `locale`.
     * The output has three columns: `key`, `source`, `<locale>`. If `existing`
     * is provided, entries already present there are preserved as the
     * translation value; otherwise the translation defaults to the source text.
     */
    public static function fromScript(
        script:AstNode,
        existing:Null<Map<String, NStringLiteral>>,
        locale:String
    ):String {
        return generate(script, existing, locale, ",".code);
    }

    public static function tsvFromScript(
        script:AstNode,
        existing:Null<Map<String, NStringLiteral>>,
        locale:String
    ):String {
        return generate(script, existing, locale, "\t".code);
    }

    static function generate(
        script:AstNode,
        existing:Null<Map<String, NStringLiteral>>,
        locale:String,
        sep:Int
    ):String {
        final entries = AstUtils.extractTranslatableEntries(script);
        final printer = new Printer();
        final buf = new Utf8Buf();
        final sepStr = String.fromCharCode(sep);

        // Header
        buf.add(escapeForCsvField("key", sep));
        buf.add(sepStr);
        buf.add(escapeForCsvField("source", sep));
        buf.add(sepStr);
        buf.add(escapeForCsvField(locale, sep));
        buf.add("\n");

        for (entry in entries) {
            final source = printer.printStringLiteralAsText(entry.str);
            final translation = (existing != null && existing.exists(entry.id))
                ? printer.printStringLiteralAsText(existing.get(entry.id))
                : source;

            buf.add(escapeForCsvField(entry.id, sep));
            buf.add(sepStr);
            buf.add(escapeForCsvField(source, sep));
            buf.add(sepStr);
            buf.add(escapeForCsvField(translation, sep));
            buf.add("\n");
        }

        return buf.toString();
    }

    /**
     * Escape a field for CSV/TSV output per RFC 4180. Wraps the value in
     * double-quotes if it contains the separator, a quote, or a newline; and
     * doubles any literal `"` to `""` inside the wrapped value.
     */
    static function escapeForCsvField(s:String, sep:Int):String {
        var needsQuoting = false;
        for (i in 0...s.uLength()) {
            final c = s.uCharCodeAt(i);
            if (c == sep || c == "\"".code || c == "\n".code || c == "\r".code) {
                needsQuoting = true;
                break;
            }
        }
        if (!needsQuoting) return s;
        return "\"" + s.split("\"").join("\"\"") + "\"";
    }

    static function findColumn(header:Array<String>, names:Array<String>):Int {
        for (i in 0...header.length) {
            final h = header[i].toLowerCase();
            for (n in names) {
                if (h == n) return i;
            }
        }
        return -1;
    }

    static function findLocaleColumn(header:Array<String>, locale:String):Int {
        final locLow = locale.toLowerCase();
        // Exact match first
        for (i in 0...header.length) {
            if (header[i].toLowerCase() == locLow) return i;
        }
        // Primary subtag match
        final primary = primarySubtag(locLow);
        for (i in 0...header.length) {
            if (primarySubtag(header[i].toLowerCase()) == primary) return i;
        }
        return -1;
    }

    static inline function primarySubtag(s:String):String {
        final dash = s.uIndexOf("-");
        if (dash < 0) return s;
        return s.uSubstr(0, dash);
    }

    // ------------------------------------------------------------------------
    // CSV parser (RFC 4180 compliant)
    // ------------------------------------------------------------------------

    static function parseRows(content:String, sep:Int):Array<Array<String>> {
        final rows:Array<Array<String>> = [];
        var row:Array<String> = [];
        var field = new Utf8Buf();
        var inQuotes = false;
        var i = 0;
        final len = content.uLength();

        while (i < len) {
            final c = content.uCharCodeAt(i);
            if (inQuotes) {
                if (c == "\"".code) {
                    if (i + 1 < len && content.uCharCodeAt(i + 1) == "\"".code) {
                        // Escaped quote
                        field.addChar("\"".code);
                        i += 2;
                    } else {
                        inQuotes = false;
                        i++;
                    }
                } else {
                    field.addChar(c);
                    i++;
                }
            } else {
                if (c == "\"".code) {
                    inQuotes = true;
                    i++;
                } else if (c == sep) {
                    row.push(field.toString());
                    field = new Utf8Buf();
                    i++;
                } else if (c == "\n".code || c == "\r".code) {
                    row.push(field.toString());
                    field = new Utf8Buf();
                    // Only push non-empty rows (skip blank lines)
                    if (row.length > 1 || (row.length == 1 && row[0] != "")) {
                        rows.push(row);
                    }
                    row = [];
                    // Handle CRLF as a single line ending
                    if (c == "\r".code && i + 1 < len && content.uCharCodeAt(i + 1) == "\n".code) {
                        i += 2;
                    } else {
                        i++;
                    }
                } else {
                    field.addChar(c);
                    i++;
                }
            }
        }
        // Tail row (no trailing newline)
        if (field.toString() != "" || row.length > 0) {
            row.push(field.toString());
            if (row.length > 1 || (row.length == 1 && row[0] != "")) {
                rows.push(row);
            }
        }
        return rows;
    }

    static inline function escapeLineForComment(s:String):String {
        return s.split("\n").join(" ").split("\r").join("");
    }

}
