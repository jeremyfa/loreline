package loreline;

import loreline.Interpreter;

/**
 * The main public API for Loreline runtime.
 * Provides easy access to the core functionality for parsing and running Loreline scripts.
 */
class Loreline {

    /**
     * Parses the given text input and creates an executable `Script` instance from it.
     *
     * This is the first step in working with a Loreline script. The returned
     * `Script` object can then be passed to methods `play()` or `resume()`.
     *
     * @param input The Loreline script content as a string (`.lor` format)
     * @return The parsed script as an AST `Script` instance
     * @throws loreline.Error If the script contains syntax errors or other parsing issues
     */
    public static function parse(input:String):Script {

        final lexer = new Lexer(input);
        final tokens = lexer.tokenize();
        final parser = new Parser(tokens);

        final result = parser.parse();
        final lexerErrors = lexer.getErrors();
        final parseErrors = parser.getErrors();

        if (lexerErrors != null && lexerErrors.length > 0) {
            throw lexerErrors[0];
        }

        if (parseErrors != null && parseErrors.length > 0) {
            throw parseErrors[0];
        }

        return result;
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
     * @param functions Optional map of custom functions to make available in the script
     * @return The interpreter instance that is running the script
     */
    public static function play(
        script:Script,
        handleDialogue:DialogueHandler,
        handleChoice:ChoiceHandler,
        handleFinish:FinishHandler,
        ?beatName:String,
        ?functions:Map<String,Any>
    ):Interpreter {

        final interpreter = new Interpreter(
            script,
            handleDialogue,
            handleChoice,
            handleFinish,
            functions
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
        ?functions:Map<String,Any>
    ):Interpreter {

        final interpreter = new Interpreter(
            script,
            handleDialogue,
            handleChoice,
            handleFinish,
            functions
        );

        interpreter.restore(saveData);
        interpreter.resume();

        return interpreter;
    }

}