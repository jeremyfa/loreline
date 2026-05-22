package loreline;

/**
 * The main public API for Loreline runtime on JVM.
 * Provides easy access to the core functionality for parsing and running Loreline scripts.
 */
public final class Loreline {

    private Loreline() {}

    /**
     * Parses the given text input and creates a Script instance.
     *
     * @param input the Loreline script content as a string
     * @return the parsed script
     */
    public static Script parse(String input) {
        return parse(input, null, null);
    }

    /**
     * Parses the given text input with file import support.
     *
     * @param input the Loreline script content as a string
     * @param filePath the file path of the input being parsed
     * @param handleFile a file handler to read imports
     * @return the parsed script
     */
    public static Script parse(String input, String filePath, ImportsFileHandler handleFile) {
        loreline.internal.jvm.Function fileHandlerBridge = null;
        if (handleFile != null) {
            fileHandlerBridge = new ImportsFileHandlerBridge(handleFile);
        }

        loreline.runtime.Script runtimeScript =
            RuntimeBridge.parse(input, filePath, fileHandlerBridge, null);
        return runtimeScript != null ? new Script(runtimeScript) : null;
    }

    /**
     * Starts playing a Loreline script from the beginning or a specific beat.
     *
     * @param script the parsed script
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     * @return the interpreter instance
     */
    public static Interpreter play(Script script, DialogueHandler handleDialogue,
                                   ChoiceHandler handleChoice, FinishHandler handleFinish) {
        return play(script, handleDialogue, handleChoice, handleFinish, null, null);
    }

    /**
     * Starts playing a Loreline script from a specific beat with options.
     *
     * @param script the parsed script
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     * @param beatName optional name of a specific beat to start from
     * @param options additional options
     * @return the interpreter instance
     */
    public static Interpreter play(Script script, DialogueHandler handleDialogue,
                                   ChoiceHandler handleChoice, FinishHandler handleFinish,
                                   String beatName, InterpreterOptions options) {
        Interpreter interpreter = new Interpreter(script, handleDialogue, handleChoice,
                                                  handleFinish, options);
        interpreter.start(beatName);
        return interpreter;
    }

    /**
     * Resumes a previously saved Loreline script.
     *
     * @param script the parsed script
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     * @param saveData the saved game data (JSON string from interpreter.save())
     * @return the interpreter instance
     */
    public static Interpreter resume(Script script, DialogueHandler handleDialogue,
                                     ChoiceHandler handleChoice, FinishHandler handleFinish,
                                     String saveData) {
        return resume(script, handleDialogue, handleChoice, handleFinish, saveData, null, null);
    }

    /**
     * Resumes a previously saved Loreline script with options.
     *
     * @param script the parsed script
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     * @param saveData the saved game data (JSON string from interpreter.save())
     * @param beatName optional beat name to override where to resume from
     * @param options additional options
     * @return the interpreter instance
     */
    public static Interpreter resume(Script script, DialogueHandler handleDialogue,
                                     ChoiceHandler handleChoice, FinishHandler handleFinish,
                                     String saveData, String beatName,
                                     InterpreterOptions options) {
        Interpreter interpreter = new Interpreter(script, handleDialogue, handleChoice,
                                                  handleFinish, options);
        interpreter.restore(saveData);
        if (beatName != null) {
            interpreter.start(beatName);
        } else {
            interpreter.resume();
        }
        return interpreter;
    }

    /**
     * Extracts translations from a parsed translation script.
     *
     * @param script the parsed translation script
     * @return a translations object to pass as InterpreterOptions.translations
     */
    public static Object extractTranslations(Script script) {
        return loreline.runtime.Loreline.extractTranslations(script.runtimeScript);
    }

    /**
     * Enable or disable runtime support for an alternate translation file format.
     *
     * By default only `.<locale>.lor` files are tried by loadLocale. Call this
     * to opt in to additional formats. Known names:
     *   - "po"    — GNU gettext PO (.po)
     *   - "xliff" — XLIFF 1.2 / 2.x (.xliff, .xlf)
     *   - "csv"   — CSV / TSV (.csv, .tsv)
     *
     * Unknown names are accepted silently (forward-compat).
     */
    public static void translationFormat(String name, boolean enabled) {
        loreline.runtime.Loreline.translationFormat(name, enabled);
    }

