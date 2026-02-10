package loreline;

using StringTools;
using loreline.Utf8;

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
    Interpolation(braces:Bool, inTag:Bool, expr:Tokens, start:Int, length:Int);

    /**
     * String formatting tag.
     * @param closing Whether this is a closing tag
     * @param start Starting position in the string
     * @param length Length of the tag
     */
    Tag(closing:Bool, start:Int, length:Int);

}

enum abstract StrictExprType(Int) {

    var Loose = 0;

    var Strict = 1;

    var Inherit = 2;

}

enum abstract TokenStackType(Int) {

    var ChoiceBrace;

    var ChoiceIndent;

    var StateBrace;

    var StateIndent;

    var CharacterBrace;

    var CharacterIndent;

    var BeatBrace;

    var BeatIndent;

    var Brace;

    var Indent;

    var Bracket;

    public function toString() {

        return switch abstract {
            case ChoiceBrace: 'ChoiceBrace';
            case ChoiceIndent: 'ChoiceIndent';
            case StateBrace: 'StateBrace';
            case StateIndent: 'StateIndent';
            case CharacterBrace: 'CharacterBrace';
            case CharacterIndent: 'CharacterIndent';
            case BeatBrace: 'BeatBrace';
            case BeatIndent: 'BeatIndent';
            case Brace: 'Brace';
            case Indent: 'Indent';
            case Bracket: 'Bracket';
        }

    }

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

    /** Function code */
    Function(name:Null<String>, args:Array<String>, code:String, external:Bool);

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
    /** Logical AND operator (&& / and) */
    OpAnd(word:Bool);
    /** Logical OR operator (|| / or) */
    OpOr(word:Bool);
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

    /** Increase indentation level */
    Indent;
    /** Decrease indentation level */
    Unindent;

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
            case [Indent, Indent]: true;
            case [Unindent, Unindent]: true;
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
            case [OpAnd(_), OpAnd(_)]: true;
            case [OpOr(_), OpOr(_)]: true;
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

