package loreline;

import loreline.AstUtils;
import loreline.Imports;
import loreline.Interpreter;
import loreline.Lexer;
import loreline.Node.NStringLiteral;
import loreline.Parser;

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

}