    /**
     * Returns the error from the most recent failed {@code parse()} or
     * {@code loadLocale()} call, or {@code null} on success.
     *
     * In async mode (callback supplied) the callback fires with {@code null}
     * on failure and this method tells you what went wrong. In sync mode the
     * call throws, and this field is set to the same error so it can be
     * inspected after the catch.
     *
     * Not thread-safe — read immediately after the call returns.
     */
    public static loreline.runtime.Error lastError() {
        return loreline.runtime.Loreline.lastError();
    }

    /**
     * Loads translations for a specific locale.
     * Walks the script's full import tree and loads `.<locale>.lor` files for each.
     * Defaults to looking up translations next to the source files.
     *
     * @param locale the locale code (e.g. "fr")
     * @param script the parsed source script
     * @param handleFile a file handler used to read translation files
     * @return a translations object to pass as InterpreterOptions.translations
     */
    public static Object loadLocale(String locale, Script script, ImportsFileHandler handleFile) {
        return loadLocale(locale, script, null, handleFile);
    }

    /**
     * Loads translations for a specific locale, walking the script's full import tree.
     * For each file involved in the script (root + transitively imported), looks up the
     * corresponding translation file by inserting `.<locale>` before the extension
     * (e.g. `characters.lor` → `characters.fr.lor`). Missing translation files are
     * silently skipped.
     *
     * @param locale the locale code (e.g. "fr")
     * @param script the parsed source script
     * @param filePath optional override for where to look for translation files; pass null to
     *                 default to `script.filePath`. Can be a `.lor`/`.lor.txt` path or a directory.
     * @param handleFile a file handler used to read translation files
     * @return a translations object to pass as InterpreterOptions.translations
     */
    public static Object loadLocale(String locale, Script script, String filePath,
                                    ImportsFileHandler handleFile) {
        loreline.internal.jvm.Function fileHandlerBridge = null;
        if (handleFile != null) {
            fileHandlerBridge = new ImportsFileHandlerBridge(handleFile);
        }

        return RuntimeBridge.loadLocale(locale, script.runtimeScript, filePath,
                                         fileHandlerBridge, null);
    }

    /**
     * Prints a parsed script back into Loreline source code.
     *
     * @param script the parsed script
     * @return the printed source code as a string
     */
    public static String print(Script script) {
        return print(script, null, null);
    }

    /**
     * Prints a parsed script back into Loreline source code with custom formatting.
     *
     * @param script the parsed script
     * @param indent the indentation string to use (defaults to two spaces)
     * @param newline the newline string to use (defaults to "\n")
     * @return the printed source code as a string
     */
    public static String print(Script script, String indent, String newline) {
        return loreline.runtime.Loreline.print(script.runtimeScript, indent, newline);
    }

    /**
     * Ticks pending wait() timers. Call this from your game loop every frame.
     * The first call enables non-blocking deferred mode for wait();
     * before this is called, wait() falls back to blocking sleep (correct for CLI tools).
     *
     * @param delta time elapsed since last frame in seconds
     */
    public static void update(double delta) {
        loreline.runtime.Timer.update(delta);
    }

    // --- Bridge class for imports file handler ---

    private static class ImportsFileHandlerBridge extends loreline.internal.jvm.Function {
        private final ImportsFileHandler handler;

        ImportsFileHandlerBridge(ImportsFileHandler handler) {
            this.handler = handler;
        }

        @Override
        public void invoke(Object arg1, Object arg2) {
            // arg1 = file path, arg2 = Haxe callback function
            final String path = (String) arg1;
            final loreline.internal.jvm.Function hxCallback =
                (loreline.internal.jvm.Function) arg2;
            // Pass the user a Consumer that, when called (sync or async), fires
            // the underlying Haxe callback. Allocate a fresh args array per
            // dispatch — async-safe (a static array would race if the user
            // invokes the consumer from another thread).
            handler.handle(path, content -> {
                Object[] args = new Object[]{ content };
                hxCallback.invokeDynamic(args);
            });
        }
    }
}
