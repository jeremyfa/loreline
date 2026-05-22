package loreline.translation;

import haxe.xml.Parser as XmlParser;
import loreline.AstUtils;
import loreline.Node;
import loreline.Printer;

using loreline.Utf8;

/**
 * Converts XLIFF (1.2 or 2.x) file content into a Loreline translation file body.
 *
 * XLIFF 1.2 layout:
 *   <xliff version="1.2">
 *     <file source-language="en" target-language="fr">
 *       <body>
 *         <trans-unit id="intro">
 *           <source>Welcome to the cafe.</source>
 *           <target>Bienvenue dans le café.</target>
 *         </trans-unit>
 *       </body>
 *     </file>
 *   </xliff>
 *
 * XLIFF 2.x layout:
 *   <xliff version="2.0" srcLang="en" trgLang="fr">
 *     <file id="...">
 *       <unit id="intro">
 *         <segment>
 *           <source>Welcome to the cafe.</source>
 *           <target>Bienvenue dans le café.</target>
 *         </segment>
 *       </unit>
 *     </file>
 *   </xliff>
 *
 * Locale filter:
 *   - 1.2: only `<file target-language="<locale>">` is converted
 *   - 2.x: the root `<xliff trgLang="<locale>">` must match
 *   - If no target-language attribute is present anywhere, we take everything
 *     (the file is assumed to be in the requested locale).
 *
 * Empty/missing `<target>` → entry skipped.
 *
 * **`<target>` must be valid Loreline body content** — its text is written
 * verbatim into the synthesised `.lor` and re-parsed by Loreline. See the
 * full rules in `loreline.translation.TranslationFormats`.
 */
class XliffTranslation {

    public static function toLoreline(content:String, locale:String):String {
        var root:Xml;
        try {
            root = XmlParser.parse(content);
        } catch (e:Dynamic) {
            throw new loreline.Error("Invalid XLIFF: " + Std.string(e));
        }

        // Find the <xliff> element (may be wrapped by the document node).
        var xliff:Xml = null;
        for (child in root) {
            if (child.nodeType == Element && child.nodeName == "xliff") {
                xliff = child;
                break;
            }
        }
        if (xliff == null) throw new loreline.Error("Invalid XLIFF: missing <xliff> root element");

        // Determine version: 2.x has srcLang/trgLang at xliff level,
        // 1.2 puts target-language at file level.
        final xliffTrgLang = xliff.exists("trgLang") ? xliff.get("trgLang") : null;
        final is2x = xliffTrgLang != null;

        // For 2.x, the trgLang must match the requested locale.
        if (is2x && !localeMatches(xliffTrgLang, locale)) return "";

        final buf = new Utf8Buf();
        var first = true;

        for (file in xliff.elementsNamed("file")) {
            if (!is2x) {
                final fileTrgLang = file.exists("target-language")
                    ? file.get("target-language")
                    : null;
                // 1.2 with target-language attribute: must match locale
                if (fileTrgLang != null && !localeMatches(fileTrgLang, locale)) continue;
            }

            if (is2x) {
                // 2.x: <file>/<unit>/<segment>/<source>/<target>
                for (unit in file.elementsNamed("unit")) {
                    if (!unit.exists("id")) continue;
                    final id = unit.get("id");
                    final segs = [for (s in unit.elementsNamed("segment")) s];
                    if (segs.length == 0) continue;
                    final sourceParts = [];
                    final targetParts = [];
                    for (seg in segs) {
                        final s = innerText(firstChildElement(seg, "source"));
                        final t = innerText(firstChildElement(seg, "target"));
                        if (s != null) sourceParts.push(s);
                        if (t != null) targetParts.push(t);
                    }
                    final src = sourceParts.join("");
                    final tgt = targetParts.join("");
                    if (tgt == "") continue;
                    if (!first) buf.add("\n");
                    first = false;
                    writeEntry(buf, id, src, tgt);
                }
            } else {
                // 1.2: <file>/<body>/<trans-unit>/<source|target>
                final body = firstChildElement(file, "body");
                if (body == null) continue;
                for (unit in body.elementsNamed("trans-unit")) {
                    if (!unit.exists("id")) continue;
                    final id = unit.get("id");
                    final src = innerText(firstChildElement(unit, "source"));
                    final tgt = innerText(firstChildElement(unit, "target"));
                    if (tgt == null || tgt == "") continue;
                    if (!first) buf.add("\n");
                    first = false;
                    writeEntry(buf, id, src != null ? src : "", tgt);
                }
            }
        }

        return buf.toString();
    }

