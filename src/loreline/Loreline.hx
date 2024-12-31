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
     * @throws parseErrors if the parsing failed (`Array<ParseError>`).
     * @throws lexerError if the lexing failed (`LexerError`).
     * @return The parsed script AST
     */
    public static function parse(input:String):Script {

        final lexer = new Lexer(input);
        final parser = new Parser(lexer.tokenize());

        final result = parser.parse();
        final parseErrors = parser.getErrors();

        if (parseErrors != null && parseErrors.length > 0) {
            throw [].concat(parseErrors);
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