    public static function isAssignOp(a:TokenType):Bool {
        return switch a {
            case OpAssign | OpPlusAssign | OpMinusAssign | OpMultiplyAssign | OpDivideAssign: true;
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

    /**
     * Checks if a token is a block start
     * @param a Token type to check
     * @return Whether the token type is a block start
     */
    public static function isBlockStart(a:TokenType):Bool {
        return switch a {
            case KwState | KwBeat | KwCharacter | KwChoice | KwIf: true;
            case _: false;
        }
    }

    public static function toCodeString(a:TokenType):String {
        return switch a {
            case KwImport: 'import';
            case KwState: 'state';
            case KwBeat: 'beat';
            case KwCharacter: 'character';
            case KwChoice: 'choice';
            case KwIf: 'if';
            case KwElse: 'else';
            case KwNew: 'new';
            case Function(_, _, _): 'function';
            case LString(_, _, _): 'string';
            case LNumber(_): 'number';
            case LBoolean(_): 'boolean';
            case LNull: 'null';
            case Identifier(name): 'identifier';
            case OpAssign: '=';
            case OpPlusAssign: '+=';
            case OpMinusAssign: '-=';
            case OpMultiplyAssign: '*=';
            case OpDivideAssign: '/=';
            case OpPlus: '+';
            case OpMinus: '-';
            case OpMultiply: '*';
            case OpDivide: '/';
            case OpModulo: '%';
            case OpEquals: '==';
            case OpNotEquals: '!=';
            case OpGreater: '>';
            case OpLess: '<';
            case OpGreaterEq: '>=';
            case OpLessEq: '<=';
            case OpAnd(word): word ? 'and' : '&&';
            case OpOr(word): word ? 'or' : '||';
            case OpNot: '!';
            case Arrow: '->';
            case Colon: ':';
            case Comma: ',';
            case Dot: '.';
            case LBrace: '{';
            case RBrace: '}';
            case LParen: '(';
            case RParen: ')';
            case LBracket: '[';
            case RBracket: ']';
            case CommentLine(content): 'comment';
            case CommentMultiLine(content): 'multiline comment';
            case Indent: 'indent';
            case Unindent: 'unindent';
            case LineBreak: 'line break';
            case Eof: 'end of file';
        }
    }

}

/**
 * Represents an array of tokens (a tokenized source code).
 */
typedef Tokens = Array<Token>;

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
@:keep class Lexer {

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
        "null" => TokenType.LNull,
        "and" => TokenType.OpAnd(true),
        "or" => TokenType.OpOr(true)
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
    var tokenized:Tokens;

    /**
     * A stack to keep track of whether we are inside a `beat` or a `state`/`character` block.
     * Depending on that, the rules for reading unquoted string tokens are different.
     */
    var stack:Array<TokenStackType>;

    /**
     * The token type that will be added to the `stack`
     * next time we find a `LBrace` token
     */
    var nextBlock:TokenStackType;

    /**
     * When last value is true, that means only strictly
     * correct expressions are accepted, thus
     * unquoted strings will be disabled. Mostly
     * used to handle interpolated values in strings
     * or object/array literals in strict expressions that loosen the rules
     */
    var strictExprs:Array<StrictExprType>;

    /** Current indentation level (number of spaces/tabs) */
    var indentLevel:Int = 0;

    /** Stack of indentation levels */
    var indentStack:Array<Int> = [];

    /** Queue of generated indentation tokens */
    var indentTokens:Tokens = [];

    /** The indentation size (e.g., 4 spaces or 1 tab) */
    var indentSize:Int = 4;

    /** Whether tabs are allowed for indentation */
    var allowTabs:Bool = true;

    /** Errors collected during lexing, if any */
    var errors:Array<LexerError> = null;

    /**
     * Creates a new lexer for the given input.
     * @param input The source code to lex
     */
    public function new(input:String) {
        this.input = input;
        this.length = input.uLength();
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
        this.nextBlock = Brace;
        this.tokenized = null;
        this.strictExprs = [];
        this.indentLevel = 0;
        this.indentStack = [0];
        this.indentTokens = [];
    }

    /**
     * Converts the entire input into an array of tokens.
     * @return Array of tokens
     */
    public function tokenize():Tokens {
        final tokens = [];
        this.tokenized = tokens;
        while (true) {
            final token = nextToken();

            // Handle EOF
            if (token.type == Eof) {
                // Generate any remaining unindents
                if (indentStack.length > 1) {
                    var count = indentStack.length - 1;
                    for (_ in 0...count) {
                        tokens.push(makeToken(Unindent));
                    }
                }
                break;
            }

            tokens.push(token);

            switch token.type {
                case KwState:
                    nextBlock = StateIndent;
                case KwCharacter:
                    nextBlock = CharacterIndent;
                case KwBeat:
                    nextBlock = BeatIndent;
                case KwChoice:
                    nextBlock = ChoiceIndent;
                case LBrace:
                    stack.push(switch nextBlock {
                        case ChoiceBrace | ChoiceIndent: ChoiceBrace;
                        case StateBrace | StateIndent: StateBrace;
                        case CharacterBrace | CharacterIndent: CharacterBrace;
                        case BeatBrace | BeatIndent: BeatIndent;
                        case Brace | Indent | Bracket: Brace;
                    });
                    nextBlock = Brace;
                case Indent:
                    stack.push(switch nextBlock {
                        case ChoiceBrace | ChoiceIndent: ChoiceIndent;
                        case StateBrace | StateIndent: StateIndent;
                        case CharacterBrace | CharacterIndent: CharacterIndent;
                        case BeatBrace | BeatIndent: BeatIndent;
                        case Brace | Indent | Bracket: Indent;
                    });
                    nextBlock = Brace;
                case LBracket:
                    stack.push(Bracket);
                    nextBlock = Brace;
                case RBrace | Unindent | RBracket:
                    stack.pop();
                    nextBlock = Brace;
                case _:
            }
        }
        return tokens;
    }

    /**
     * Reads and returns the next token from the input.
     * @return The next token
     * @throws LexerError if invalid input is encountered
     */
    public function nextToken():Token {
        // Check for queued indentation tokens first
        if (indentTokens.length > 0) {
            return indentTokens.shift();
        }

        skipWhitespace();

        if (pos >= length) {
            return makeToken(Eof);
        }

        startLine = line;
        startColumn = column;
        final c = input.uCharCodeAt(pos);

        if (c == "\n".code || c == "\r".code) {
            final lineBreakToken = readLineBreak();

            // After a line break, check for indentation changes
            var currentIndent = countIndentation();

            if (currentIndent > indentStack[indentStack.length - 1]) {
                // Indent - just check that it's more than previous level
                indentStack.push(currentIndent);
                indentTokens.push(makeToken(Indent));
            } else if (currentIndent < indentStack[indentStack.length - 1]) {
                // Unindent - pop until we find a matching or lower level
                while (indentStack.length > 0 && currentIndent < indentStack[indentStack.length - 1]) {
                    indentStack.pop();
                    indentTokens.push(makeToken(Unindent));
                }
            }

            return lineBreakToken;
        }

        final startPos = makePosition();

        // If following import keyword, read import value
        if (tokenized.length > 0 && tokenized[tokenized.length - 1].type == KwImport) {
            return readImportValue(c, startPos);
        }

        return switch (c) {
            case "{".code: advance(); makeToken(LBrace, startPos);
            case "}".code: advance(); makeToken(RBrace, startPos);
            case '"'.code: readString(startPos);
            case "[".code: advance(); makeLooseOrStrictAfterBracket(); makeToken(LBracket, startPos);
            case _:
                tryReadUnquotedString() ?? switch (c) {
                    case "]".code: advance(); strictExprs.pop(); makeToken(RBracket, startPos);
                    case "(".code: advance(); makeStrictIfFollowingCallable(); makeToken(LParen, startPos);
                    case ")".code: advance(); strictExprs.pop(); makeToken(RParen, startPos);
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
                            makeToken(OpAnd(false), startPos);
                        }
                        else {
                            advance();
                            error('Expected &', false);
                            makeToken(OpAnd(false), startPos);
                        }

                    case "|".code:
                        if (peek() == "|".code) {
                            advance(2);
                            makeToken(OpOr(false), startPos);
                        }
                        else {
                            advance();
                            error('Expected |', false);
                            makeToken(OpOr(false), startPos);
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

                    case _:
                        error('Unexpected character: ${String.fromCharCode(c)}', true);
                        null;
                }
        }

    }

    function countIndentation():Int {
        var pos = this.pos;
        var spaces = 0;

        // Count spaces/tabs
        while (pos < length) {
            final c = input.uCharCodeAt(pos);
            if (c == " ".code) {
                spaces++;
            } else if (c == "\t".code) {
                spaces++;
            } else {
                break;
            }
            pos++;
        }

        // Check if line is empty or only whitespace
        if (pos >= length || input.uCharCodeAt(pos) == "\n".code || input.uCharCodeAt(pos) == "\r".code) {
            // Return previous indentation level for empty lines
            return indentStack[indentStack.length - 1];
        }

        return spaces;
    }

    /**
     * Returns the token type of the parent block.
     * @return The token type of the parent block or KwBeat if at top level
     */
    function parentBlockType():TokenType {

        var i = stack.length - 1;
        while (i >= 0) {
            if (stack[i] != Brace && stack[i] != Indent && stack[i] != Bracket) {
                return switch stack[i] {
                    case ChoiceBrace | ChoiceIndent: KwBeat;
                    case StateBrace | StateIndent: KwState;
                    case CharacterBrace | CharacterIndent: KwCharacter;
                    case BeatBrace | BeatIndent: KwBeat;
                    case Brace: LBrace;
                    case Indent: Indent;
                    case Bracket: LBracket;
                };
            }
            i--;
        }

        // Assume top level is like being in a beat
        return KwBeat;

    }

    /**
     * Checks if currently in a beat block.
     * @return True if inside a beat block, false otherwise
     */
    function inBeat():Bool {
        return parentBlockType() == KwBeat;
    }

    /**
     * Checks if currently at the root level of a choice block (not inside an option body).
     * @return True if the top of the stack is a choice entry, false otherwise
     */
    function inChoiceRoot():Bool {
        return stack.length > 0
            && (stack[stack.length - 1] == ChoiceIndent || stack[stack.length - 1] == ChoiceBrace);
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
        if (input.uCharCodeAt(pos) == "\r".code) {
            advance();
            if (pos < length && input.uCharCodeAt(pos) == "\n".code) {
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
        if (this.length == 0) {
            return null;
        }

        // Check if the first character is a valid identifier start
        var firstChar = input.uCharCodeAt(pos + 0);
        if (!isIdentifierStart(firstChar)) {
            return null;
        }

        // Keep track of where the identifier ends
        var identifierLength = 1;

        // Check subsequent characters until we find an invalid one
        // or reach the end of the string
        while (identifierLength < this.length) {
            if (!isIdentifierPart(input.uCharCodeAt(pos + identifierLength))) {
                break;
            }
            identifierLength++;
        }

        // Return the substring that contains our identifier
        return input.uSubstr(pos, identifierLength);
    }

    /**
     * Helper function to skip whitespace and comments
     */
    extern inline overload function skipWhitespaceAndComments(pos:Int, stopNextLine:Bool = false):Int {
        return _skipWhitespaceAndComments(pos, stopNextLine);
    }

    /**
     * Helper function to skip whitespace and comments
     */
    extern inline overload function skipWhitespaceAndComments(stopNextLine:Bool = false):Void {
        final newPos = skipWhitespaceAndComments(pos, stopNextLine);
        while (pos < newPos) {
            advance();
        }
    }

    function _skipWhitespaceAndComments(pos:Int, stopNextLine:Bool = false):Int {
        if (stopNextLine) {
            return _skipWhitespaceAndCommentsStopNextLine(pos);
        }
        else {
            final startPos = pos;
            var foundContent = false;
            while (pos < this.length) {
                // Skip whitespace
                while (pos < this.length && (input.uCharCodeAt(pos) == " ".code || input.uCharCodeAt(pos) == "\t".code)) {
                    pos++;
                    foundContent = true;
                }

                // Check for comments
                if (pos < this.length - 1) {
                    if (input.uCharCodeAt(pos) == "/".code) {
                        if (input.uCharCodeAt(pos + 1) == "/".code) {
                            // Single line comment - invalid in single line
                            pos = startPos;
                            return pos;
                        }
                        else if (input.uCharCodeAt(pos + 1) == "*".code) {
                            // Multi-line comment
                            pos += 2;
                            foundContent = true;
                            var commentClosed = false;
                            while (pos < this.length - 1) {
                                if (input.uCharCodeAt(pos) == "*".code && input.uCharCodeAt(pos + 1) == "/".code) {
                                    pos += 2;
                                    commentClosed = true;
                                    break;
                                }
                                pos++;
                            }
                            if (!commentClosed) {
                                pos = startPos;
                                return pos;
                            }
                            continue;
                        }
                    }
                }
                break;
            }
            return foundContent ? pos : startPos;
        }
    }

    function _skipWhitespaceAndCommentsStopNextLine(pos:Int):Int {
        final startPos = pos;
        var foundContent = false;
        var isNextLine = false;
        while (pos < this.length) {
            // Skip whitespace including newlines
            while (pos < this.length) {
                final c = input.uCharCodeAt(pos);
                if (c == " ".code || c == "\t".code || c == "\r".code || (!isNextLine && c == "\n".code)) {
                    if (c == "\n".code) {
                        isNextLine = true;
                    }
                    pos++;
                    foundContent = true;
                }
                else {
                    break;
                }
            }

            // Check for comments
            if (pos < this.length - 1 && !isNextLine) {
                if (input.uCharCodeAt(pos) == "/".code) {
                    if (input.uCharCodeAt(pos + 1) == "/".code) {
                        // Single line comment - skip until end of line
                        pos += 2; // Skip //
                        foundContent = true;
                        while (pos < this.length && input.uCharCodeAt(pos) != "\n".code && input.uCharCodeAt(pos) != "\r".code) {
                            pos++;
                        }
                        continue; // Continue to process potential newline after comment
                    }
                    else if (input.uCharCodeAt(pos + 1) == "*".code) {
                        // Multi-line comment
                        pos += 2; // Skip /*
                        foundContent = true;
                        var commentClosed = false;
                        while (pos < this.length - 1) {
                            if (input.uCharCodeAt(pos) == "*".code && input.uCharCodeAt(pos + 1) == "/".code) {
                                pos += 2; // Skip */
                                commentClosed = true;
                                break;
                            }
                            pos++;
                        }
                        if (!commentClosed) {
                            pos = startPos;
                            return pos; // Unclosed comment, return original position
                        }
                        continue;
                    }
                }
            }

            break;
        }

        return foundContent ? pos : startPos;

    }

    /**
     * Returns whether the input at the given position is the start of an if condition.
     * @param pos Position to check from
     * @return True if an if condition starts at the position, false otherwise
     */
    function isIfStart(pos:Int):Bool {
        pos = skipWhitespaceAndComments(pos);

        // Check "if" literal first
        if (input.uCharCodeAt(pos) != "i".code) return false;
        pos++;

        if (input.uCharCodeAt(pos) != "f".code) return false;
        pos++;

        // Save initial position to restore it later
        var startPos = pos;

        // Helper function to read identifier
        inline function readIdent():Bool {
            var result = true;
            final len = this.length;

            if (pos >= len) {
                result = false;
            }
            else if (pos + 1 < len && input.uCharCodeAt(pos) == "o".code && input.uCharCodeAt(pos + 1) == "r".code && !isIdentifierStart(input.uCharCodeAt(pos + 2))) {
                result = false;
            }
            else if (pos + 2 < len && input.uCharCodeAt(pos) == "a".code && input.uCharCodeAt(pos + 1) == "n".code && input.uCharCodeAt(pos + 2) == "d".code && !isIdentifierStart(input.uCharCodeAt(pos + 3))) {
                result = false;
            }
            else {
                var c = input.uCharCodeAt(pos);

                // First char must be letter or underscore
                if (!isIdentifierStart(c)) {
                    result = false;
                }
                else {
                    pos++;

                    // Continue reading identifier chars
                    while (pos < this.length) {
                        c = input.uCharCodeAt(pos);
                        if (!isIdentifierPart(c)) break;
                        pos++;
                    }
                }
            }

            return result;
        }

        pos = skipWhitespaceAndComments(pos);

        // Handle optional ! for negation
        if (pos < this.length && input.uCharCodeAt(pos) == "!".code) {
            pos++;
            pos = skipWhitespaceAndComments(pos);
        }

        // If directly followed with (, that's a valid if
        if (input.uCharCodeAt(pos) == "(".code) {
            return true;
        }

        // If "if" is directly followed by an identifier start (without space), that's not a if
        if (pos == startPos && isIdentifierStart(input.uCharCodeAt(startPos))) {
            return false;
        }

        // Must start with identifier or opening parenthesis
        if (pos >= this.length || !isIdentifierStart(input.uCharCodeAt(pos))) {
            return false;
        }

        while (pos < this.length) {
            if (input.uCharCodeAt(pos) == "(".code) {
                // Function call
                return true;
            } else {
                if (!readIdent()) {
                    return false;
                }
            }

            pos = skipWhitespaceAndComments(pos);
            if (pos >= this.length) {
                return true;
            }

            var c = input.uCharCodeAt(pos);

            // Handle dot access
            if (c == ".".code) {
                pos++;
                pos = skipWhitespaceAndComments(pos);
                if (!readIdent()) {
                    return true;
                }
                pos = skipWhitespaceAndComments(pos);
                if (pos >= this.length) {
                    return true;
                }
                c = input.uCharCodeAt(pos);
            }

            // Handle bracket access
            if (c == "[".code) {
                pos++;
                var bracketLevel = 1;
                while (pos < this.length && bracketLevel > 0) {
                    c = input.uCharCodeAt(pos);
                    if (c == "[".code) bracketLevel++;
                    if (c == "]".code) bracketLevel--;
                    pos++;
                }
                pos = skipWhitespaceAndComments(pos);
                if (pos >= this.length) {
                    return true;
                }
                c = input.uCharCodeAt(pos);
            }

            // Check for and delimiter
            if (c == "a".code && input.uCharCodeAt(pos + 1) == "n".code && input.uCharCodeAt(pos + 2) == "d".code && !isIdentifierStart(input.uCharCodeAt(pos + 3))) {
                return true;
            }

            // Check for or delimiter
            if (c == "o".code && input.uCharCodeAt(pos + 1) == "r".code && !isIdentifierStart(input.uCharCodeAt(pos + 2))) {
                return true;
            }

            // Check for various delimiters typical from if condition
            if (c == "(".code || c == "&".code || c == "|".code || ((input.uCharCodeAt(pos + 1) == "=".code) && c == "=".code) || c == ">".code || c == "<".code || (c == "!".code && input.charCodeAt(pos + 1) == "=".code) || (input.uCharCodeAt(pos + 1) != "=".code && (c == "+".code || c == "-".code || c == "*".code || c == "/".code || c == "{".code))) {
                return true;
            }

            // If we're at end or newline, it's valid
            if (c == "\n".code || c == "\r".code || pos >= this.length) {
                pos = startPos;
                return true;
            }

            // Any other character invalidates it
            return false;
        }

        // If we get here, we're at end of input
        return true;
    }

    /**
     * Returns whether the input at the given position is the start of an identifier expression.
     * @param pos Position to check from
     * @return True if an identifier expression starts at the position, false otherwise
     */
    function isIdentifierExpressionStart(pos:Int, lowercaseIdentOnly:Bool):Bool {
        pos = skipWhitespaceAndComments(pos);

        // Helper function to read identifier
        inline function readIdent(lowercaseIdentOnly = false):Bool {
            var result = true;

            if (pos >= this.length) {
                result = false;
            }
            else {
                var isUnderscore:Bool = false;
                var c = input.uCharCodeAt(pos);
                isUnderscore = (c == "_".code);

                // First char must be letter or underscore
                if (!isIdentifierStart(c) || (lowercaseIdentOnly && !isUnderscore && !isLowerCase(c))) {
                    result = false;
                }
                else {
                    pos++;

                    // Continue reading identifier chars
                    while (pos < this.length) {
                        final wasUnderscore = isUnderscore;
                        c = input.uCharCodeAt(pos);
                        isUnderscore = (c == "_".code);
                        if (!isIdentifierPart(c)) break;
                        if (lowercaseIdentOnly && wasUnderscore && !isUnderscore && !isLowerCase(c)) {
                            result = false;
                            break;
                        }
                        pos++;
                    }
                }
            }

            return result;
        }

        pos = skipWhitespaceAndComments(pos);

        // Must start with identifier or opening parenthesis
        if (pos >= this.length) {
            return false;
        }

        // Check for function call
        if (input.uCharCodeAt(pos) == "(".code) {
            return true;
        }

        // Must start with identifier
        if (!readIdent(lowercaseIdentOnly)) {
            return false;
        }

        // Keep reading dot access, array access segments
        while (pos < this.length) {
            pos = skipWhitespaceAndComments(pos);
            if (pos >= this.length) {
                return true;
            }

            var c = input.uCharCodeAt(pos);

            // If we hit a non-special char after identifier,
            // and it's not a dot or bracket, expression is invalid
            if (!isWhitespace(c) && c != ".".code && c != "[".code &&
                c != "\n".code && c != "\r".code && c != "/".code) {
                return false;
            }

            // End of line or comment is valid
            if (c == "\n".code || c == "\r".code ||
                (c == "/".code && pos + 1 < this.length &&
                 (input.uCharCodeAt(pos + 1) == "/".code ||
                  input.uCharCodeAt(pos + 1) == "*".code))) {
                return true;
            }

            // Handle dot access
            if (c == ".".code) {
                pos++;
                pos = skipWhitespaceAndComments(pos);

                // A dot by itself at end is valid
                if (pos >= this.length) {
                    return true;
                }

                // Must be followed by identifier
                if (!readIdent()) {
                    return true; // Trailing dot is valid
                }
                continue;
            }

            // Handle array access
            if (c == "[".code) {
                pos++;
                var bracketLevel = 1;
                while (pos < this.length && bracketLevel > 0) {
                    c = input.uCharCodeAt(pos);
                    if (c == "[".code) bracketLevel++;
                    if (c == "]".code) bracketLevel--;
                    pos++;
                }
                continue;
            }

            // Skip whitespace
            if (isWhitespace(c)) {
                pos++;
                continue;
            }

            break;
        }

        return true;
    }

    /**
     * Returns whether the input at the given position is a valid transition start.
     * A valid transition consists of "->" followed by an identifier, with optional
     * whitespace and comments in between. Nothing but whitespace and comments can
     * follow the identifier.
     * @param pos Position to check from
     * @return True if a valid transition starts at the position, false otherwise
     */
    function isTransitionStart(pos:Int):Bool {

        // Check for ->
        if (input.uCharCodeAt(pos) != "-".code || pos >= this.length - 1 || input.uCharCodeAt(pos + 1) != ">".code) {
            return false;
        }
        pos += 2;

        // Skip whitespace and comments between -> and identifier
        pos = skipWhitespaceAndComments(pos);

        // Read target
        if (pos >= this.length) {
            return false;
        }

        final char = input.uCharCodeAt(pos);
        if (char == ".".code) {
            // Move past dot
            pos++;
        }
        else if (isIdentifierPart(input.uCharCodeAt(pos))) {
            // Move past identifier
            pos++;
            while (pos < this.length && isIdentifierPart(input.uCharCodeAt(pos))) {
                pos++;
            }
        }
        else {
            return false;
        }

        // Skip any trailing comments
        pos = skipWhitespaceAndComments(pos);

        // Check that we're at end of line, end of input, or only have whitespace/comments left
        if (pos < this.length) {
            var c = input.uCharCodeAt(pos);
            if (c != "\n".code && c != "\r".code && c != " ".code && c != "\t".code && c != "/".code) {
                return false;
            }
        }

        // Return success
        return true;
    }

    function isInsertionStart(pos:Int):Bool {

        // Check for +
        if (input.uCharCodeAt(pos) != "+".code) {
            return false;
        }
        pos += 1;

        // Skip whitespace and comments between -> and identifier
        pos = skipWhitespaceAndComments(pos);

        // Read target
        if (pos >= this.length) {
            return false;
        }

        final char = input.uCharCodeAt(pos);
        if (char == ".".code) {
            // Move past dot
            pos++;
        }
        else if (isIdentifierPart(input.uCharCodeAt(pos))) {
            // Move past identifier
            pos++;
            while (pos < this.length && isIdentifierPart(input.uCharCodeAt(pos))) {
                pos++;
            }
        }
        else {
            return false;
        }

        // Skip any trailing comments
        pos = skipWhitespaceAndComments(pos);

        // Check that we're at end of line, end of input, or only have whitespace/comments left
        if (pos < this.length) {
            var c = input.uCharCodeAt(pos);
            if (c != "\n".code && c != "\r".code && c != " ".code && c != "\t".code && c != "/".code) {
                return false;
            }
        }

        // Return success
        return true;
    }

    /**
     * Returns whether the input at the given position begins with a label pattern (identifier:).
     * @param pos Position to check from
     * @return True if a label starts at the position, false otherwise
     */
    function isLabelStart(pos:Int):Bool {
        // Skip any whitespace and comments before looking for label
        pos = skipWhitespaceAndComments(pos);

        // Check if we have a valid identifier
        if (!isIdentifierStart(input.uCharCodeAt(pos))) {
            return false;
        }

        // Track the initial position
        var startPos = pos;

        // Read through identifier characters
        pos++;
        while (pos < length && isIdentifierPart(input.uCharCodeAt(pos))) {
            pos++;
        }

        // Skip whitespace between identifier and colon
        while (pos < length && isWhitespace(input.uCharCodeAt(pos))) {
            pos++;
        }

        // Must end with a colon
        if (pos >= length || input.uCharCodeAt(pos) != ":".code) {
            return false;
        }

        // Verify that what we read is an identifier is not a keyword
        final word = input.uSubstr(startPos, pos - startPos);
        if (KEYWORDS.exists(word)) {
            return false;
        }

        return true;
    }

    /**
     * Returns whether the input at the given position is the start of a function or method call.
     * @param pos Position to check from
     * @return True if a function call starts at the position, false otherwise
     */
    function isCallStart(pos:Int):Bool {

        // Save initial position to restore it later
        var startPos = pos;

        // Helper function to read identifier
        inline function readIdent():Bool {
            var result = true;

            if (pos >= this.length) {
                result = false;
            }
            else {
                var c = input.uCharCodeAt(pos);

                // First char must be letter or underscore
                if (!isIdentifierStart(c)) {
                    result = false;
                }
                else {
                    pos++;

                    // Continue reading identifier chars
                    while (pos < this.length) {
                        c = input.uCharCodeAt(pos);
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
        while (pos < this.length) {
            pos = skipWhitespaceAndComments(pos);

            if (pos >= this.length) {
                pos = startPos;
                return false;
            }

            var c = input.uCharCodeAt(pos);

            // Found opening parenthesis - success!
            if (c == "(".code) {
                pos = startPos;
                return true;
            }

            // Handle dot access
            if (c == ".".code) {
                pos++;
                pos = skipWhitespaceAndComments(pos);
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
                while (pos < this.length) {
                    if (input.uCharCodeAt(pos) == "]".code) {
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
     * Returns whether the input at the given position is the start of an assignment.
     * @param pos Position to check from
     * @return True if an assignment starts at the position, false otherwise
     */
    function isAssignStart(pos:Int, strict:Bool):Bool {

        // Helper function to read identifier
        inline function readIdent():Bool {
            var result = true;
            final startPos = pos;

            if (pos >= this.length) {
                result = false;
            }
            else {
                var c = input.uCharCodeAt(pos);

                // First char must be letter or underscore
                if (!isIdentifierStart(c)) {
                    result = false;
                }
                else {
                    pos++;

                    // Continue reading identifier chars
                    while (pos < this.length) {
                        c = input.uCharCodeAt(pos);
                        if (!isIdentifierPart(c)) break;
                        pos++;
                    }
                }
            }

            if (pos == startPos + 2 && input.uCharCodeAt(startPos) == "i".code && input.uCharCodeAt(startPos + 1) == "f".code) {
                // `if` keyword isn't valid here
                return false;
            }

            return result;
        }

        // Must start with identifier
        if (strict && !readIdent()) {
            return false;
        }

        // Keep reading segments until we find opening parenthesis
        var isEscape:Bool = false;
        while (pos < this.length) {
            pos = skipWhitespaceAndComments(pos);

            if (pos >= this.length) {
                return false;
            }

            var c = input.uCharCodeAt(pos);

            // Found assign operator
            if (!isEscape && (c == "=".code ||
                (input.uCharCodeAt(pos + 1) == "=".code && (c == "+".code || c == "-".code || c == "*".code || c == "/".code)))) {
                return true;
            }

            if (strict) {
                // Handle dot access
                if (c == ".".code) {
                    pos++;
                    pos = skipWhitespaceAndComments(pos);
                    if (!readIdent()) {
                        return false;
                    }
                    continue;
                }

                // Handle bracket access
                if (c == "[".code) {
                    // Skip everything until closing bracket
                    pos++;
                    while (pos < this.length) {
                        if (input.uCharCodeAt(pos) == "]".code) {
                            pos++;
                            break;
                        }
                        pos++;
                    }
                    continue;
                }

                // Any other character means this isn't an assign
                return false;
            }
            else {
                // End of line in loose mode: not an assign
                if (c == "\\".code) {
                    isEscape = true;
                    pos++;
                }
                else if (c == "\r".code || c == "\n".code) {
                    return false;
                }
                else if (isIdentifierStart(c)) {
                    if (!readIdent()) return false;
                }
                else {
                    pos++;
                }
            }
        }

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
            while (pos < this.length && (input.uCharCodeAt(pos) == " ".code || input.uCharCodeAt(pos) == "\t".code)) {
                pos++;
            }
        }

        return pos < this.length && input.uCharCodeAt(pos) == ":".code;

    }

    /**
     * If we are currently right after a label, return the related identifier token index (before colon),
     * or -1 if not after a label.
     */
    function afterLabelIdentifierToken(inSameLine:Bool = true):Int {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];

            if (!token.type.isComment() && (inSameLine || (token.type != LineBreak && token.type != Indent && token.type != Unindent))) {
                if (token.type == Colon && i > 0 && tokenized[i-1].type.isIdentifier()) {
                    return i - 1;
                }
                return -1;
            }

            i--;
        }

        return -1;

    }

    /**
     * Checks if a dialogue statement continues over multiple lines.
     *
     * @param labelIdentifierToken The token containing the character name before the colon
     * @return The indentation of the multiline dialogue or -1
     */
    function isStartingMultilineDialogue(labelIdentifierTokenIndex:Int):Int {

        final labelIdentifierToken = tokenized[labelIdentifierTokenIndex];
        var i = labelIdentifierTokenIndex + 1;
        while (tokenized[i].type != Colon) {
            i++;
        }
        var pos = tokenized[i].pos.offset + 1;

        // Calculate the indentation level of the label identifier token
        final labelColumn = labelIdentifierToken.pos.column;

        // First, check if the first line contains only tags or is empty
        // A valid tag pattern would be: whitespace* (<...> whitespace*)+
        var onlyTagsOnFirstLine = true;
        var insideTag = false;

        // Trim leading whitespace
        while (pos < length) {
            final c = input.uCharCodeAt(pos);
            if (c == " ".code || c == "\t".code) {
                pos++;
            } else {
                break;
            }
        }

        // Check if there's any content besides tags and whitespace on the first line
        while (pos < length) {
            final c = input.uCharCodeAt(pos);

            // Found end of first line
            if (c == "\n".code || c == "\r".code) {
                break;
            }

            // Handle comments
            if (c == "/".code && pos + 1 < length) {
                final next = input.uCharCodeAt(pos + 1);
                if (next == "/".code) {
                    // Single-line comment, skip to end of line
                    break;
                } else if (next == "*".code) {
                    // Skip multiline comment
                    pos += 2; // Skip /*
                    while (pos < length) {
                        if (input.uCharCodeAt(pos) == "*".code &&
                            pos + 1 < length &&
                            input.uCharCodeAt(pos + 1) == "/".code) {
                                pos += 2; // Skip */
                            break;
                        }
                        pos++;
                    }
                    continue;
                }
            }

            // Handle tags
            if (c == "<".code) {
                insideTag = true;
            } else if (c == ">".code) {
                insideTag = false;
            } else if (!insideTag && !(c == " ".code || c == "\t".code)) {
                // Found non-tag, non-whitespace content on first line
                onlyTagsOnFirstLine = false;
                break;
            }

            pos++;
        }

        // If the first line has text content (not just tags), this isn't a multiline dialogue
        if (!onlyTagsOnFirstLine) {
            return -1;
        }

        final prevPos = pos;
        pos = skipWhitespaceAndComments(pos, true);
        if (pos <= prevPos) {
            // Not indented
            return -1;
        }

        // Compute indent
        var indent = 0;
        var tmpPos = pos;
        while (tmpPos > 0 && (input.uCharCodeAt(tmpPos-1) == " ".code || input.uCharCodeAt(tmpPos-1) == "\t".code)) {
            indent++;
            tmpPos--;
        }

        // Check that it's enough
        if (indent <= labelColumn - 1) {
            return -1;
        }

        // Check that there is content in this line
        pos = skipWhitespaceAndComments(pos, false);
        if (isWhitespace(input.uCharCodeAt(pos)) || (input.uCharCodeAt(pos) == "/".code && input.uCharCodeAt(pos+1) == "/".code)) {
            return -1;
        }

        return indent;

    }

    function isContinuingMultilineText(pos:Int, indent:Int):Bool {

        if (input.uCharCodeAt(pos) == "/".code && input.uCharCodeAt(pos+1) == "/".code) {
            while (pos < length && input.uCharCodeAt(pos) != "\r".code && input.uCharCodeAt(pos) != "\n".code) {
                pos++;
            }
        }

        if (input.uCharCodeAt(pos) == "\r".code) {
            pos++;
        }

        if (input.uCharCodeAt(pos) == "\n".code) {
            pos++;
        }
        else {
            return false;
        }

        var computedIndent = 0;
        while (input.uCharCodeAt(pos) == " ".code || input.uCharCodeAt(pos) == "\t".code) {
            computedIndent++;
            pos++;
        }

        if (computedIndent != indent) {
            return false;
        }

        // Check that there is content in this line
        pos = skipWhitespaceAndComments(pos, false);
        if (isWhitespace(input.uCharCodeAt(pos)) || input.uCharCodeAt(pos) == "\r".code || input.uCharCodeAt(pos) == "\n".code || (input.uCharCodeAt(pos) == "/".code && input.uCharCodeAt(pos+1) == "/".code)) {
            return false;
        }

        return true;

    }

    function isAfterComma():Bool {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];

            if (!token.type.isComment() && token.type != LineBreak && token.type != Indent && token.type != Unindent) {
                return (token.type == Comma);
            }

            i--;
        }

        return false;

    }

    function isAfterLBracket():Bool {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];

            if (!token.type.isComment() && token.type != LineBreak && token.type != Indent && token.type != Unindent) {
                return (token.type == LBracket);
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

        var i = stack.length - 1;
        while (i >= 0 && stack[i] == Indent) {
            i--;
        }
        return i >= 0 && stack[i] == Bracket;

    }

    function followsAssignStart() {

        var i = tokenized.length - 1;
        while (i >= 0) {
            final token = tokenized[i];
            if (token.type.isComment() || token.type == Indent || token.type == Unindent) {
                i--;
            }
            else if (token.type.isAssignOp()) {
                return true;
            }
            else {
                return false;
            }
        }

        return false;

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
            if (token.type.isComment() || token.type == Indent || token.type == Unindent) {
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

            if (token.type.isComment() || token.type == Indent || token.type == Unindent) {
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
            var code = str.uCharCodeAt(i);
            for (j in 0...specialChars.length) {
                if (code == specialChars.uCharCodeAt(j)) {
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
     * @param value String to check
     * @return True if string represents a valid number, false otherwise
     */
    function isNumber(value:String):Bool {
        var pos:Int = 0;
        var length = value.uLength();

        while (pos < length && isDigit(value.uCharCodeAt(pos))) {
            pos++;
        }

        if (pos < length && value.uCharCodeAt(pos) == ".".code && pos + 1 < length && isDigit(value.uCharCodeAt(pos + 1))) {
            pos++;
            while (pos < length && isDigit(value.uCharCodeAt(pos))) pos++;
        }

        return pos == length;
    }

    function makeLooseOrStrictAfterBracket():Void {
        var i = tokenized.length - 1;

        while (i >= 0) {
            final token = tokenized[i];
            switch token.type {
                case Identifier(_) | RParen | RBracket:
                    strictExprs.push(Strict);
                    return;
                case CommentLine(_) | CommentMultiLine(_) | Indent | Unindent | LineBreak:
                    // Continue
                case _:
                    strictExprs.push(Loose);
                    return;
            }
            i--;
        }

        strictExprs.push(Inherit);
    }

    function makeStrictIfFollowingCallable():Void {
        if (followsCallableOrIndexable()) {
            strictExprs.push(Strict);
        }
        else {
            strictExprs.push(Inherit);
        }
    }

    function followsCallableOrIndexable():Bool {
        var i = tokenized.length - 1;

        while (i >= 0) {
            final token = tokenized[i];
            switch token.type {
                case Identifier(_) | RParen | RBracket:
                    return true;
                case CommentLine(_) | CommentMultiLine(_) | Indent | Unindent | LineBreak:
                    // Continue
                case _:
                    return false;
            }
            i--;
        }

        return false;
    }

    function isStrict():Bool {
        var i = strictExprs.length - 1;
        while (i >= 0 && strictExprs[i] == Inherit) {
            i--;
        }
        return i >= 0 && strictExprs[i] == Strict;
    }

    function readImportValue(c:Int, startPos:Position):Token {

        if (c == '"'.code) {
            return readString(startPos);
        }
        else {
            final buf = new Utf8Buf();
            while (pos < length) {
                final cc = input.uCharCodeAt(pos);
                if (cc == "\n".code) {
                    break;
                }
                buf.addChar(cc);
                pos++;
            }
            final value = buf.toString().rtrim();
            return makeToken(LString(
                Unquoted, value, []
            ), new Position(
                startPos.line, startPos.column, startPos.offset, value.uLength()
            ));
        }

    }

    /**
     * Tries to read an unquoted string literal from the current position.
     * Returns null if the current position cannot start an unquoted string.
     * @return Token if an unquoted string was read, null otherwise
     */
    function tryReadUnquotedString():Null<Token> {

        // Skip in strict expression area
        if (isStrict()) return null;

        // Look ahead to validate if this could be an unquoted string start
        final c = input.uCharCodeAt(pos);
        final cc = peek();

        // Skip if it's a comment
        if (c == "/".code && pos < length - 1) {
            final next = input.uCharCodeAt(pos + 1);
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

        // Skip if parent is not a beat, character, state
        if (parent != KwBeat && parent != KwState && parent != KwCharacter) {
            return null;
        }

        // Whether this is an unquoted string value or not
        final inBrackets = isInsideBrackets();

        // If loreline_assign_unquoted is defined, unquoted string values will be allowed after
        // assigns like = += -= /= etc...
        // The default is not allowed in order to keep some consistency between assign syntax
        // and condition expressions, which are usually working in pairs
        final isAssignValue = #if loreline_assign_unquoted followsAssignStart() #else false #end;

        final labelIdentifierIndex = afterLabelIdentifierToken(false);

        // When after label, but starting the line after, check that we are indented
        if (labelIdentifierIndex != -1 && tokenized[labelIdentifierIndex].pos.line < line) {
            if (tokenized[labelIdentifierIndex].pos.column >= column) {
                return null;
            }
            // Also check that the line gap is 1 maximum
            if (line - tokenized[labelIdentifierIndex].pos.line > 1) {
                return null;
            }
        }

        final multilineIndent = if (labelIdentifierIndex != -1) {
            isStartingMultilineDialogue(labelIdentifierIndex);
        }
        else {
            -1;
        }

        final isAfterLabel = (labelIdentifierIndex != -1);
        final isValue = (parent == KwState || parent == KwCharacter || inBrackets || isAssignValue);

        // More skip cases
        if (isValue) {
            if (isCallStart(pos) || isLabelStart(pos)) {
                return null;
            }
        }
        else {
            if (!isAfterLabel && (isIdentifierExpressionStart(pos, true) || isIfStart(pos) || isCallStart(pos) || isAssignStart(pos, false))) {
                return null;
            }
        }

        // Skip if it's one of those operators too, when not a value:
        // =
        // +=
        // -=
        // *=
        // /=
        if (!isValue) {
            if (c == "=".code ||
                (cc == "=".code && (c == "+".code || c == "-".code || c == "*".code || c == "/".code))) {
                return null;
            }
        }

        // Skip if this is a beat insertion
        if (!isValue && !isAfterLabel) {
            if (isInsertionStart(pos)) {
                return null;
            }
        }

        var identifier = matchIdentifier(pos);
        if (identifier != null) {
            if (identifier == 'function') {
                // Cannot start with function keyword
                return null;
            }
            if (!isValue) {
                // Skip if starting with some keywords
                if (identifier != 'if' && identifier != 'null' && identifier != 'true' && identifier != 'false' && identifier != 'and' && identifier != 'or' && KEYWORDS.exists(identifier)) return null;

                // Skip if starting with a label
                if (isColon(pos + identifier.length)) {
                    return null;
                }
            }
        }

        // By default, tags are not allowed unless inside beat content
        var allowTags = !isValue;

        // Tells whether we are reading a dialogue text or not
        var isDialogue = false;

        // If inside a character or state block,
        // Only allow unquoted strings after labels (someKey: ...)
        // or inside array brackets
        if (isValue) {
            // Skip if not after a label or inside brackets
            if (inBrackets) {
                if (!isAfterLabel && !followsOnlyWhitespacesOrCommentsInLine() && !isAfterComma() && !isAfterLBracket()) {
                    return null;
                }
            }
            else {
                if (!isAssignValue && !isAfterLabel) {
                    return null;
                }
            }
        }

        // If not a value,
        // Only allow unquoted strings after labels (someKey: ...) starting the line
        // or if only preceded by white spaces or comments in current line
        else {

            // Skip if not after a label or starting line
            isDialogue = followsOnlyLabelOrCommentsInLine();
            if (!isDialogue && !followsOnlyWhitespacesOrCommentsInLine()) {
                return null;
            }

            if (!isDialogue) {
                // When not in dialogue, in beat, forbid starting with arrow
                if (cc == ">".code && (c == "-".code)) {
                    return null;
                }
            }
        }

        // If we get here, we can start reading the unquoted string
        final start = makePosition();
        final buf = new loreline.Utf8.Utf8Buf();
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
            final c = input.uCharCodeAt(pos);
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
            else if (tagStart == -1 && isSpace && !hasContent && attachments.length == 0) {
                // Skip leading white spaces
                advance();
            }
            // Check for end of string conditions
            else if (tagStart == -1 && (c == "{".code)) {
                break;
            }
            // Check for line breaks, which end the string only if not followed by more
            // string content on the next non-empty line
            // Also check trailing comments //
            else if (tagStart == -1 && (c == "\n".code || c == "\r".code || (c == "/".code && pos < length - 1 && input.uCharCodeAt(pos+1) == "/".code))) {
                if (multilineIndent != -1) {
                    if (isContinuingMultilineText(pos, multilineIndent)) {
                        buf.addChar(c);
                        advance();
                        // CRLF
                        if (c == "\r".code && input.charCodeAt(pos) == "\n".code) {
                            buf.addChar("\n".code);
                            advance();
                        }
                        currentColumn = column;
                        currentLine = line;
                    }
                    else {
                        break;
                    }
                }
                else {
                    break;
                }
            }
            else if (tagStart == -1 && (c == "/".code && pos < length - 1 && input.uCharCodeAt(pos+1) == "*".code)) {
                // Skip multiline comment in unquoted string
                buf.addChar("/".code);
                buf.addChar("*".code);
                advance(2); // Process /*

                // Read until comment end
                var commentClosed = false;
                while (pos < length) {
                    if (input.uCharCodeAt(pos) == "*".code && pos + 1 < length && input.uCharCodeAt(pos + 1) == "/".code) {
                        buf.addChar("*".code);
                        buf.addChar("/".code);
                        advance(2); // Process */
                        commentClosed = true;
                        break;
                    }
                    buf.addChar(input.uCharCodeAt(pos));
                    advance();
                }

                currentColumn = column;
                currentLine = line;

                if (!commentClosed) {
                    error("Unterminated multiline comment", false);
                }
            }
            // Check for trailing if
            else if (tagStart == -1 && !isValue && isIfStart(pos)) {
                break;
            }
            // Check for arrow start
            else if (tagStart == -1 && c == "-".code && pos < length - 1 && input.uCharCodeAt(pos+1) == ">".code && isTransitionStart(pos)) {
                break;
            }
            else if (tagStart == -1 && isValue && (c == ",".code || c == "]".code || c == "}".code)) {
                break;
            }
            else if (allowTags && c == "<".code) {
                if (tagStart != -1) {
                    error("Unexpected < inside tag", true);
                }
                final nextChar = pos + 1 < length ? input.uCharCodeAt(pos + 1) : 0;
                tagIsClosing = nextChar == "/".code;
                final checkPos = pos + (tagIsClosing ? 2 : 1);
                if (checkPos < length) {
                    final nameStart = input.uCharCodeAt(checkPos);
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

                    if (input.uCharCodeAt(pos) == "{".code) {
                        advance();
                        currentColumn++;

                        final interpPos = new Position(interpLine, interpColumn + 2, pos);
                        final tokens = readComplexInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(true, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
                    }
                    else if (isIdentifierStart(input.uCharCodeAt(pos))) {
                        final interpPos = new Position(interpLine, interpColumn + 1, pos);
                        final tokens = readFieldAccessInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
                    }
                    else if (input.uCharCodeAt(pos) == "$".code) {
                        buf.addChar("$".code);
                        buf.addChar("$".code);
                        advance();
                        currentColumn += 1;
                    }
                    else {
                        error("Expected identifier or { after $", false);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, [], interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
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
            var content = buf.toString();
            final rawContentLength = content.uLength();
            content = content.rtrim();

            var contentLength = content.uLength();
            var rtrimmedOffset = (rawContentLength - contentLength);
            if (contentLength > 0 && hasNonSpecialChar(content) && !isNumber(content) && content != 'null' && content != 'true' && content != 'false') {

                if (multilineIndent == -1 && !isAfterLabel && !inChoiceRoot()) {
                    // Look for more text to compose a paragraph
                    final savedLine = line;
                    final savedColumn = column;
                    final savedPos = pos;

                    skipWhitespaceAndComments(true);

                    final afterWhitespaceAndCommentsPos = pos;
                    if (column == startColumn) {
                        // Only valid if the indentation is identical
                        final followingText = tryReadUnquotedString();
                        if (followingText != null) {
                            final between = input.uSubstring(savedPos - rtrimmedOffset, afterWhitespaceAndCommentsPos);
                            switch followingText.type {
                                case LString(_, s_, attachments_):
                                    if (attachments_ != null) {
                                        for (attachment in attachments_) {
                                            switch attachment {
                                                case Interpolation(braces, inTag, expr, start, length):
                                                    attachments.push(
                                                        Interpolation(braces, inTag, expr, start + afterWhitespaceAndCommentsPos - startPos, length)
                                                    );
                                                case Tag(closing, start, length):
                                                    attachments.push(
                                                        Tag(closing, start + afterWhitespaceAndCommentsPos - startPos, length)
                                                    );
                                            }
                                        }
                                    }
                                    content += between;
                                    content += s_;
                                case _:
                            }
                            rtrimmedOffset = 0;
                            var n = pos - 1;
                            while (n >= 0 && input.uCharCodeAt(n) == " ".code || input.uCharCodeAt(n) == "\t".code) {
                                rtrimmedOffset++;
                                n--;
                            }
                        }
                        else {
                            line = savedLine;
                            column = savedColumn;
                            pos = savedPos;
                        }
                    }
                    else {
                        line = savedLine;
                        column = savedColumn;
                        pos = savedPos;
                    }
                }

                attachments.sort(compareAttachments);

                final token = makeToken(LString(
                    Unquoted, content,
                    attachments.length > 0 ? attachments : null
                ), start);
                token.pos.length -= rtrimmedOffset;

                return token;
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
        final buf = new loreline.Utf8.Utf8Buf();
        final attachments = new Array<LStringAttachment>();
        var escaped = false;
        var tagStart = -1;
        var tagIsClosing = false;
        var currentColumn = stringStart.column + 1; // Add 1 for the opening quote
        var currentLine = stringStart.line;

        // By default, tags are not allowed unless inside beat content
        var allowTags = (parentBlockType() == KwBeat);

        while (pos < length) {
            final c = input.uCharCodeAt(pos);

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
                    error("Unexpected < inside tag", true);
                }
                final nextChar = pos + 1 < length ? input.uCharCodeAt(pos + 1) : 0;
                tagIsClosing = nextChar == "/".code;
                final checkPos = pos + (tagIsClosing ? 2 : 1);
                if (checkPos < length) {
                    final nameStart = input.uCharCodeAt(checkPos);
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

                    if (input.uCharCodeAt(pos) == "{".code) {
                        advance();
                        currentColumn++;

                        final interpPos = new Position(interpLine, interpColumn + 2, pos);
                        final tokens = readComplexInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(true, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
                    }
                    else if (isIdentifierStart(input.uCharCodeAt(pos))) {
                        final interpPos = new Position(interpLine, interpColumn + 1, pos);
                        final tokens = readFieldAccessInterpolation(interpPos);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, tokens, interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
                    }
                    else if (input.uCharCodeAt(pos) == "$".code) {
                        buf.addChar("$".code);
                        buf.addChar("$".code);
                        advance();
                        currentColumn += 1;
                    }
                    else {
                        error("Expected identifier or { after $", false);
                        final interpLength = pos - tokenStartPos;
                        attachments.push(Interpolation(false, tagStart != -1, [], interpStart, interpLength));

                        buf.add(input.uSubstr(tokenStartPos, interpLength));
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

        error("Unterminated string", true);
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
    function readComplexInterpolation(interpStart:Position):Tokens {
        strictExprs.push(Strict);

        final tokens = new Tokens();
        var braceLevel = 1;
        var currentColumn = interpStart.column;
        var currentLine = interpStart.line;

        while (pos < length && braceLevel > 0) {

            if (input.uCharCodeAt(pos) == '"'.code) {
                final stringPos = new Position(currentLine, currentColumn, pos);
                tokens.push(readString(stringPos));
                currentColumn += (pos - stringPos.offset);
                continue;
            }

            final token = nextToken();
            tokens.push(token);

            if (token.type == LineBreak) {
                currentLine++;
                currentColumn = 1;
            }
            else if (token.type == Indent || token.type == Unindent) {
                // Ignore
            }
            else {
                var tokenLength = switch (token.type) {
                    case Identifier(name): name.uLength();
                    case LString(q, s, _): s.uLength() + (q != Unquoted ? 2 : 0);
                    case LNumber(n): Std.string(n).uLength();
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
                error("Unterminated interpolation expression", true);
            }
        }

        // Remove last closing brace
        tokens.pop();

        strictExprs.pop();

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
        final len = token.pos.length;

        final tokenOffset = pos - savedPos;
        token.pos = new Position(
            startPos.line,
            startPos.column + tokenOffset,
            startPos.offset + tokenOffset,
            len
        );

        line = savedLine;
        column = savedColumn;

        return token;
    }

    /**
     * Reads a simple field access interpolation (e.g. $foo.bar[baz].qux).
     * @param interpStart Starting position of the interpolation
     * @return Array of tokens making up the field access
     * @throws LexerError if field access is malformed
     */
    function readFieldAccessInterpolation(interpStart:Position):Tokens {
        strictExprs.push(Strict);

        final tokens = new Tokens();

        // Read initial identifier
        if (!isIdentifierStart(input.uCharCodeAt(pos))) {
            error("Expected identifier in field access", true);
        }

        // Read identifier token
        final idStartPos = pos;
        while (pos < length) {
            final c = input.uCharCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }
        final name = input.uSubstr(idStartPos, pos - idStartPos);
        final tokenType = KEYWORDS.exists(name) ? KEYWORDS.get(name) : Identifier(name);
        tokens.push(new Token(tokenType, new Position(interpStart.line, interpStart.column, idStartPos, pos - idStartPos)));

        // Keep reading field access, array access, function calls, and their combinations
        while (pos < length) {
            switch (input.uCharCodeAt(pos)) {
                case "[".code:
                    // Push the [ token
                    tokens.push(new Token(LBracket, new Position(line, column, pos, 1)));
                    advance();

                    // Enter array bracket expression mode
                    stack.push(Bracket);
                    strictExprs.push(Strict);

                    // Read tokens until closing bracket
                    var bracketLevel = 1;
                    while (pos < length && bracketLevel > 0) {
                        if (input.uCharCodeAt(pos) == "]".code) {
                            bracketLevel--;
                            if (bracketLevel == 0) {
                                tokens.push(new Token(RBracket, new Position(line, column, pos, 1)));
                                advance();
                                stack.pop();
                                strictExprs.pop();
                                break;
                            }
                        }
                        else if (input.uCharCodeAt(pos) == "[".code) {
                            bracketLevel++;
                        }

                        // Read next token within brackets
                        tokens.push(nextToken());
                    }

                    if (bracketLevel > 0) {
                        error("Unterminated array access in interpolation", true);
                    }

                case "(".code:
                    // Push the ( token
                    tokens.push(new Token(LParen, new Position(line, column, pos, 1)));
                    advance();

                    // Enter function call expression mode
                    stack.push(Brace);
                    strictExprs.push(Strict);

                    // Read tokens until closing parenthesis
                    var parenLevel = 1;
                    while (pos < length && parenLevel > 0) {
                        if (input.uCharCodeAt(pos) == ")".code) {
                            parenLevel--;
                            if (parenLevel == 0) {
                                tokens.push(new Token(RParen, new Position(line, column, pos, 1)));
                                advance();
                                stack.pop();
                                strictExprs.pop();
                                break;
                            }
                        }
                        else if (input.uCharCodeAt(pos) == "(".code) {
                            parenLevel++;
                        }

                        if (input.uCharCodeAt(pos) == ",".code) {
                            tokens.push(new Token(Comma, new Position(line, column, pos, 1)));
                            advance();
                        }
                        else {
                            // Read next token within parentheses
                            tokens.push(nextToken());
                        }
                    }

                    if (parenLevel > 0) {
                        error("Unterminated function call in interpolation", true);
                    }

                case ".".code if (pos + 1 < length && isIdentifierStart(input.uCharCodeAt(pos + 1))):
                    tokens.push(new Token(Dot, new Position(line, column, pos, 1)));
                    advance();

                    // Read the identifier after the dot
                    final idStartPos = pos;
                    while (pos < length) {
                        final c = input.uCharCodeAt(pos);
                        if (!isIdentifierPart(c)) break;
                        advance();
                    }
                    final name = input.uSubstr(idStartPos, pos - idStartPos);
                    final tokenType = KEYWORDS.exists(name) ? KEYWORDS.get(name) : Identifier(name);
                    tokens.push(new Token(tokenType, new Position(line, column - (pos - idStartPos), idStartPos)));

                case _:
                    break;
            }
        }

        strictExprs.pop();
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
            final c = input.uCharCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }

        final name = input.uSubstr(startOffset, pos - startOffset);
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
            if (input.uCharCodeAt(i) == "\n".code) {
                line++;
                column = 1;
            }
            else {
                column++;
            }
            i++;
        }

        return new Position(line, column, pos, stringStart.length);
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
            final c = input.uCharCodeAt(pos);
            if (c == "\n".code || c == "\r".code) break;
            advance();
        }

        return makeToken(CommentLine(input.uSubstr(contentStart, pos - contentStart)), start);
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
            if (input.uCharCodeAt(pos) == "*".code && peek() == "/".code) {
                nestLevel--;
                if (nestLevel == 0) {
                    final content = input.uSubstr(contentStart, pos - contentStart);
                    advance(2);
                    return makeToken(CommentMultiLine(content), start);
                }
                advance(2);
            }
            else if (input.uCharCodeAt(pos) == "/".code && peek() == "*".code) {
                nestLevel++;
                advance(2);
            }
            else {
                advance();
            }
        }

        error("Unterminated multi-line comment", true);
        return null;
    }

    /**
     * Reads a numeric literal.
     * @return Number token
     */
    function readNumber():Token {
        final start = makePosition();
        final startPos = pos;

        while (pos < length && isDigit(input.uCharCodeAt(pos))) {
            advance();
        }

        if (pos < length && input.uCharCodeAt(pos) == ".".code && pos + 1 < length && isDigit(input.uCharCodeAt(pos + 1))) {
            advance();
            while (pos < length && isDigit(input.uCharCodeAt(pos))) advance();
        }

        final token = makeToken(LNumber(Std.parseFloat(input.uSubstr(startPos, pos - startPos))), start);
        return token;
    }

    /**
     * Reads an identifier or keyword.
     * @return Identifier or keyword token
     */
    function readIdentifier():Token {
        final start = makePosition();
        final startPos = pos;

        while (pos < length) {
            final c = input.uCharCodeAt(pos);
            if (!isIdentifierPart(c)) break;
            advance();
        }

        final word = input.uSubstr(startPos, pos - startPos);

        if (word == 'function') {
            return readFunction(start);
        }

        final tokenType = KEYWORDS.exists(word) ? KEYWORDS.get(word) : Identifier(word);
        return makeToken(
            tokenType,
            start
        );
    }

    function readFunction(start:Position):Token {
        skipWhitespaceAndComments();

        // Evaluate min indentation
        final minIndent = start.column; // Column is 1-based, so column 0 will mean min indent 1

        // Read function name if present
        var name:Null<String> = null;
        if (isIdentifierStart(input.uCharCodeAt(pos))) {
            final nameStart = pos;
            while (pos < length && isIdentifierPart(input.uCharCodeAt(pos))) {
                advance();
            }
            name = input.uSubstr(nameStart, pos - nameStart);
        }

        skipWhitespaceAndComments();

        // Read parameters
        if (pos >= length || input.uCharCodeAt(pos) != "(".code) {
            error('Expected opening parenthesis after function name', true);
        }

        // Extract the arguments
        var parenLevel = 0;
        var args:Array<String> = [];

        // Skip the opening (
        advance();
        parenLevel = 1;

        var currentArg = new Utf8Buf();
        while (pos < length && parenLevel > 0) {
            final c = input.uCharCodeAt(pos);

            // Handle nested parentheses
            if (c == "/".code) {
                final prevPos = pos;
                skipWhitespaceAndComments();
                if (pos == prevPos) {
                    advance();
                    error('Invalid character "/"', false);
                }
            }
            else if (c == "(".code) {
                parenLevel++;
                currentArg.addChar(c);
                advance();

                skipWhitespaceAndComments();
            }
            else if (c == ")".code) {
                parenLevel--;
                if (parenLevel > 0) {
                    currentArg.addChar(c);
                } else {
                    // End of arguments, add the last argument if not empty
                    var argStr = currentArg.toString().trim();
                    if (argStr.length > 0) {
                        args.push(argStr);
                    }
                }
                advance();

                skipWhitespaceAndComments();
            }
            else if (c == ",".code && parenLevel == 1) {
                // Argument separator at top level
                var argStr = currentArg.toString().trim();
                if (argStr.length > 0) {
                    args.push(argStr);
                }
                currentArg = new Utf8Buf();
                advance();

                skipWhitespaceAndComments();
            }
            else {
                currentArg.addChar(c);
                advance();
            }
        }

        if (parenLevel > 0) {
            error('Unclosed parentheses in function declaration', false);
        }

        skipWhitespaceAndComments();

        // Check if using braces or indentation
        final usesBraces = pos < length && input.uCharCodeAt(pos) == "{".code;

        var lastLineBreakPos = pos;
        var lastLineBreakLine = line;
        var lastLineBreakColumn = column;

        if (usesBraces) {
            // Brace-delimited function body
            advance(); // Skip opening brace
            var braceLevel = 1;

            while (pos < length && braceLevel > 0) {
                final c = input.uCharCodeAt(pos);

                // Handle string literals
                if (c == "\"".code) {
                    advance(); // Skip opening quote

                    // Parse string content including possible interpolations
                    skipQuotedString();
                    continue;
                }

                // Handle normal brace counting
                if (c == "{".code) braceLevel++;
                else if (c == "}".code) braceLevel--;

                advance();
            }

            if (braceLevel > 0) {
                error('Unclosed braces in function body', false);
            }
        }
        else {
            // Indentation-delimited function body
            var functionIndentLevel = -1;
            var currentLine = true;

            // Skip to next line to start indent-based parsing
            while (pos < length) {
                final c = input.uCharCodeAt(pos);
                if (c == "\n".code || c == "\r".code) {
                    lastLineBreakPos = pos;
                    lastLineBreakLine = line;
                    lastLineBreakColumn = column;
                    advance();
                    currentLine = true;
                    break;
                }
                advance();
            }

            // Read until the indentation level decreases
            while (pos < length) {
                if (currentLine) {
                    // Count indentation level
                    var indent = 0;
                    final indentStart = pos;

                    while (pos < length) {
                        final c = input.uCharCodeAt(pos);
                        if (c == " ".code) indent++;
                        else if (c == "\t".code) indent++;
                        else break;
                        advance();
                    }

                    // If this is the first line, record the indent level
                    if (functionIndentLevel == -1 && pos < length && input.uCharCodeAt(pos) != "\n".code && input.uCharCodeAt(pos) != "\r".code) {
                        functionIndentLevel = indent;

                        // Check this is indented enough
                        if (functionIndentLevel < minIndent) {
                            pos = indentStart;
                            break;
                        }
                    }
                    // Check if we are done (dedent or empty line at lower indentation)
                    else if (functionIndentLevel != -1 && indent < functionIndentLevel &&
                            (pos >= length || (input.uCharCodeAt(pos) != "\n".code && input.uCharCodeAt(pos) != "\r".code))) {
                        // Rewind position to the start of this line
                        pos = indentStart;
                        break;
                    }

                    currentLine = false;
                }

                final c = input.uCharCodeAt(pos);

                // Handle string literals
                if (c == "\"".code) {
                    skipQuotedString();
                    continue;
                }

                // Check for newline to reset line processing
                if (c == "\n".code || c == "\r".code) {
                    lastLineBreakPos = pos;
                    lastLineBreakLine = line;
                    lastLineBreakColumn = column;
                    currentLine = true;
                }

                advance();
            }
        }

        // Keep last line break after function body so that it is tokenized
        pos = lastLineBreakPos;
        line = lastLineBreakLine;
        column = lastLineBreakColumn;

        // Extract the function code from the original input
        final bodyEnd = pos;
        var code = input.uSubstr(start.offset, bodyEnd - start.offset).rtrim();

        final external = (code.uIndexOf("\n") == -1);
        if (!external) {
            code = code + "\n";
        }

        // Create token with the function code
        final token = makeToken(Function(name, args, code, external), start);
        token.pos.length = code.uLength();
        return token;
    }

    function skipQuotedString():Void {
        var escaped = false;

        advance(); // Skip opening quote

        while (pos < length) {
            final c = input.uCharCodeAt(pos);

            if (escaped) {
                // Handle escape sequence
                escaped = false;
                advance();
            }
            else if (c == "\\".code) {
                // Start of escape sequence
                escaped = true;
                advance();
            }
            else if (c == "\"".code) {
                // End of string
                advance(); // Skip closing quote
                break;
            }
            else if (c == "$".code && pos + 1 < length) {
                // Handle string interpolation
                advance(); // Skip $

                if (pos < length && input.uCharCodeAt(pos) == "{".code) {
                    // Complex interpolation ${...}
                    advance(); // Skip {

                    // Parse interpolation expression with proper nesting
                    var interpBraceLevel = 1;

                    while (pos < length && interpBraceLevel > 0) {
                        final ic = input.uCharCodeAt(pos);

                        if (ic == "\"".code) {
                            // Handle nested strings within interpolation
                            skipQuotedString(); // Recursively parse the nested string
                            continue;
                        }
                        else if (ic == "{".code) {
                            interpBraceLevel++;
                        }
                        else if (ic == "}".code) {
                            interpBraceLevel--;
                        }

                        if (interpBraceLevel > 0 || ic != "}".code) {
                            advance();
                        } else {
                            advance(); // Skip closing }
                            break;
                        }
                    }
                }
                else if (isIdentifierStart(input.uCharCodeAt(pos))) {
                    // Simple identifier interpolation $identifier
                    while (pos < length && isIdentifierPart(input.uCharCodeAt(pos))) {
                        advance();
                    }
                }
            }
            else {
                advance();
            }
        }
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
            if (input.uCharCodeAt(pos) == "\n".code) {
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
        return pos + offset < length ? input.uCharCodeAt(pos + offset) : 0;
    }

    /**
     * Creates and throws a lexer error.
     * @param message Error message
     * @throws LexerError with the given message and current position
     */
    function error(message:String, fatal:Bool):LexerError {
        final err = new LexerError(message, makePosition());
        if (errors == null) {
            errors = [];
        }
        errors.push(err);
        if (fatal) {
            throw err;
        }
        return err;
    }

    /**
     * Gets the array of lexing errors encountered.
     * @return Array of LexerError objects
     */
    public function getErrors():Array<LexerError> {
        if (errors == null) errors = [];
        return errors;
    }

    /**
     * Skips whitespace characters (space and tab).
     */
    function skipWhitespace() {
        while (pos < length) {
            switch (input.uCharCodeAt(pos)) {
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

    inline function isLowerCase(c:Int):Bool {
        return (c >= "a".code && c <= "z".code);
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