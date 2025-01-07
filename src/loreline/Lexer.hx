package loreline;

using StringTools;

/**
 * Represents an error that occurred during lexical analysis.
 */
class LexerError extends Error {

}

/**
 * Represents additional information attached to a string token, such as interpolations or tags.
 */
enum LStringAttachment {

    /**
     * String interpolation expression.
     * @param braces Whether the interpolation uses braces
     * @param inTag Whether the interpolation is inside a tag
     * @param expr The tokens making up the interpolation expression
     * @param start Starting position in the string
     * @param length Length of the interpolation
     */
    Interpolation(braces:Bool, inTag:Bool, expr:Array<Token>, start:Int, length:Int);

    /**
     * String formatting tag.
     * @param closing Whether this is a closing tag
     * @param start Starting position in the string
     * @param length Length of the tag
     */
    Tag(closing:Bool, start:Int, length:Int);

}

/**
 * Represents the different types of tokens that can be produced by the lexer.
 */
@:using(loreline.Lexer.TokenTypeHelpers)
enum TokenType {

    /** Import statement keyword */
    KwImport;
    /** State declaration keyword */
    KwState;
    /** Beat declaration keyword */
    KwBeat;
    /** Character declaration keyword */
    KwCharacter;
    /** Choice block keyword */
    KwChoice;
    /** If statement keyword */
    KwIf;
    /** Else statement keyword */
    KwElse;
    /** New state keyword */
    KwNew;

    /** String literal with optional attachments */
    LString(quotes:Quotes, s:String, ?attachments:Array<LStringAttachment>);
    /** Numeric literal */
    LNumber(n:Float);
    /** Boolean literal */
    LBoolean(b:Bool);
    /** Null literal */
    LNull;

    /** Identifier token */
    Identifier(name:String);

    /** Assignment operator (=) */
    OpAssign;
    /** Plus-assignment operator (+=) */
    OpPlusAssign;
    /** Minus-assignment operator (-=) */
    OpMinusAssign;
    /** Multiply-assignment operator (*=) */
    OpMultiplyAssign;
    /** Divide-assignment operator (/=) */
    OpDivideAssign;
    /** Addition operator (+) */
    OpPlus;
    /** Subtraction operator (-) */
    OpMinus;
    /** Multiplication operator (*) */
    OpMultiply;
    /** Division operator (/) */
    OpDivide;
    /** Modulo operator (%) */
    OpModulo;
    /** Equality operator (==) */
    OpEquals;
    /** Inequality operator (!=) */
    OpNotEquals;
    /** Greater than operator (>) */
    OpGreater;
    /** Less than operator (<) */
    OpLess;
    /** Greater than or equal operator (>=) */
    OpGreaterEq;
    /** Less than or equal operator (<=) */
    OpLessEq;
    /** Logical AND operator (&&) */
    OpAnd;
    /** Logical OR operator (||) */
    OpOr;
    /** Logical NOT operator (!) */
    OpNot;

    /** Transition arrow (->) */
    Arrow;
    /** Colon (:) */
    Colon;
    /** Comma (,) */
    Comma;
    /** Dot (.) */
    Dot;
    /** Left brace ({) */
    LBrace;
    /** Right brace (}) */
    RBrace;
    /** Left parenthesis (() */
    LParen;
    /** Right parenthesis ()) */
    RParen;
    /** Left bracket ([) */
    LBracket;
    /** Right bracket (]) */
    RBracket;

    /** Single-line comment */
    CommentLine(content:String);
    /** Multi-line comment */
    CommentMultiLine(content:String);

    /** Line break token */
    LineBreak;

    /** End of file token */
    Eof;

}

/**
 * Helper functions for TokenType enum.
 */
class TokenTypeHelpers {

    /**
     * Compares two token types for equality.
     * @param a First token type
     * @param b Second token type
     * @return Whether the token types are equal
     */
    public static function equals(a:TokenType, b:TokenType):Bool {
        return switch [a, b] {
            case [Arrow, Arrow]: true;
            case [Colon, Colon]: true;
            case [Dot, Dot]: true;
            case [LBrace, LBrace]: true;
            case [RBrace, RBrace]: true;
            case [LParen, LParen]: true;
            case [RParen, RParen]: true;
            case [LBracket, LBracket]: true;
            case [RBracket, RBracket]: true;
            case [LineBreak, LineBreak]: true;
            case [KwState, KwState]: true;
            case [KwBeat, KwBeat]: true;
            case [KwCharacter, KwCharacter]: true;
            case [KwChoice, KwChoice]: true;
            case [KwIf, KwIf]: true;
            case [KwElse, KwElse]: true;
            case [KwNew, KwNew]: true;
            case [OpAssign, OpAssign]: true;
            case [OpPlusAssign, OpPlusAssign]: true;
            case [OpMinusAssign, OpMinusAssign]: true;
            case [OpMultiplyAssign, OpMultiplyAssign]: true;
            case [OpDivideAssign, OpDivideAssign]: true;
            case [OpPlus, OpPlus]: true;
            case [OpMinus, OpMinus]: true;
            case [OpMultiply, OpMultiply]: true;
            case [OpDivide, OpDivide]: true;
            case [OpModulo, OpModulo]: true;
            case [OpEquals, OpEquals]: true;
            case [OpNotEquals, OpNotEquals]: true;
            case [OpGreater, OpGreater]: true;
            case [OpLess, OpLess]: true;
            case [OpGreaterEq, OpGreaterEq]: true;
            case [OpLessEq, OpLessEq]: true;
            case [OpAnd, OpAnd]: true;
            case [OpOr, OpOr]: true;
            case [OpNot, OpNot]: true;
            case [LNull, LNull]: true;
            case [Identifier(n1), Identifier(n2)]: n1 == n2;
            case [LString(s1, _), LString(s2, _)]: s1 == s2;
            case [LNumber(n1), LNumber(n2)]: n1 == n2;
            case [LBoolean(b1), LBoolean(b2)]: b1 == b2;
            case [CommentLine(c1), CommentLine(c2)]: c1 == c2;
            case [CommentMultiLine(c1), CommentMultiLine(c2)]: c1 == c2;
            case [Eof, Eof]: true;
            case _: Type.enumEq(a, b);
        }
    }

