package loreline;

import haxe.io.Path;
import loreline.AstUtils;
import loreline.Imports;
import loreline.Interpreter;
import loreline.Lens;
import loreline.Lexer;
import loreline.Node.NStringLiteral;
import loreline.Parser;

using loreline.Utf8;

/**
 * The main public API for Loreline runtime.
 * Provides easy access to the core functionality for parsing and running Loreline scripts.
 */
#if js
@:expose
#end
class Loreline {

    /**
     * Parses the given text input and creates an executable `Script` instance from it.
     *
     * This is the first step in working with a Loreline script. The returned
     * `Script` object can then be passed to methods `play()` or `resume()`.
     *
     * @param input The Loreline script content as a string (`.lor` format)
     * @param filePath (optional) The file path of the input being parsed. If provided, requires `handleFile` as well.
     * @param handleFile
     *          (optional) A file handler to read imports. If that handler is asynchronous, then `parse()` method
     *          will return null and `callback` argument should be used to get the final script
     * @param callback If provided, will be called with the resulting script as argument. Mostly useful when reading file imports asynchronously
     * @return The parsed script as an AST `Script` instance (if loaded synchronously)
     * @throws loreline.Error If the script contains syntax errors or other parsing issues
     */
    public static function parse(input:String, ?filePath:String, ?handleFile:ImportsFileHandler, ?callback:(script:Script)->Void):Null<Script> {

        final lexer = new Lexer(input);
        final tokens = lexer.tokenize();

        #if loreline_debug_tokens
        for (tok in tokens) {
            trace(tok);
        }
        #end

        final lexerErrors = lexer.getErrors();
        if (lexerErrors != null && lexerErrors.length > 0) {
            throw lexerErrors[0];
        }

        var result:Script = null;

        if (filePath != null && handleFile != null) {
            // File path and file handler provided, which mean we can support
            // imports, either synchronous or asynchronous

            final imports = new Imports();
            imports.resolve(filePath, tokens, handleFile, (error) -> {
                throw error;
            },
            (hasErrors, resolvedImports) -> {

                final parser = new Parser(tokens, {
                    rootPath: filePath,
                    path: filePath,
                    imports: resolvedImports
                });

                result = parser.parse();
                result.indentSize = lexer.detectedIndentSize;
                final parseErrors = parser.getErrors();

                if (parseErrors != null && parseErrors.length > 0) {
                    throw parseErrors[0];
                }

                if (callback != null) {
                    callback(result);
                }

            });
            return result;
        }

        // No imports handling, simply parse the input
        final parser = new Parser(tokens);

        result = parser.parse();
        result.indentSize = lexer.detectedIndentSize;
        final parseErrors = parser.getErrors();

        if (parseErrors != null && parseErrors.length > 0) {
            throw parseErrors[0];
        }

        if (callback != null) {
            callback(result);
        }

        return result;
    }

