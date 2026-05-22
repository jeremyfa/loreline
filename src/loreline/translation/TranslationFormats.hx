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
     * Each entry: short name (used by `translationFormat`) and file extension.
     * The converter for each `ext` is dispatched explicitly in `convert()` —
     * see the comment there for why we don't store function refs here.
     */
    static final formats:Array<{name:String, ext:String}> = [
        #if !loreline_no_po
        { name: "po", ext: ".po" },
        #end
        #if !loreline_no_xliff
        { name: "xliff", ext: ".xliff" },
        { name: "xliff", ext: ".xlf" },
        #end
        #if !loreline_no_csv
        { name: "csv", ext: ".csv" },
        { name: "csv", ext: ".tsv" },
        #end
    ];

    /**
     * Dispatches a file's content to its format converter by extension.
     *
     * Explicit `switch` rather than a function pointer stored in `formats`
     * so every converter has a direct call site visible to dead-code
     * elimination / AOT trim analysis. The reflective `Closure(typeof(X),
     * "toLoreline", …)` Haxe would otherwise emit on C# is invisible to
     * .NET's `PublishAot` trimmer and silently drops the converter bodies.
     */
    static function convert(ext:String, content:String, locale:String):String {
        return switch (ext) {
            #if !loreline_no_po
            case ".po": PoTranslation.toLoreline(content, locale);
            #end
            #if !loreline_no_xliff
            case ".xliff" | ".xlf": XliffTranslation.toLoreline(content, locale);
            #end
            #if !loreline_no_csv
            case ".csv": CsvTranslation.toLoreline(content, locale);
            case ".tsv": CsvTranslation.tsvToLoreline(content, locale);
            #end
            case _: throw new haxe.Exception("Unknown translation format extension: " + ext);
        }
    }

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
     *
     * Returns both the wrapped handler and an accessor for the most recent
     * converter error captured during this wrap's lifetime. When a converter
     * throws on a malformed file, the wrapper records the error (with the
     * actual file path) and falls through to the next enabled format — so a
     * broken `.fr.po` doesn't block a valid `.fr.xliff`. The caller reads
     * `lastError()` after dispatch completes to surface the failure.
     */
    public static function wrap(underlying:ImportsFileHandler, locale:String):WrappedFileHandler {
        // Fast path: no format enabled → just pass through. No overhead.
        if (!anyEnabled()) return new WrappedFileHandler(underlying, () -> null);

        var captured:Null<loreline.Error> = null;

        function tryNext(stem:String, withLocaleSuffix:Bool, index:Int, cb:(content:String)->Void):Void {
            if (index >= formats.length) {
                if (withLocaleSuffix) {
                    tryNext(stem, false, 0, cb);
                } else {
                    cb(null);
                }
                return;
            }

            final f = formats[index];
            if (enabled.get(f.name) != true) {
                tryNext(stem, withLocaleSuffix, index + 1, cb);
                return;
            }

            final candidate = withLocaleSuffix
                ? stem + "." + locale + f.ext
                : stem + f.ext;

            underlying(candidate, content -> {
                if (content != null) {
                    try {
                        cb(convert(f.ext, content, locale));
                    } catch (e:loreline.Error) {
                        // Record under this file's actual path and fall through
                        // to the next format. loadLocale promotes `lastError()`
                        // into Loreline._lastError after the dispatch loop.
                        captured = new loreline.Error('Failed to load translation file "$candidate": ' + e.message);
                        tryNext(stem, withLocaleSuffix, index + 1, cb);
                    }
                } else {
                    tryNext(stem, withLocaleSuffix, index + 1, cb);
                }
            });
        }

        final wrapped:ImportsFileHandler = (path, cb) -> {
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

                tryNext(stem, true, 0, cb);
            });
        };

        return new WrappedFileHandler(wrapped, () -> captured);
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

}

/**
 * Result of `TranslationFormats.wrap()`:
 * - `handler` is the wrapped file handler that adds alternate-format lookups.
 * - `lastError()` returns the most recent converter error captured during
 *   this wrap's lifetime (or null). Caller reads after dispatch completes.
 *
 * Defined as a class (not a typedef) because Haxe Lua wraps anonymous-struct
 * function fields in `function(_, ...) return underlying(...) end` (the `_`
 * eats an implicit `self` arg), which breaks direct function-style invocation.
 * Class fields don't get that treatment.
 */
class WrappedFileHandler {
    public final handler:loreline.ImportsFileHandler;
    public final lastError:()->Null<loreline.Error>;

    public function new(handler:loreline.ImportsFileHandler, lastError:()->Null<loreline.Error>) {
        this.handler = handler;
        this.lastError = lastError;
    }
}