    /**
     * Checks if a token type is a comment.
     * @param a Token type to check
     * @return Whether the token type is a comment
     */
    public static function isComment(a:TokenType):Bool {
        return switch a {
            case CommentLine(_) | CommentMultiLine(_): true;
            case _: false;
        }
    }

    /**
     * Checks if a token type is an identifier.
     * @param a Token type to check
     * @return Whether the token type is an identifier
     */
    public static function isIdentifier(a:TokenType):Bool {
        return switch a {
            case Identifier(_): true;
            case _: false;
        }
    }

}

/**
 * Represents a token in the source code.
 */
class Token {
    /**
     * The type of this token.
     */
    public final type:TokenType;

    /**
     * The position of this token in the source code.
     */
    public var pos:Position;

    /**
     * Creates a new token.
     * @param type The token type
     * @param pos The token's position
     */
    public function new(type:TokenType, pos:Position) {
        this.type = type;
        this.pos = pos;
    }

    /**
     * Converts the token to a human-readable string.
     * @return Formatted token information with position
     */
    public function toString():String {
        return '$type at ${pos.toString()}';
    }

}

/**
 * The lexical analyzer for the Loreline language.
 * Converts source code text into a sequence of tokens.
 */
class Lexer {

    /**
     * Mapping of keywords to their corresponding token types.
     */
    static final KEYWORDS = [
        "import" => TokenType.KwImport,
        "state" => TokenType.KwState,
        "beat" => TokenType.KwBeat,
        "character" => TokenType.KwCharacter,
        "choice" => TokenType.KwChoice,
        "if" => TokenType.KwIf,
        "else" => TokenType.KwElse,
        "new" => TokenType.KwNew,
        "true" => TokenType.LBoolean(true),
        "false" => TokenType.LBoolean(false),
        "null" => TokenType.LNull
    ];

    /**
     * The input source code being lexed.
     */
    final input:String;

    /**
     * Current position in the input.
     */
    var pos:Int;

    /**
     * Length of the input string.
     */
    var length:Int;

    /**
     * Current line number.
     */
    var line:Int;

    /**
     * Current column number.
     */
    var column:Int;

    /**
     * Starting line of the current token.
     */
    var startLine:Int;

    /**
     * Starting column of the current token.
     */
    var startColumn:Int;

    /**
     * Previous token that was read.
     */
    var previous:Token;

    /**
     * Current token lists during tokenization
     */
    var tokenized:Array<Token>;

    /**
     * A stack to keep track of whether we are inside a `beat` or a `state`/`character` block.
     * Depending on that, the rules for reading unquoted string tokens are different.
     */
    var stack:Array<TokenType>;

    /**
     * The token type that will be added to the `stack`
     * next time we find a `LBrace` token
     */
    var nextBlock:TokenType;

    /**
     * When higher than zero, that means only strictly
     * correct expressions are accepted, thus
     * unquoted strings will be disabled. Mostly
     * used to handle interpolated values in strings
     */
    var strictExprs:Int;

    /**
     * Creates a new lexer for the given input.
     * @param input The source code to lex
     */
    public function new(input:String) {
        this.input = input;
        this.length = input.length;
        reset();
    }

    /**
     * Resets the lexer to the beginning of the input.
     */
    public function reset() {
        this.pos = 0;
        this.line = 1;
        this.column = 1;
        this.startLine = 1;
        this.startColumn = 1;
        this.previous = null;
        this.stack = [];
        this.nextBlock = LBrace;
        this.tokenized = null;
        this.strictExprs = 0;
    }

    /**
     * Converts the entire input into an array of tokens.
     * @return Array of tokens
     */
    public function tokenize():Array<Token> {
        final tokens = [];
        this.tokenized = tokens;
        while (true) {
            final token = nextToken();
            tokens.push(token);

            switch token.type {
                case KwState | KwCharacter | KwBeat | KwChoice:
                    nextBlock = token.type;
                case LBrace:
                    stack.push(nextBlock);
                    nextBlock = LBrace;
                case LBracket:
                    stack.push(LBracket);
                    nextBlock = LBrace;
                case RBrace | RBracket:
                    stack.pop();
                    nextBlock = LBrace;
                case _:
            }

            if (token.type == Eof) break;
        }
        return tokens;
    }

