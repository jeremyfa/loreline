package loreline.translation;

import loreline.Imports;

using StringTools;
using loreline.Utf8;

/**
 * Registry + wrapper for pluggable translation file formats.
 *
 * Loreline natively loads translations from `.<locale>.lor` / `.<locale>.lor.txt`
 * files. This class extends `Loreline.loadLocale`'s file lookup so that, when
 * the `.lor` translation file doesn't exist, the runtime can also look for
 * sibling files in other common formats (PO, XLIFF, CSV/TSV) and convert
 * them on the fly to the Loreline translation format.
 *
 * Each format must be **opted in** at runtime via `translationFormat(name, true)`.
 * By default, no alternate format is tried — the behaviour is identical to
 * the original `.lor`-only setup, so the file handler doesn't get spammed
 * with requests for formats the developer doesn't use.
 *
 * Format families can also be removed entirely at compile time with
 * `-D loreline_no_po`, `-D loreline_no_xliff`, `-D loreline_no_csv`. The
 * corresponding converter classes are then eliminated by DCE.
 *
 * ## Translation strings must be valid Loreline body content
 *
 * Every original / translation string in every supported format
 * (msgid/msgstr in PO, source/target in XLIFF, source/locale columns in
 * CSV/TSV) is written as-is into a synthesised `.lor` body that is then
 * re-parsed by the standard Loreline parser. The string therefore has to
 * be **valid Loreline body content**, following the same rules that apply
 * to text in a `.lor` source file:
 *
 *  - `$var` and `${expr}` perform interpolation; use `$$` for a literal `$`.
 *  - `<tag>` / `</tag>` are tag markup; use `\<` for a literal `<`.
 *  - `\n`, `\t`, `\r`, `\\` are the usual escape sequences for newline,
 *    tab, carriage return and backslash.
 *  - Bare `"` characters are allowed and pass through as literal quotes.
 *
 * Translators who want to use these features just write the corresponding
 * Loreline syntax in their localised string and it round-trips intact.
 * Translators who want literal characters must apply the same escapes they
 * would in the original `.lor`.
 */
class TranslationFormats {

    /**
     * Registered formats. Order is the lookup priority.
     * Each entry: short name (used by `translationFormat`), file extension,
     * and the converter that turns the format's file content into a Loreline
     * translation file body (the same shape as a `.<locale>.lor` file).
     */
    static final formats:Array<{name:String, ext:String, convert:(content:String, locale:String)->String}> = [
        #if !loreline_no_po
        { name: "po", ext: ".po", convert: PoTranslation.toLoreline },
        #end
        #if !loreline_no_xliff
        { name: "xliff", ext: ".xliff", convert: XliffTranslation.toLoreline },
        { name: "xliff", ext: ".xlf",   convert: XliffTranslation.toLoreline },
        #end
        #if !loreline_no_csv
        { name: "csv", ext: ".csv", convert: CsvTranslation.toLoreline },
        { name: "csv", ext: ".tsv", convert: CsvTranslation.tsvToLoreline },
        #end
    ];

    /**
     * Per-format enabled state. Empty by default → all formats disabled.
     * The user opts in via `translationFormat(name, true)`.
     */
    static final enabled:Map<String, Bool> = new Map();

    /**
     * Enable or disable runtime support for a translation format.
     *
     * Known names: "po", "xliff", "csv". Unknown names are accepted silently
     * (forward-compat for new formats added later).
     */
    public static function translationFormat(name:String, value:Bool):Void {
        enabled.set(name, value);
    }

    /**
     * Returns true if at least one format is currently enabled.
     */
    static function anyEnabled():Bool {
        for (f in formats) {
            if (enabled.get(f.name) == true) return true;
        }
        return false;
    }

    /**
     * Wraps a file handler so that, when asked for a `.lor`/`.lor.txt`
     * translation file that doesn't exist, the wrapper tries each enabled
     * alternate format (`.po`, `.xliff`/`.xlf`, `.csv`/`.tsv`) as a sibling,
     * converts the first match to a synthesized `.lor` translation file
     * content, and hands that back to the caller.
     *
     * Two passes:
     *   1. With locale suffix: `<stem>.<locale><ext>`
     *   2. Without locale suffix: `<stem><ext>` — only useful for formats
     *      that self-identify their locale (XLIFF target-language, CSV
     *      column header) or are mono-locale by convention (PO).
     *
     * `underlying` is assumed non-null (loadLocale validates this before
     * calling wrap).
     */
    public static function wrap(underlying:ImportsFileHandler, locale:String):ImportsFileHandler {
        // Fast path: no format enabled → just pass through. No overhead.
        if (!anyEnabled()) return underlying;

        return (path, cb) -> {
            underlying(path, content -> {
                if (content != null) {
                    cb(content);
                    return;
                }
                // Only fall back for `.lor` requests (and `.lor.txt` when built
                // with -D loreline_lor_txt). Other file requests (script imports,
                // user-fetched files) are left alone.
                final isLorPath = #if loreline_lor_txt
                    Imports.isLorFilePath(path);
                #else
                    Imports.endsWithLor(path);
                #end
                if (!isLorPath) {
                    cb(null);
                    return;
                }
                // Compute the bare stem: strip the .lor extension (and .lor.txt
                // when the flag enables it), then strip the `.<locale>` suffix
                // if present.
                final withoutLorExt = #if loreline_lor_txt
                    Imports.stripLorExtension(path);
                #else
                    path.uSubstr(0, path.uLength() - 4); // strip ".lor"
                #end
                final localeSuffix = "." + locale;
                final stem = endsWith(withoutLorExt, localeSuffix)
                    ? withoutLorExt.uSubstr(0, withoutLorExt.uLength() - localeSuffix.uLength())
                    : withoutLorExt;

                tryNext(underlying, stem, locale, true, 0, cb);
            });
        };
    }

    /**
     * UTF-safe suffix check. Uses byte-level comparison via uSubstr which is
     * safe because the suffix is ASCII (`.<locale>` with locale being an
     * ASCII code like "fr", "en-US", etc.).
     */
    static inline function endsWith(s:String, suffix:String):Bool {
        final sLen = s.uLength();
        final suffixLen = suffix.uLength();
        if (suffixLen > sLen) return false;
        return s.uSubstr(sLen - suffixLen, suffixLen) == suffix;
    }

    static function tryNext(
        underlying:ImportsFileHandler,
        stem:String,
        locale:String,
        withLocaleSuffix:Bool,
        index:Int,
        cb:(content:String)->Void
    ):Void {
        if (index >= formats.length) {
            if (withLocaleSuffix) {
                // Done with the suffixed pass; switch to the non-suffixed pass
                // for formats that can self-identify their locale.
                tryNext(underlying, stem, locale, false, 0, cb);
            } else {
                // Exhausted both passes.
                cb(null);
            }
            return;
        }

        final f = formats[index];
        if (enabled.get(f.name) != true) {
            tryNext(underlying, stem, locale, withLocaleSuffix, index + 1, cb);
            return;
        }

        final candidate = withLocaleSuffix
            ? stem + "." + locale + f.ext
            : stem + f.ext;

        underlying(candidate, content -> {
            if (content != null) {
                cb(f.convert(content, locale));
            } else {
                tryNext(underlying, stem, locale, withLocaleSuffix, index + 1, cb);
            }
        });
    }

}