    /**
     * Matches the file's target-language against the requested locale.
     * Accepts an exact match OR a primary-language match
     * (e.g. file "fr-FR" matches request "fr", and vice versa).
     */
    static function localeMatches(fileLocale:String, requested:String):Bool {
        if (fileLocale == requested) return true;
        final fileLow = fileLocale.toLowerCase();
        final reqLow = requested.toLowerCase();
        if (fileLow == reqLow) return true;
        // Primary subtag match: "fr-FR" / "fr"
        final filePrimary = primarySubtag(fileLow);
        final reqPrimary = primarySubtag(reqLow);
        return filePrimary == reqPrimary;
    }

    static inline function primarySubtag(s:String):String {
        final dash = s.uIndexOf("-");
        if (dash < 0) return s;
        return s.uSubstr(0, dash);
    }

    static function firstChildElement(parent:Xml, name:String):Xml {
        for (c in parent) {
            if (c.nodeType == Element && c.nodeName == name) return c;
        }
        return null;
    }

    static function innerText(node:Xml):String {
        if (node == null) return null;
        final buf = new StringBuf();
        for (c in node) {
            switch (c.nodeType) {
                case PCData: buf.add(c.nodeValue);
                case CData: buf.add(c.nodeValue);
                case Element: buf.add(innerText(c));
                case _: // ignore comments, etc.
            }
        }
        return buf.toString();
    }

    /**
     * Generates an XLIFF 1.2 file body for the given source `script` and
     * `locale`. If `existing` is provided, entries already present there are
     * preserved as the `<target>` value; otherwise the `<target>` defaults to
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

        buf.add("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        buf.add("<xliff version=\"1.2\" xmlns=\"urn:oasis:names:tc:xliff:document:1.2\">\n");
        buf.add("  <file source-language=\"en\" target-language=\"");
        buf.add(escapeForXmlAttr(locale));
        buf.add("\" datatype=\"plaintext\">\n");
        buf.add("    <body>\n");

        for (entry in entries) {
            final source = printer.printStringLiteralAsText(entry.str);
            final translation = (existing != null && existing.exists(entry.id))
                ? printer.printStringLiteralAsText(existing.get(entry.id))
                : source;

            buf.add("      <trans-unit id=\"");
            buf.add(escapeForXmlAttr(entry.id));
            buf.add("\">\n");
            buf.add("        <source>");
            buf.add(escapeForXmlText(source));
            buf.add("</source>\n");
            buf.add("        <target>");
            buf.add(escapeForXmlText(translation));
            buf.add("</target>\n");
            buf.add("      </trans-unit>\n");
        }

        buf.add("    </body>\n");
        buf.add("  </file>\n");
        buf.add("</xliff>\n");

        return buf.toString();
    }

    static function escapeForXmlText(s:String):String {
        var out = s.split("&").join("&amp;");
        out = out.split("<").join("&lt;");
        out = out.split(">").join("&gt;");
        return out;
    }

    static function escapeForXmlAttr(s:String):String {
        var out = escapeForXmlText(s);
        out = out.split("\"").join("&quot;");
        return out;
    }

    static function writeEntry(buf:Utf8Buf, id:String, src:String, tgt:String):Void {
        buf.add("#");
        buf.add(id);
        if (src != null && src != "") {
            buf.add(" // ");
            buf.add(escapeLineForComment(src));
        }
        buf.add("\n");
        buf.add(tgt);
        buf.add("\n");
    }

    static inline function escapeLineForComment(s:String):String {
        return s.split("\n").join(" ").split("\r").join("");
    }

}