    /**
     * Loads translations for a specific locale, walking the script's full import tree.
     *
     * For each file involved in the script (root + transitively imported), the
     * corresponding translation file is looked up by inserting `.<locale>` before
     * the extension (e.g. `characters.lor` → `characters.fr.lor`). Missing translation
     * files are silently skipped.
     *
     * Each translation key is stored under both:
     *   - a global key `<id>` (first occurrence wins, root file priority)
     *   - a scoped key `<source-rel-path>#<id>` (always set per file, allows override)
     *
     * The interpreter prefers the scoped key when looking up a translation.
     *
     * @param locale The locale code (e.g. "fr")
     * @param script The parsed source script (must have been parsed with a file path
     *               or `filePath` must be provided)
     * @param filePath (optional) Override where to look for translation files. If null,
     *                 defaults to `script.filePath`. Can be a `.lor`/`.lor.txt` file path
     *                 (translations sit alongside source files) or a directory path
     *                 (translations are all in that directory).
     * @param handleFile (optional) File handler for reading translation files
     * @param callback (optional) Called with the merged translations map. Required for async file handlers.
     * @return The merged translations map (synchronously, when `handleFile` is sync)
     */
    public static function loadLocale(locale:String, script:Script, ?filePath:String, ?handleFile:ImportsFileHandler, ?callback:(translations:Map<String, NStringLiteral>)->Void):Null<Map<String, NStringLiteral>> {

        if (filePath == null) {
            filePath = script.filePath;
        }
        if (filePath == null) {
            throw new Error("Cannot load locale: no filePath provided and script.filePath is null");
        }
        if (handleFile == null) {
            throw new Error("Cannot load locale: handleFile is required");
        }

        // Wrap to enable alternate translation file formats (PO, XLIFF, CSV/TSV).
        // Pass-through if no format was enabled via Loreline.translationFormat();
        // otherwise the wrap tries each enabled format as a sibling and converts
        // the first match to a synthesized .lor translation body before handing
        // it back to loadLocale.
        handleFile = loreline.translation.TranslationFormats.wrap(handleFile, locale);

        // Determine which Loreline extension we're working with for translation files.
        // By default, always ".lor" — ".lor.txt" translations are only considered when
        // built with -D loreline_lor_txt (which restores the previous behavior of
        // matching the source script's extension).
        final ext = #if loreline_lor_txt
            (script.filePath != null && Imports.endsWithLorTxt(script.filePath))
                ? '.lor.txt'
                : Imports.lorExtension(filePath);
        #else
            '.lor';
        #end

        // Determine where to look for translation files.
        // If filePath ends with .lor / .lor.txt, treat its directory as the lookup base.
        // Otherwise treat filePath as a directory (strip trailing separator if any).
        final translationsBaseDir:String = if (Imports.isLorFilePath(filePath)) {
            Path.directory(filePath);
        }
        else {
            final fpLen = filePath.uLength();
            final lastChar = fpLen > 0 ? filePath.uCharCodeAt(fpLen - 1) : 0;
            (lastChar == '/'.code || lastChar == '\\'.code)
                ? filePath.uSubstr(0, fpLen - 1)
                : filePath;
        };

        // Source script's own root path is needed to compute relative paths
        // (the scoped keys reference paths relative to script.filePath, not filePath).
        final sourceRootPath = script.filePath;

        // Build parallel arrays of source-relative paths and translation absolute paths.
        // Root file:
        final relativePaths:Array<String> = [];
        final translationPaths:Array<String> = [];

        if (sourceRootPath != null) {
            final rootBaseName = Path.withoutDirectory(sourceRootPath);
            final rootStem = Imports.stripLorExtension(rootBaseName);
            final rootTransName = rootStem + '.' + locale + ext;
            relativePaths.push('.');
            translationPaths.push(Path.normalize(Path.join([translationsBaseDir, rootTransName])));
        }

        // Imported files
        if (sourceRootPath != null) {
            final lens = new Lens(script);
            final sourceRootDir = Path.directory(sourceRootPath);
            final importedAbsPaths = lens.getImportedPaths(sourceRootPath);
            for (importAbsPath in importedAbsPaths) {
                final importRelPath = relativePath(sourceRootDir, importAbsPath);
                final importStem = Imports.stripLorExtension(importRelPath);
                final importTransRelPath = importStem + '.' + locale + ext;
                relativePaths.push(Imports.stripLorExtension(Path.normalize(importRelPath)));
                translationPaths.push(Path.normalize(Path.join([translationsBaseDir, importTransRelPath])));
            }
        }

        final result:Map<String, NStringLiteral> = new Map();
        var pending = relativePaths.length;
        var allProcessed = false;

        // No-op file handler for translation files (they shouldn't import anything).
        final noopHandle:ImportsFileHandler = (path, cb) -> cb(null);

        inline function dispatchResult() {
            if (callback != null) callback(result);
        }

        for (i in 0...relativePaths.length) {
            final relPath = relativePaths[i];
            final transPath = translationPaths[i];
            handleFile(transPath, content -> {
                pending--;
                if (content != null) {
                    try {
                        final transScript = parse(content, transPath, noopHandle);
                        if (transScript != null) {
                            final translations = AstUtils.extractTranslations(transScript);
                            for (id => str in translations) {
                                // Scoped per file. The interpreter walks the
                                // import ancestor chain at lookup time, so a
                                // translation in an ancestor's file naturally
                                // applies to descendants that don't have their
                                // own translation for the same key.
                                result.set(relPath + '#' + id, str);
                            }
                        }
                    } catch (e:Any) {
                        // Translation file parse error: skip this file silently to keep
                        // the loadLocale resilient. The caller still gets whatever loaded.
                    }
                }
                if (pending == 0 && allProcessed) {
                    dispatchResult();
                }
            });
        }

        allProcessed = true;
        if (pending == 0) {
            dispatchResult();
        }

        return result;
    }