    /**
     * Reads and returns the next token from the input.
     * @return The next token
     * @throws LexerError if invalid input is encountered
     */
    public function nextToken():Token {
        skipWhitespace();

        if (pos >= length) {
            return makeToken(Eof);
        }

        startLine = line;
        startColumn = column;
        final c = input.charCodeAt(pos);

        if (c == "\n".code || c == "\r".code) {
            return readLineBreak();
        }

        final startPos = makePosition();
        return switch (c) {
            case "{".code: advance(); makeToken(LBrace, startPos);
            case "}".code: advance(); makeToken(RBrace, startPos);
            case '"'.code: readString(startPos);
            case "[".code: advance(); makeToken(LBracket, startPos);
            case _:
                tryReadUnquotedString() ?? switch (c) {
                    case "]".code: advance(); makeToken(RBracket, startPos);
                    case "(".code: advance(); makeToken(LParen, startPos);
                    case ")".code: advance(); makeToken(RParen, startPos);
                    case ":".code: advance(); makeToken(Colon, startPos);
                    case ",".code: advance(); makeToken(Comma, startPos);
                    case ".".code: advance(); makeToken(Dot, startPos);
                    case c if (isDigit(c)): readNumber();
                    case c if (isIdentifierStart(c)): readIdentifier();

                    case "+".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpPlusAssign, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpPlus, startPos);
                        }

                    case "-".code:
                        if (peek() == ">".code) {
                            advance(2);
                            makeToken(Arrow, startPos);
                        }
                        else if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpMinusAssign, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpMinus, startPos);
                        }

                    case "*".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpMultiplyAssign, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpMultiply, startPos);
                        }

                    case "/".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpDivideAssign, startPos);
                        }
                        else if (peek() == "/".code) {
                            return readLineComment();
                        }
                        else if (peek() == "*".code) {
                            return readMultiLineComment();
                        }
                        else {
                            advance();
                            makeToken(OpDivide, startPos);
                        }

                    case "%".code:
                        advance();
                        makeToken(OpModulo, startPos);

                    case "&".code:
                        if (peek() == "&".code) {
                            advance(2);
                            makeToken(OpAnd, startPos);
                        }
                        else {
                            advance();
                            error('Expected &');
                        }

                    case "|".code:
                        if (peek() == "|".code) {
                            advance(2);
                            makeToken(OpOr, startPos);
                        }
                        else {
                            advance();
                            error('Expected |');
                        }

                    case "!".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpNotEquals, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpNot, startPos);
                        }

                    case "=".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpEquals, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpAssign, startPos);
                        }

                    case ">".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpGreaterEq, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpGreater, startPos);
                        }

                    case "<".code:
                        if (peek() == "=".code) {
                            advance(2);
                            makeToken(OpLessEq, startPos);
                        }
                        else {
                            advance();
                            makeToken(OpLess, startPos);
                        }

                    case _: error('Unexpected character: ${String.fromCharCode(c)}');
                }
        }

    }

    /**
     * Returns the token type of the parent block.
     * @return The token type of the parent block or KwBeat if at top level
     */
    function parentBlockType():TokenType {

        var i = stack.length - 1;
        while (i >= 0) {
            if (stack[i] != LBrace && stack[i] != LBracket) {
                if (stack[i] == KwChoice && i < stack.length - 1) {
                    return KwBeat;
                }
                return stack[i];
            }
            i--;
        }

        // Assume top level is like being in a beat
        return KwBeat;

    }

    /**
     * Checks if currently in a parent bracket block.
     * @return True if inside brackets, false otherwise
     */
    function inParentBrackets():Bool {

        var i = stack.length - 1;
        while (i >= 0) {
            if (stack[i] != LBrace) {
                return stack[i] == LBracket;
            }
            i--;
        }

        return false;

    }

    /**
     * Checks if currently in a beat block.
     * @return True if inside a beat block, false otherwise
     */
    function inBeat():Bool {
        return parentBlockType() == KwBeat;
    }

    /**
     * Checks if currently in a state or character block.
     * @return True if inside a state or character block, false otherwise
     */
    function inStateOrCharacter():Bool {
        final parent = parentBlockType();
        return parent == KwState || parent == KwCharacter;
    }

    /**
     * Reads a line break token (newline or carriage return + newline).
     * @return Line break token
     */
    function readLineBreak():Token {
        final start = makePosition();
        if (input.charCodeAt(pos) == "\r".code) {
            advance();
            if (pos < length && input.charCodeAt(pos) == "\n".code) {
                advance();
            }
        }
        else {
            advance();
        }
        return makeToken(LineBreak, start);
    }

    /**
     * Helper function to check if a character is whitespace.
     * @param c The character code to check
     * @return True if the character is whitespace, false otherwise
     */
    inline function isWhitespace(c:Int):Bool {
        return c == " ".code || c == "\t".code;
    }

    /**
     * Helper function to match an identifier at the given position.
     * @param pos The position to start matching from
     * @return The matched identifier, or `null` if not matching
     */
    function matchIdentifier(pos:Int):Null<String> {
        // Handle empty strings first
        if (input.length == 0) {
            return null;
        }

        // Check if the first character is a valid identifier start
        var firstChar = input.charCodeAt(pos + 0);
        if (!isIdentifierStart(firstChar)) {
            return null;
        }

        // Keep track of where the identifier ends
        var identifierLength = 1;

        // Check subsequent characters until we find an invalid one
        // or reach the end of the string
        while (identifierLength < input.length) {
            if (!isIdentifierPart(input.charCodeAt(pos + identifierLength))) {
                break;
            }
            identifierLength++;
        }

        // Return the substring that contains our identifier
        return input.substr(pos, identifierLength);
    }

    /**
     * Returns whether the input at the given position is the start of an if condition.
     * @param pos Position to check from
     * @return True if an if condition starts at the position, false otherwise
     */
    function isIfStart(pos:Int):Bool {

        if (input.charCodeAt(pos) != "i".code) return false;
        pos++;

        if (input.charCodeAt(pos) != "f".code) return false;
        pos++;

        final len = input.length;
        var inComment = false;
        var matchesIf = false;

        while (pos < len) {
            var c = input.charCodeAt(pos);
            var cc = pos < input.length - 1 ? input.charCodeAt(pos+1) : 0;

            if (inComment) {
                if (c == "*".code && cc == "/".code) {
                    inComment = false;
                    pos += 2;
                }
                else {
                    pos++;
                }
            }
            else {
                if (c == "/".code && cc == "*".code) {
                    inComment = true;
                    pos += 2;
                }
                else if (isWhitespace(c)) {
                    pos++;
                }
                else if (c == "(".code) {
                    matchesIf = true;
                    break;
                }
                else {
                    break;
                }
            }
        }

        return matchesIf;

    }

    /**
     * Returns whether the input at the given position is the start of a function or method call.
     * @param pos Position to check from
     * @return True if a function call starts at the position, false otherwise
     */
    function isCallStart(pos:Int):Bool {

        // Save initial position to restore it later
        var startPos = pos;

        // Helper function to skip whitespace
        inline function skipWhitespaces() {
            while (pos < input.length && (input.charCodeAt(pos) == " ".code || input.charCodeAt(pos) == "\t".code)) {
                pos++;
            }
        }

        // Helper function to read identifier
        inline function readIdent():Bool {
            var result = true;

            if (pos >= input.length) {
                result = false;
            }
            else {
                var c = input.charCodeAt(pos);

                // First char must be letter or underscore
                if (!isIdentifierStart(c)) {
                    result = false;
                }
                else {
                    pos++;

                    // Continue reading identifier chars
                    while (pos < input.length) {
                        c = input.charCodeAt(pos);
                        if (!isIdentifierPart(c)) break;
                        pos++;
                    }
                }
            }

            return result;
        }

        // Must start with identifier
        if (!readIdent()) {
            pos = startPos;
            return false;
        }

        // Keep reading segments until we find opening parenthesis
        while (pos < input.length) {
            skipWhitespaces();

            if (pos >= input.length) {
                pos = startPos;
                return false;
            }

            var c = input.charCodeAt(pos);

            // Found opening parenthesis - success!
            if (c == "(".code) {
                pos = startPos;
                return true;
            }

            // Handle dot access
            if (c == ".".code) {
                pos++;
                skipWhitespaces();
                if (!readIdent()) {
                    pos = startPos;
                    return false;
                }
                continue;
            }

            // Handle bracket access
            if (c == "[".code) {
                // Skip everything until closing bracket
                pos++;
                while (pos < input.length) {
                    if (input.charCodeAt(pos) == "]".code) {
                        pos++;
                        break;
                    }
                    pos++;
                }
                continue;
            }

            // Any other character means this isn't a call
            pos = startPos;
            return false;
        }

        pos = startPos;
        return false;

    }

    /**
     * Returns whether the next token is a colon.
     * @param pos Position to check from
     * @param skipWhitespaces Whether to skip whitespace before checking
     * @return True if next token is a colon, false otherwise
     */
    function isColon(pos:Int, skipWhitespaces:Bool = true):Bool {

        if (skipWhitespaces) {
            while (pos < input.length && (input.charCodeAt(pos) == " ".code || input.charCodeAt(pos) == "\t".code)) {
                pos++;
            }
        }

        return pos < input.length && input.charCodeAt(pos) == ":".code;

    }

    /**
     * Returns whether we are currently right after a label.
     * @return True if after a label, false otherwise
     */
    function isAfterLabel():Bool {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];

            if (!token.type.isComment() && token.type != LineBreak) {
                return (token.type == Colon && i > 0 && tokenized[i-1].type.isIdentifier());
            }

            i--;
        }

        return false;

    }

    /**
     * Returns whether we are currently inside brackets [ ].
     * @return True if inside brackets, false otherwise
     */
    function isInsideBrackets():Bool {

        return stack.length > 0 && stack[stack.length-1] == LBracket;

    }

    /**
     * Returns whether the resolved tokens in the current line are only white spaces,
     * a single label `someLabel:`, or comments.
     * @return True if line only contains label or comments, false otherwise
     */
    function followsOnlyLabelOrCommentsInLine() {

        var foundLabel = false;
        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];
            if (token.type.isComment()) {
                i--;
            }
            else if (!foundLabel && token.type == Colon) {
                i--;
                if (i >= 0) {
                    if (tokenized[i].type.isIdentifier()) {
                        foundLabel = true;
                        i--;
                    }
                }
                else {
                    return false;
                }
            }
            else if (token.type == LineBreak) {
                return true;
            }
            else {
                return false;
            }
        }

        return true;

    }

    /**
     * Returns whether the resolved tokens in the current line are only white spaces or comments.
     * @return True if line only contains whitespace or comments, false otherwise
     */
    function followsOnlyWhitespacesOrCommentsInLine() {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];

            if (token.type.isComment()) {
                i--;
            }
            else if (token.type == LineBreak) {
                return true;
            }
            else {
                return false;
            }
        }

        return true;

    }

    /**
     * Returns whether the given string has a non special character that could be
     * considered as actual text.
     * @param str String to check
     * @return True if string contains non-special characters, false otherwise
     */
    function hasNonSpecialChar(str:String):Bool {

        static final specialChars = " \t\"+=*/-(){}[]:\n\r";

        for (i in 0...str.length) {
            var found = false;
            var code = str.charCodeAt(i);
            for (j in 0...specialChars.length) {
                if (code == specialChars.charCodeAt(j)) {
                    found = true;
                    break;
                }
            }
            if (!found) return true;
        }

        return false;

    }

    /**
     * Returns whether the given input is a valid number.
     * @param input String to check
     * @return True if string represents a valid number, false otherwise
     */
    function isNumber(input:String):Bool {
        var pos:Int = 0;
        var length = input.length;

        while (pos < length && isDigit(input.charCodeAt(pos))) {
            pos++;
        }

        if (pos < length && input.charCodeAt(pos) == ".".code && pos + 1 < length && isDigit(input.charCodeAt(pos + 1))) {
            pos++;
            while (pos < length && isDigit(input.charCodeAt(pos))) pos++;
        }

        return pos == length;
    }

    /**
     * Tries to read an unquoted string literal from the current position.
     * Returns null if the current position cannot start an unquoted string.
     * @return Token if an unquoted string was read, null otherwise
     */
    function tryReadUnquotedString():Null<Token> {
        // Skip in strict expression area
        if (strictExprs > 0) return null;

        // Look ahead to validate if this could be an unquoted string start
        final c = input.charCodeAt(pos);
        final cc = peek();

        // Skip if it's a comment
        if (c == "/".code && pos < length - 1) {
            final next = input.charCodeAt(pos + 1);
            if (next == "/".code || next == "*".code) return null;
        }

        // Skip if it's one of those operators:
        // {
        // }
        // [
        // ]
        // "
        // :
        if (c == "{".code || c == "}".code || c == "[".code || c == "]".code ||
            c == "\"".code || c == ":".code ||
            isWhitespace(c)) {
            return null;
        }

        // Check what is the parent block
        final parent = parentBlockType();

        // Skip if parent is not a beat, character, state or choice
        if (parent != KwBeat && parent != KwState && parent != KwCharacter && parent != KwChoice) {
            return null;
        }

        // Skip if this is a condition start or call start, in a beat block
        if (parent == KwBeat) {
            if (isIfStart(pos) || isCallStart(pos)) {
                return null;
            }
        }

        // Skip if it's one of those operators either, when inside a beat:
        // =
        // +=
        // -=
        // *=
        // /=
        // ->
        if (parent == KwBeat) {
            if (c == "=".code ||
                (cc == "=".code && (c == "+".code || c == "-".code || c == "*".code || c == "/".code)) ||
                (cc == ">".code && (c == "-".code))) {
                return null;
            }
        }

        // Skip if starting with a keyword
        var identifier = matchIdentifier(pos);
        if (identifier != null) {
            if (identifier != 'if' && KEYWORDS.exists(identifier)) return null;

            // Skip if starting with a label
            if (isColon(pos + identifier.length)) {
                return null;
            }
        }

        // By default, tags are not allowed unless inside beat content
        var allowTags = (parent == KwBeat);

        // If inside a character or state block,
        // Only allow unquoted strings after labels (someKey: ...)
        // or inside array brackets
        if (parent == KwState || parent == KwCharacter) {

            // Skip if not after a label or inside brackets
            if (!isAfterLabel() && !isInsideBrackets()) {
                return null;
            }
        }

        // If inside a choice,
        // Only allow unquoted strings preceded by
        // white spaces or comments in current line
        else if (parent == KwChoice) {

            // Skip if not starting line
            if (!followsOnlyWhitespacesOrCommentsInLine()) {
                return null;
            }
        }

        // If inside a beat,
        // Only allow unquoted strings after labels (someKey: ...) starting the line
        // or if only preceded by white spaces or comments in current line
        else if (parent == KwBeat) {

            // Skip if not after a label or starting line
            if (!followsOnlyLabelOrCommentsInLine() && !followsOnlyWhitespacesOrCommentsInLine()) {
                return null;
            }
        }

        // If we get here, we can start reading the unquoted string
        final start = makePosition();
        final buf = new StringBuf();
        final attachments = new Array<LStringAttachment>();

        final startLine = line;
        final startColumn = column;
        final startPos = pos;

        var escaped = false;
        var tagStart = -1;
        var tagIsClosing = false;
        var currentColumn = column;
        var currentLine = line;
        var valid = true;
        var hasContent = false;

        while (pos < length) {
            final c = input.charCodeAt(pos);
            final isSpace = isWhitespace(c);

            if (!hasContent) {
                if (!isSpace && tagStart == -1 && (c != "<".code || !allowTags)) {
                    hasContent = true;
                }
            }

            if (escaped) {
                buf.addChar("\\".code);
                buf.addChar(c);
                escaped = false;
                advance();
                currentColumn += 2;
            }
            else if (c == "\\".code) {
                escaped = true;
                advance();
            }
            else if (tagStart == -1 && isSpace && !hasContent) {
                // Skip leading white spaces
                advance();
            }
            // Check for end of string conditions
            else if (tagStart == -1 && (c == "\n".code || c == "\r".code || c == "{".code)) {
                break;
            }
            // Check for trailing if
            else if (tagStart == -1 && parent == KwChoice && c == "i".code && input.charCodeAt(pos+1) == "f".code && isIfStart(pos)) {
                break;
            }
            // Check for comment start
            else if (tagStart == -1 && (c == "/".code && pos < length - 1 && (input.charCodeAt(pos+1) == "/".code || input.charCodeAt(pos+1) == "*".code))) {
                break;
            }
            // No assign in beats
            else if (tagStart == -1 && parent == KwBeat && (c == "=".code ||
                (input.charCodeAt(pos+1) == "=".code && (c == "+".code || c == "-".code || c == "*".code || c == "/".code)))) {
                valid = false;
                break;
            }
            else if (allowTags && c == "<".code) {
                if (tagStart != -1) {
                    error("Unexpected < inside tag");
                }
                final nextChar = pos + 1 < length ? input.charCodeAt(pos + 1) : 0;
                tagIsClosing = nextChar == "/".code;
                final checkPos = pos + (tagIsClosing ? 2 : 1);
                if (checkPos < length) {
                    final nameStart = input.charCodeAt(checkPos);
                    if (isIdentifierStart(nameStart) || nameStart == "_".code || nameStart == "$".code || (tagIsClosing && nameStart == ">".code)) {
                        tagStart = buf.length;
                    }
                }
                buf.addChar(c);
                advance();
                currentColumn++;
            }
            else if (allowTags && c == ">".code) {
                buf.addChar(c);
                advance();
                currentColumn++;
                if (tagStart != -1) {
                    attachments.push(Tag(tagIsClosing, tagStart, buf.length - tagStart));
                    tagStart = -1;
                }
            }
            else if (c == "$".code && !escaped) {
                final interpStart = buf.length;
                final interpLine = currentLine;
                final interpColumn = currentColumn;
                final tokenStartPos = pos;

                try {
                    advance();
                    currentColumn++;

                    if (input.charCodeAt(pos) == "{".code) {
                        advance();
                        currentColumn++;

                        final interpPos = new Position(interpLine, interpColumn + 2, pos);
                        final tokens = readComplexInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(true, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.substr(tokenStartPos, interpLength));
                    }
                    else if (isIdentifierStart(input.charCodeAt(pos))) {
                        final interpPos = new Position(interpLine, interpColumn + 1, pos);
                        final tokens = readFieldAccessInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.substr(tokenStartPos, interpLength));
                    }
                    else {
                        error("Expected identifier or { after $");
                    }
                } catch (e:LexerError) {
                    if (e.pos == null) e.pos = new Position(interpLine, interpColumn, pos);
                    throw e;
                }

                currentColumn = interpColumn + (pos - tokenStartPos);
            }
            else {
                if (c == "\n".code) {
                    currentLine++;
                    currentColumn = 1;
                }
                else {
                    currentColumn++;
                }
                buf.addChar(c);
                advance();
            }
        }

        // If we found valid content, return the string token
        if (valid) {
            final content = buf.toString().rtrim();
            if (content.length > 0 && hasNonSpecialChar(content) && !isNumber(content)) {
                attachments.sort(compareAttachments);

                return makeToken(LString(
                    Unquoted, content,
                    attachments.length > 0 ? attachments : null
                ), start);
            }
        }

        // Not matching an unquoted string, restore
        // position like before
        line = startLine;
        column = startColumn;
        pos = startPos;

        return null;
    }

    /**
     * Reads a string literal, handling escape sequences, interpolation, and tags.
     * @param stringStart Starting position of the string
     * @return String literal token
     * @throws LexerError if string is malformed or unterminated
     */
    function readString(stringStart:Position):Token {
        advance(); // Skip opening quote
        final buf = new StringBuf();
        final attachments = new Array<LStringAttachment>();
        var escaped = false;
        var tagStart = -1;
        var tagIsClosing = false;
        var currentColumn = stringStart.column + 1; // Add 1 for the opening quote
        var currentLine = stringStart.line;

        // By default, tags are not allowed unless inside beat content
        var allowTags = (parentBlockType() == KwBeat);

        while (pos < length) {
            final c = input.charCodeAt(pos);

            if (escaped) {
                buf.addChar("\\".code);
                buf.addChar(c);
                escaped = false;
                advance();
                currentColumn += 2;
            }
            else if (c == "\\".code) {
                escaped = true;
                advance();
            }
            else if (c == '"'.code && tagStart == -1) {
                advance();
                attachments.sort(compareAttachments);

                return makeToken(LString(
                    DoubleQuotes, buf.toString(),
                    attachments.length > 0 ? attachments : null
                ), stringStart);
            }
            else if (allowTags && c == "<".code) {
                if (tagStart != -1) {
                    error("Unexpected < inside tag");
                }
                final nextChar = pos + 1 < length ? input.charCodeAt(pos + 1) : 0;
                tagIsClosing = nextChar == "/".code;
                final checkPos = pos + (tagIsClosing ? 2 : 1);
                if (checkPos < length) {
                    final nameStart = input.charCodeAt(checkPos);
                    if (isIdentifierStart(nameStart) || nameStart == "_".code || nameStart == "$".code || (tagIsClosing && nameStart == ">".code)) {
                        tagStart = buf.length;
                    }
                }
                buf.addChar(c);
                advance();
                currentColumn++;
            }
            else if (c == ">".code) {
                buf.addChar(c);
                advance();
                currentColumn++;
                if (tagStart != -1) {
                    attachments.push(Tag(tagIsClosing, tagStart, buf.length - tagStart));
                    tagStart = -1;
                }
            }
            else if (c == "$".code && !escaped) {
                final interpStart = buf.length;
                final interpLine = currentLine;
                final interpColumn = currentColumn;
                final tokenStartPos = pos;

                try {
                    advance();
                    currentColumn++;

                    if (input.charCodeAt(pos) == "{".code) {
                        advance();
                        currentColumn++;

                        final interpPos = new Position(interpLine, interpColumn + 2, pos);
                        final tokens = readComplexInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(true, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.substr(tokenStartPos, interpLength));
                    }
                    else if (isIdentifierStart(input.charCodeAt(pos))) {
                        final interpPos = new Position(interpLine, interpColumn + 1, pos);
                        final tokens = readFieldAccessInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.substr(tokenStartPos, interpLength));
                    }
                    else {
                        error("Expected identifier or { after $");
                    }
                } catch (e:LexerError) {
                    if (e.pos == null) e.pos = new Position(interpLine, interpColumn, pos);
                    throw e;
                }

                currentColumn = interpColumn + (pos - tokenStartPos);
            }
            else {
                if (c == "\n".code) {
                    currentLine++;
                    currentColumn = 1;
                }
                else {
                    currentColumn++;
                }
                buf.addChar(c);
                advance();
            }
        }

        error("Unterminated string");
        return null;
    }

    /**
     * Compares two string attachments by their starting position.
     * @param l First attachment
     * @param r Second attachment
     * @return Negative if l comes before r, positive if r comes before l, 0 if equal
     */
    static function compareAttachments(l:LStringAttachment, r:LStringAttachment):Int {
        final lStart = switch l {
            case Interpolation(_, _, _, start, _): start;
            case Tag(_, start, _): start;
        }
        final rStart = switch r {
            case Interpolation(_, _, _, start, _): start;
            case Tag(_, start, _): start;
        }
        return lStart - rStart;
    }

    /**
     * Reads a complex interpolation expression inside ${...}.
     * @param interpStart Starting position of the interpolation
     * @return Array of tokens making up the interpolation expression
     * @throws LexerError if interpolation is malformed or unterminated
     */
    function readComplexInterpolation(interpStart:Position):Array<Token> {
        strictExprs++;

        final tokens = new Array<Token>();
        var braceLevel = 1;
        var currentColumn = interpStart.column;
        var currentLine = interpStart.line;

        while (pos < length && braceLevel > 0) {
            if (input.charCodeAt(pos) == "}".code && --braceLevel == 0) {
                advance();
                break;
            }

            if (input.charCodeAt(pos) == '"'.code) {
                final stringPos = new Position(currentLine, currentColumn, pos);
                tokens.push(readString(stringPos));
                currentColumn += (pos - stringPos.offset);
                continue;
            }

            final tokenStart = new Position(currentLine, currentColumn, pos);
            final token = nextToken();
            token.pos = tokenStart;
            tokens.push(token);

            if (token.type == LineBreak) {
                currentLine++;
                currentColumn = 1;
            }
            else {
                var tokenLength = switch (token.type) {
                    case Identifier(name): name.length;
                    case LString(q, s, _): s.length + (q != Unquoted ? 2 : 0);
                    case LNumber(n): Std.string(n).length;
                    case _: 1;
                }
                currentColumn += tokenLength;
            }

            switch (token.type) {
                case LBrace: braceLevel++;
                case RBrace: braceLevel--;
                case _:
            }

            if (token.type == Eof) {
                error("Unterminated interpolation expression");
            }
        }

        strictExprs--;

        return tokens;
    }

    /**
     * Reads a token with proper position tracking in a nested context.
     * @param startPos Starting position for position calculation
     * @return Token with adjusted position
     */
    function nextTokenWithPosition(startPos:Position):Token {
        final savedLine = line;
        final savedColumn = column;
        final savedPos = pos;

        final token = nextToken();

        final tokenOffset = pos - savedPos;
        token.pos = new Position(
            startPos.line,
            startPos.column + tokenOffset,
            startPos.offset + tokenOffset
        );

        line = savedLine;
        column = savedColumn;

        return token;
    }

    /**
     * Reads a simple field access interpolation (e.g. $foo.bar).
     * @param stringStart Starting position of the interpolation
     * @return Array of tokens making up the field access
     * @throws LexerError if field access is malformed
     */
    function readFieldAccessInterpolation(stringStart:Position):Array<Token> {
        final tokens = new Array<Token>();

        if (!isIdentifierStart(input.charCodeAt(pos))) {
            error("Expected identifier in field access");
        }
        tokens.push(readIdentifierTokenInInterpolation(stringStart));

        while (pos < length - 1 && input.charCodeAt(pos) == ".".code && isIdentifierStart(input.charCodeAt(pos + 1))) {
            final dotPos = makePositionRelativeTo(stringStart);
            advance();

            if (pos >= length || !isIdentifierStart(input.charCodeAt(pos))) {
                break;
            }
            tokens.push(new Token(Dot, dotPos));
            tokens.push(readIdentifierTokenInInterpolation(stringStart));
        }

        return tokens;
    }

    /**
     * Reads an identifier token in a string interpolation context.
     * @param stringStart Starting position for position calculation
     * @return Identifier token
     */
    function readIdentifierTokenInInterpolation(stringStart:Position):Token {
        final startPos = makePositionRelativeTo(stringStart);
        final startOffset = pos;

        while (pos < length) {
            final c = input.charCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }

        final name = input.substr(startOffset, pos - startOffset);
        final tokenType = KEYWORDS.exists(name) ? KEYWORDS.get(name) : Identifier(name);
        return new Token(
            tokenType,
            startPos
        );
    }

    /**
     * Makes position relative to the given string start position.
     * @param stringStart Starting position for calculation
     * @return Position object relative to string start
     */
    function makePositionRelativeTo(stringStart:Position):Position {
        var line = stringStart.line;
        var column = stringStart.column;
        var i = stringStart.offset;

        while (i < pos) {
            if (input.charCodeAt(i) == "\n".code) {
                line++;
                column = 1;
            }
            else {
                column++;
            }
            i++;
        }

        return new Position(line, column, pos);
    }

    /**
     * Reads a single-line comment.
     * @return Comment token
     */
    function readLineComment():Token {
        final start = makePosition();
        advance(2);
        final contentStart = pos;

        while (pos < length) {
            final c = input.charCodeAt(pos);
            if (c == "\n".code || c == "\r".code) break;
            advance();
        }

        return makeToken(CommentLine(input.substr(contentStart, pos - contentStart)), start);
    }

    /**
     * Reads a multi-line comment, handling nested comments.
     * @return Comment token
     * @throws LexerError if comment is unterminated
     */
    function readMultiLineComment():Token {
        final start = makePosition();
        advance(2);
        final contentStart = pos;
        var nestLevel = 1;

        while (pos < length && nestLevel > 0) {
            if (input.charCodeAt(pos) == "*".code && peek() == "/".code) {
                nestLevel--;
                if (nestLevel == 0) {
                    final content = input.substr(contentStart, pos - contentStart);
                    advance(2);
                    return makeToken(CommentMultiLine(content), start);
                }
                advance(2);
            }
            else if (input.charCodeAt(pos) == "/".code && peek() == "*".code) {
                nestLevel++;
                advance(2);
            }
            else {
                advance();
            }
        }

        error("Unterminated multi-line comment");
        return null;
    }

    /**
     * Reads a numeric literal.
     * @return Number token
     */
    function readNumber():Token {
        final start = makePosition();
        final startPos = pos;

        while (pos < length && isDigit(input.charCodeAt(pos))) {
            advance();
        }

        if (pos < length && input.charCodeAt(pos) == ".".code && pos + 1 < length && isDigit(input.charCodeAt(pos + 1))) {
            advance();
            while (pos < length && isDigit(input.charCodeAt(pos))) advance();
        }

        return makeToken(LNumber(Std.parseFloat(input.substr(startPos, pos - startPos))), start);
    }

    /**
     * Reads an identifier or keyword.
     * @return Identifier or keyword token
     */
    function readIdentifier():Token {
        final start = makePosition();
        final startPos = pos;

        while (pos < length) {
            final c = input.charCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }

        final word = input.substr(startPos, pos - startPos);
        final tokenType = KEYWORDS.exists(word) ? KEYWORDS.get(word) : Identifier(word);
        return makeToken(
            tokenType,
            start
        );
    }

    /**
     * Creates a new position at the current location.
     * @return Position object
     */
    inline function makePosition():Position {
        return new Position(startLine, startColumn, pos);
    }

    /**
     * Creates a new token with the given type and optional position.
     * @param type Token type
     * @param position Optional position (defaults to current position)
     * @return Created token
     */
    inline function makeToken(type:TokenType, ?position:Position):Token {
        if (position == null) position = makePosition();
        position.length = pos - position.offset;
        final token = new Token(type, position);
        previous = token;
        return token;
    }

    /**
     * Advances the lexer position by the given number of characters.
     * @param count Number of characters to advance (default 1)
     */
    inline function advance(count:Int = 1) {
        while (count-- > 0 && pos < length) {
            if (input.charCodeAt(pos) == "\n".code) {
                line++;
                column = 1;
            }
            else {
                column++;
            }
            pos++;
        }
    }

    /**
     * Looks ahead in the input without advancing the position.
     * @param offset Number of characters to look ahead (default 1)
     * @return Character code at the offset position, or 0 if beyond input length
     */
    inline function peek(offset:Int = 1):Int {
        return pos + offset < length ? input.charCodeAt(pos + offset) : 0;
    }

    /**
     * Creates and throws a lexer error.
     * @param message Error message
     * @throws LexerError with the given message and current position
     */
    function error(message:String):Dynamic {
        throw new LexerError(message, makePosition());
    }

    /**
     * Skips whitespace characters (space and tab).
     */
    function skipWhitespace() {
        while (pos < length) {
            switch (input.charCodeAt(pos)) {
                case " ".code | "\t".code:
                    advance();
                case _:
                    return;
            }
        }
    }

    /**
     * Checks if a character is a digit (0-9).
     * @param c Character code to check
     * @* @return Whether the character is a digit
     */
    inline function isDigit(c:Int):Bool {
        return c >= "0".code && c <= "9".code;
    }

    /**
     * Checks if a character is valid as the start of an identifier.
     * Valid identifier starts are letters and underscore.
     * @param c Character code to check
     * @return Whether the character can start an identifier
     */
    inline function isIdentifierStart(c:Int):Bool {
        return (c >= "a".code && c <= "z".code) ||
               (c >= "A".code && c <= "Z".code) ||
                c == "_".code;
    }

    /**
     * Checks if a character is valid as part of an identifier.
     * Valid identifier parts are letters, numbers, and underscore.
     * @param c Character code to check
     * @return Whether the character can be part of an identifier
     */
    inline function isIdentifierPart(c:Int):Bool {
        return isIdentifierStart(c) || isDigit(c);
    }

}