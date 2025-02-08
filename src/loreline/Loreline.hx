package loreline;

import loreline.Interpreter;

/**
 * Public Loreline API
 */
class Loreline {

    /**
     * Parse the given loreline script content and
     * returns the resulting script AST
     * @param input The input script as text. Must be a valid loreline script (`.lor` format)
     * @throws error if the lexing or parsing failed (`loreline.Error`)
     * @return The parsed script AST
     */
    public static function parse(input:String):Script {

        final lexer = new Lexer(input);
        final tokens = lexer.tokenize();
        //trace(tokens);
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

    public static function play(
        script:Script,
        handleDialogue:DialogueHandler,
        handleChoice:ChoiceHandler,
        handleFinish:FinishHandler,
        ?beatName:String
    ):Void {

        final interpreter = new Interpreter(
            script,
            handleDialogue,
            handleChoice,
            handleFinish
        );

        interpreter.start(beatName);

    }

}