    /**
     * Computes a relative path from `fromDir` to `toPath`, both expected to be
     * normalized absolute paths. Returns a forward-slash-separated relative path.
     */
    static function relativePath(fromDir:String, toPath:String):String {
        final from = Path.normalize(fromDir);
        final to = Path.normalize(toPath);
        final fromParts = from.split('/');
        final toParts = to.split('/');
        var commonLen = 0;
        while (commonLen < fromParts.length && commonLen < toParts.length && fromParts[commonLen] == toParts[commonLen]) {
            commonLen++;
        }
        final upCount = fromParts.length - commonLen;
        final result:Array<String> = [];
        for (i in 0...upCount) result.push('..');
        for (i in commonLen...toParts.length) result.push(toParts[i]);
        if (result.length == 0) return '.';
        return result.join('/');
    }

    /**
     * Starts playing a Loreline script from the beginning or a specific beat.
     *
     * This function takes care of initializing the interpreter and starting execution
     * immediately. You'll need to provide handlers for dialogues, choices, and
     * script completion.
     *
     * @param script The parsed script (result from `parse()`)
     * @param handleDialogue Function called when dialogue text should be displayed
     * @param handleChoice Function called when player needs to make a choice
     * @param handleFinish Function called when script execution completes
     * @param beatName Optional name of a specific beat to start from (defaults to first beat)
     * @param options Additional options
     * @return The interpreter instance that is running the script
     */
    public static function play(
        script:Script,
        handleDialogue:DialogueHandler,
        handleChoice:ChoiceHandler,
        handleFinish:FinishHandler,
        ?beatName:String,
        ?options:InterpreterOptions
    ):Interpreter {

        final interpreter = new Interpreter(
            script,
            handleDialogue,
            handleChoice,
            handleFinish,
            options
        );

        interpreter.start(beatName);

        return interpreter;
    }

    /**
     * Resumes a previously saved Loreline script from its saved state.
     *
     * This allows you to continue a story from the exact point where it was saved,
     * restoring all state variables, choices, and player progress.
     *
     * @param script The parsed script (result from `parse()`)
     * @param handleDialogue Function called when dialogue text should be displayed
     * @param handleChoice Function called when player needs to make a choice
     * @param handleFinish Function called when script execution completes
     * @param saveData The saved game data (typically from `interpreter.save()`)
     * @param beatName Optional beat name to override where to resume from
     * @param functions Optional map of custom functions to make available in the script
     * @return The interpreter instance that is running the script
     */
    public static function resume(
        script:Script,
        handleDialogue:DialogueHandler,
        handleChoice:ChoiceHandler,
        handleFinish:FinishHandler,
        saveData:SaveData,
        ?beatName:String,
        ?options:InterpreterOptions
    ):Interpreter {

        final interpreter = new Interpreter(
            script,
            handleDialogue,
            handleChoice,
            handleFinish,
            options
        );

        interpreter.restore(saveData);

        if (beatName != null) {
            interpreter.start(beatName);
        }
        else {
            interpreter.resume();
        }

        return interpreter;
    }

    /**
     * Extracts translations from a parsed translation script.
     *
     * Given a translation file parsed with `parse()`, this returns a translations map
     * that can be passed as `options.translations` to `play()` or `resume()`.
     *
     * @param script The parsed translation script (result from `parse()` on a `.XX.lor` file)
     * @return A translations map to pass as `InterpreterOptions.translations`
     */
    public static function extractTranslations(script:Script):Map<String, NStringLiteral> {
        return AstUtils.extractTranslations(script);
    }

    /**
     * Enable or disable runtime support for an alternate translation file format.
     *
     * By default, only `.<locale>.lor` files are tried by `loadLocale`. Call this
     * to opt in to additional formats. Known names:
     *   - `"po"`   — GNU gettext PO (`.po`)
     *   - `"xliff"` — XLIFF 1.2 / 2.x (`.xliff`, `.xlf`)
     *   - `"csv"`  — CSV / TSV (`.csv`, `.tsv`)
     *
     * Unknown names are accepted silently (forward-compat for future formats).
     *
     * @param name The format identifier (see above)
     * @param enabled True to enable the format, false to disable
     */
    public static function translationFormat(name:String, enabled:Bool):Void {
        loreline.translation.TranslationFormats.translationFormat(name, enabled);
    }

