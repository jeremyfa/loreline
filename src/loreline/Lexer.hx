package loreline;

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
    LString(s:String, ?attachments:Array<LStringAttachment>);
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
    }

    /**
     * Converts the entire input into an array of tokens.
     * @return Array of tokens
     */
    public function tokenize():Array<Token> {
        final tokens = [];
        while (true) {
            final token = nextToken();
            tokens.push(token);
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
            case "(".code: advance(); makeToken(LParen, startPos);
            case ")".code: advance(); makeToken(RParen, startPos);
            case "[".code: advance(); makeToken(LBracket, startPos);
            case "]".code: advance(); makeToken(RBracket, startPos);
            case ":".code: advance(); makeToken(Colon, startPos);
            case ",".code: advance(); makeToken(Comma, startPos);
            case ".".code: advance(); makeToken(Dot, startPos);
            case '"'.code: readString(startPos);
            case c if (isDigit(c)): readNumber();
            case c if (isIdentifierStart(c)): readIdentifier();

            case "+".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpPlusAssign, startPos);
                } else {
                    advance();
                    makeToken(OpPlus, startPos);
                }

            case "-".code:
                if (peek() == ">".code) {
                    advance(2);
                    makeToken(Arrow, startPos);
                } else if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpMinusAssign, startPos);
                } else {
                    advance();
                    makeToken(OpMinus, startPos);
                }

            case "*".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpMultiplyAssign, startPos);
                } else {
                    advance();
                    makeToken(OpMultiply, startPos);
                }

            case "/".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpDivideAssign, startPos);
                } else if (peek() == "/".code) {
                    return readLineComment();
                } else if (peek() == "*".code) {
                    return readMultiLineComment();
                } else {
                    advance();
                    makeToken(OpDivide, startPos);
                }

            case "&".code:
                if (peek() == "&".code) {
                    advance(2);
                    makeToken(OpAnd, startPos);
                } else {
                    advance();
                    error('Expected &');
                }

            case "|".code:
                if (peek() == "|".code) {
                    advance(2);
                    makeToken(OpOr, startPos);
                } else {
                    advance();
                    error('Expected |');
                }

            case "!".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpNotEquals, startPos);
                } else {
                    advance();
                    makeToken(OpNot, startPos);
                }

            case "=".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpEquals, startPos);
                } else {
                    advance();
                    makeToken(OpAssign, startPos);
                }

            case ">".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpGreaterEq, startPos);
                } else {
                    advance();
                    makeToken(OpGreater, startPos);
                }

            case "<".code:
                if (peek() == "=".code) {
                    advance(2);
                    makeToken(OpLessEq, startPos);
                } else {
                    advance();
                    makeToken(OpLess, startPos);
                }

            case _: error('Unexpected character: ${String.fromCharCode(c)}');
        }

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
        } else {
            advance();
        }
        return makeToken(LineBreak, start);
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

        while (pos < length) {
            final c = input.charCodeAt(pos);

            if (escaped) {
                buf.addChar("\\".code);
                buf.addChar(c);
                escaped = false;
                advance();
                currentColumn += 2;
            } else if (c == "\\".code) {
                escaped = true;
                advance();
            } else if (c == '"'.code && tagStart == -1) {
                advance();
                attachments.sort(compareAttachments);
                return makeToken(LString(
                    buf.toString(),
                    attachments.length > 0 ? attachments : null
                ), stringStart);
            } else if (c == "<".code) {
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
            } else if (c == ">".code) {
                buf.addChar(c);
                advance();
                currentColumn++;
                if (tagStart != -1) {
                    attachments.push(Tag(tagIsClosing, tagStart, buf.length - tagStart));
                    tagStart = -1;
                }
            } else if (c == "$".code && !escaped) {
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
                    } else if (isIdentifierStart(input.charCodeAt(pos))) {
                        final interpPos = new Position(interpLine, interpColumn + 1, pos);
                        final tokens = readFieldAccessInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.substr(tokenStartPos, interpLength));
                    } else {
                        error("Expected identifier or { after $");
                    }
                } catch (e:LexerError) {
                    if (e.pos == null) e.pos = new Position(interpLine, interpColumn, pos);
                    throw e;
                }

                currentColumn = interpColumn + (pos - tokenStartPos);
            } else {
                if (c == "\n".code) {
                    currentLine++;
                    currentColumn = 1;
                } else {
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
            } else {
                var tokenLength = switch (token.type) {
                    case Identifier(name): name.length;
                    case LString(s, _): s.length + 2;
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
        tokens.push(readIdentifierToken(stringStart));

        while (pos < length - 1 && input.charCodeAt(pos) == ".".code && isIdentifierStart(input.charCodeAt(pos + 1))) {
            final dotPos = makePositionRelativeTo(stringStart);
            advance();

            if (pos >= length || !isIdentifierStart(input.charCodeAt(pos))) {
                break;
            }
            tokens.push(new Token(Dot, dotPos));
            tokens.push(readIdentifierToken(stringStart));
        }

        return tokens;
    }

    /**
     * Reads an identifier token in a string interpolation context.
     * @param stringStart Starting position for position calculation
     * @return Identifier token
     */
    function readIdentifierToken(stringStart:Position):Token {
        final startPos = makePositionRelativeTo(stringStart);
        final startOffset = pos;

        while (pos < length) {
            final c = input.charCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }

        final name = input.substr(startOffset, pos - startOffset);
        return new Token(
            KEYWORDS.exists(name) ? KEYWORDS.get(name) : Identifier(name),
            startPos
        );
    }

    /**
     * Calculates a position relative to the start of a string.
     * @param stringStart Starting position for calculation
     * @return Adjusted position
     */
    function makePositionRelativeTo(stringStart:Position):Position {
        var line = stringStart.line;
        var column = stringStart.column;
        var i = stringStart.offset;

        while (i < pos) {
            if (input.charCodeAt(i) == "\n".code) {
                line++;
                column = 1;
            } else {
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
            } else if (input.charCodeAt(pos) == "/".code && peek() == "*".code) {
                nestLevel++;
                advance(2);
            } else {
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
        return makeToken(
            KEYWORDS.exists(word) ? KEYWORDS.get(word) : Identifier(word),
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
            } else {
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
     * @throws LexerError
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