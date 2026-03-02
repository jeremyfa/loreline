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

    // --- Bridge class for imports file handler ---

    private static class ImportsFileHandlerBridge extends loreline.internal.jvm.Function {
        private static final Object[] ARGS_1 = new Object[1];
        private final ImportsFileHandler handler;

        ImportsFileHandlerBridge(ImportsFileHandler handler) {
            this.handler = handler;
        }

        @Override
        public void invoke(Object arg1, Object arg2) {
            // arg1 = file path, arg2 = callback function
            String content = handler.handle((String) arg1);
            loreline.internal.jvm.Function callback = (loreline.internal.jvm.Function) arg2;
            ARGS_1[0] = content;
            callback.invokeDynamic(ARGS_1);
        }
    }
}