    /**
     * Generates a translation file body for the given source `script`.
     *
     * Each translatable string in the source that has an `#id` marker
     * becomes one entry in the output. If `existing` is provided
     * (typically the result of `extractTranslations` on a previously-saved
     * translation file), entries already filled in there are preserved
     * verbatim; otherwise each entry seeds with the source text.
     *
     * Companion to the `loreline translate ... --lang xx` CLI command.
     *
     * @param script The parsed source script
     * @param existing (optional) Existing translations to preserve when merging
     * @return The translation file body as a string, ready to write to disk
     */
    public static function generateTranslationFile(script:Script, ?existing:Map<String, NStringLiteral>, ?format:String, ?locale:String):String {
        if (format == null || format == "lor") {
            return AstUtils.generateTranslationFile(script, existing, new Printer());
        }
        if (locale == null || locale == "") {
            throw new Error("A locale is required when generating a translation file in format '" + format + "'");
        }
        return switch (format) {
            case "po":    loreline.translation.PoTranslation.fromScript(script, existing, locale);
            case "xliff": loreline.translation.XliffTranslation.fromScript(script, existing, locale);
            case "csv":   loreline.translation.CsvTranslation.fromScript(script, existing, locale);
            case "tsv":   loreline.translation.CsvTranslation.tsvFromScript(script, existing, locale);
            case _: throw new Error("Unknown translation file format: '" + format + "'");
        }
    }

    /**
     * Inserts `#id` markers after every translatable string in `content`
     * that doesn't already have one. `script` must be the AST parsed
     * from the same `content`. Returns the rewritten content.
     *
     * When `includeImports` is false, imported scripts are skipped — their
     * byte offsets refer to other files' contents and would corrupt
     * `content`. Tooling that walks imports externally should pass false.
     *
     * When `reservedIds` is provided, it's used (and mutated) as the
     * shared existing-IDs set across calls — useful for coordinating
     * ID generation across multiple per-file invocations so that file
     * B's auto-IDs avoid every ID already in file A. Existing IDs from
     * this file's hash comments are added to the map; newly-generated
     * IDs are added too.
     *
     * Equivalent to the `--auto-ids` flag of the `loreline translate` CLI.
     */
    public static function insertLocalizationKeys(content:String, script:Script, includeImports:Bool = true, ?reservedIds:Map<String, Bool>):String {
        return AstUtils.insertLocalizationKeys(content, script, includeImports, reservedIds);
    }

    /**
     * Lex-only scan of `content` for every hash-comment identifier
     * (`#xxxx`). Cheap compared to a full parse — runs the lexer over
     * the text and pulls out every `CommentHash` payload. Use to build
     * project-wide reserved-IDs registries.
     *
     * Fills and returns `out` (or a fresh map when `out` is null).
     */
    public static function collectHashIds(content:String, ?out:Map<String, Bool>):Map<String, Bool> {
        return AstUtils.collectHashIds(content, out);
    }

    /**
     * Strips every `#id` marker emitted by `insertLocalizationKeys` (or
     * authored manually). The inverse operation. Returns the rewritten
     * content. Equivalent to the `--clear` flag of the `loreline translate` CLI.
     */
    public static function removeLocalizationKeys(content:String, script:Script):String {
        return AstUtils.removeLocalizationKeys(content, script);
    }

    /**
     * Returns every `#id`-tagged translatable string in `script` paired
     * with its id. Strings WITHOUT an `#id` marker are filtered out — use
     * `hasUntaggedTranslatableStrings` to detect those.
     */
    public static function extractTranslatableEntries(script:Script):Array<{id:String, str:NStringLiteral}> {
        return AstUtils.extractTranslatableEntries(script);
    }

    /**
     * Returns true iff `script` contains at least one translatable
     * string (text statement, dialogue, or choice option) that has no
     * `#id` hash comment. Non-mutating — purely an AST inspection.
     * Used by tooling to gate "add tags?" prompts before generating
     * translation files.
     */
    public static function hasUntaggedTranslatableStrings(script:Script):Bool {
        return AstUtils.hasUntaggedTranslatableStrings(script);
    }

    /**
     * Prints a parsed script back into Loreline source code.
     *
     * @param script The parsed script (result from `parse()`)
     * @param indent The indentation string to use (defaults to two spaces)
     * @param newline The newline string to use (defaults to "\n")
     * @return The printed source code as a string
     */
    public static function print(script:Script, ?indent:String, ?newline:String):String {
        final printer = new Printer(indent ?? "  ", newline ?? "\n");
        return printer.print(script);
    }

    /**
     * Ticks pending wait() timers. Call this from your game loop every frame.
     * The first call enables non-blocking deferred mode for wait() on sys targets;
     * before this is called, wait() falls back to blocking Sys.sleep() (correct for CLI tools).
     * @param delta Time elapsed since last frame in seconds
     */
    public static function update(delta:Float):Void {
        Timer.update(delta);
    }

}