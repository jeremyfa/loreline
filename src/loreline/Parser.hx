package loreline;

import loreline.Lexer;
import loreline.Node;

/**
 * Represents a parsing error with position information.
 */
class ParseError extends Error {

}

/**
 * Parser for the Loreline scripting language.
 * Converts a stream of tokens into an Abstract Syntax Tree (AST).
 */
class Parser {

    /** Array of tokens to parse */
    final tokens:Array<Token>;

    /** Current position in the token stream */
    var current:Int;

    /** Collection of parsing errors encountered */
    var errors:Array<ParseError>;

    /** Comments waiting to be attached to nodes */
    var pendingComments:Array<Comment>;

    /** Position of the last processed token */
    var lastTokenEnd:Position;

    /** Position of the last encountered line break */
    var lastLineBreak:Position;

    /** Flag indicating if a line break follows the current token */
    var lineBreakAfterToken:Bool;

    /** Node id counter, to ensure each parsed node has a unique integer-typed id */
    var nextNodeId:Int;

    /**
     * Creates a new Parser instance.
     * @param tokens Array of tokens to parse
     */
    public function new(tokens:Array<Token>) {
        this.tokens = tokens;
        this.current = 0;
        this.errors = null;
        this.pendingComments = null;
        this.lastTokenEnd = new Position(1, 1, 0);
        this.lastLineBreak = null;
        this.lineBreakAfterToken = false;
    }

    /**
     * Looks ahead at the next token without consuming it.
     * @return The next token in the stream
     */
    function peek():Token {
        if (current + 1 >= tokens.length) {
            return tokens[tokens.length - 1]; // Return EOF token
        }
        return tokens[current + 1];
    }

    /**
     * Looks ahead two tokens without consuming them.
     * @return Token two positions ahead
     */
    function peekNext():Token {
        return tokens[current + 2];
    }

    /**
     * Gets the type of the next token without consuming it.
     * @return TokenType of the next token
     */
    function peekType():TokenType {
        return peek().type;
    }

    /**
     * Checks if the next sequence of tokens forms a transition.
     * @return True if a transition follows
     */
    function isTransitionAhead():Bool {
        return peek().type == Arrow ||
               (peek().type.match(Identifier(_)) && peekNext().type == Arrow);
    }

    /**
     * Advances to the next token, handling comments and line breaks.
     * @return The previous token
     */
    function advance():Token {
        final prev = tokens[current];
        if (!isAtEnd()) {
            lastTokenEnd = prev.pos;
            lineBreakAfterToken = false;

            // Process comments and line breaks
            while (!isAtEnd() && tokens[current + 1] != null && (isComment(tokens[current + 1].type) || tokens[current + 1].type == LineBreak)) {
                current++;
                switch (tokens[current].type) {
                    case CommentLine(content):
                        if (pendingComments == null) pendingComments = [];
                        pendingComments.push(new Comment(nextNodeId++, tokens[current].pos, content, false));
                    case CommentMultiLine(content):
                        if (pendingComments == null) pendingComments = [];
                        pendingComments.push(new Comment(nextNodeId++, tokens[current].pos, content, true));
                    case LineBreak:
                        lastLineBreak = tokens[current].pos;
                        lineBreakAfterToken = true;
                    case _:
                }
            }
            current++;
        }
        return prev;
    }

    /**
     * Gets the previously consumed token.
     * @return The previous token
     */
    function previous():Token {
        return tokens[current - 1];
    }

    /**
     * Checks if the current token matches the expected type.
     * @param type TokenType to check against
     * @return True if the current token matches
     */
    function check(type:TokenType):Bool {
        if (isAtEnd()) return false;
        return switch type {
            case Colon: tokens[current].type == Colon;
            case _: tokens[current].type.equals(type);
        }
    }

    /**
     * Checks if the current token is a string literal.
     * @return True if current token is a string
     */
    function checkString():Bool {
        return switch tokens[current].type {
            case LString(s, attachments): true;
            case _: false;
        }
    }

    /**
     * Checks if we've reached the end of the token stream.
     * @return True if at end of input
     */
    function isAtEnd():Bool {
        return current >= tokens.length || tokens[current].type == Eof;
    }

    /**
     * Determines if a token type represents a comment.
     * @param type TokenType to check
     * @return True if token is a comment
     */
    function isComment(type:TokenType):Bool {
        return switch (type) {
            case CommentLine(_) | CommentMultiLine(_): true;
            case _: false;
        }
    }

    /**
     * Main parsing entry point. Parses the entire script into an AST.
     * @return Root node of the AST
     */
    public function parse():Script {

        static var parsing:Bool = false;

        // Reset node ids for this new parsing
        var rootParsing = !parsing;
        if (rootParsing) {
            parsing = true;
            nextNodeId = 1;
        }

        final startPos = tokens[current].pos;
        final nodes = [];
        final script = new Script(nextNodeId++, startPos, nodes);

        while (!isAtEnd()) {
            try {
                nodes.push(parseNode(true));
                while (match(LineBreak)) {} // Skip line breaks between top-level nodes
            } catch (e:ParseError) {
                if (errors == null) errors = [];
                errors.push(e);
                synchronize();
            }
        }

        if (rootParsing) {
            parsing = false;
        }

        return script;
    }

    /**
     * Parses a single node based on the current token.
     * @return Parsed node
     */
    function parseNode(topLevel:Bool = false):AstNode {
        // Handle leading comments and line breaks
        while (isComment(tokens[current].type) || tokens[current].type == LineBreak) {
            if (isComment(tokens[current].type)) {
                pendingComments.push(new Comment(
                    nextNodeId++,
                    tokens[current].pos,
                    switch(tokens[current].type) {
                        case CommentLine(content): content;
                        case CommentMultiLine(content): content;
                        case _: "";
                    },
                    tokens[current].type.match(CommentMultiLine(_))
                ));
            }
            advance();
        }

        if (isAtEnd()) {
            throw new ParseError("Unexpected end of file", tokens[current].pos);
        }

        return switch (tokens[current].type) {
            case KwImport: parseImport();
            case KwState: parseStateDecl(false);
            case KwNew if (!topLevel):
                advance();
                if (!check(KwState)) {
                    throw new ParseError("Expected 'state' after 'new'", tokens[current].pos);
                }
                parseStateDecl(true);
            case KwBeat: parseBeatDecl();
            case KwCharacter: parseCharacterDecl();
            case LString(_) if (!topLevel): parseTextStatement();
            case Identifier(_) if (!topLevel && peek().type == Colon): parseDialogueStatement();
            case Identifier(_) if (!topLevel): parseIdentifierStatement();
            case KwChoice if (!topLevel): parseChoiceStatement();
            case KwIf if (!topLevel): parseIfStatement();
            case Arrow if (!topLevel): parseTransition();
            case _: throw new ParseError('Unexpected token: ${tokens[current].type}', tokens[current].pos);
        }
    }

    /**
     * Parses an import statement (import "file.lor")
     * @return Import statement node
     */
    function parseImport():NImport {
        final startPos = tokens[current].pos;
        final imp = new NImport(nextNodeId++, startPos, null);

        expect(KwImport);

        final path = switch tokens[current].type {
            case LString(s, _): s;
            case _: throw new ParseError("Expected string literal for import path", tokens[current].pos);
        }

        advance();

        attachComments(imp);

        return imp;
    }

    /**
     * Parses a dialogue statement (character: "text")
     * @return Dialogue statement node
     */
    function parseDialogueStatement():NDialogueStatement {
        final startPos = tokens[current].pos;
        final dialogue = new NDialogueStatement(nextNodeId++, startPos, null, null);

        // Parse character name
        dialogue.character = switch (tokens[current].type) {
            case Identifier(name): name;
            case _: throw new ParseError("Expected character name", tokens[current].pos);
        };
        advance(); // Move past identifier

        expect(Colon); // Move past colon

        attachComments(dialogue);

        // Parse dialogue content
        dialogue.content = parseStringLiteral();

        return dialogue;
    }

    /**
     * Parses statements that begin with an identifier.
     * Handles assignments, (beat) calls, and other identifier-based expressions.
     * @return Parsed node
     */
    function parseIdentifierStatement():AstNode {
        final startPos = tokens[current].pos;
        final name = expectIdentifier();

        // Handle assignments
        if (match(OpAssign) || match(OpPlusAssign) || match(OpMinusAssign) ||
            match(OpMultiplyAssign) || match(OpDivideAssign)) {
            final op = previous().type;
            final assignment = attachComments(new NAssignment(
                nextNodeId++,
                startPos,
                null,
                op,
                null
            ));
            assignment.target = attachComments(makeAccess(startPos, null, name));
            assignment.value = parseExpression();
            return assignment;
        }

        return parseIdentifierExpression(startPos, name);

    }

    /**
     * Parses a block of statements enclosed in braces.
     * @return Array of parsed statement nodes
     */
    function parseStatementBlock():Array<AstNode> {
        expect(LBrace);
        final statements:Array<AstNode> = [];

        while (!check(RBrace) && !isAtEnd()) {
            // Handle line breaks and comments
            while (match(LineBreak)) {}

            if (check(RBrace)) break;

            // Parse statement
            try {
                // Check for string literals first
                if (checkString()) {
                    statements.push(parseTextStatement());
                } else if (isExpressionStart()) {
                    statements.push(parseExpressionStatement());
                } else {
                    statements.push(parseNode());
                }
            } catch (e:ParseError) {
                errors.push(e);
                synchronize();
                if (check(RBrace)) break;
            }

            while (match(LineBreak)) {}
        }

        expect(RBrace);
        return statements;
    }

    /**
     * Parses a state declaration, which can be temporary or permanent.
     * @param temporary Whether this is a temporary state (new state)
     * @return State declaration node
     */
    function parseStateDecl(temporary:Bool):NStateDecl {
        final startPos = tokens[current].pos;
        final stateNode = new NStateDecl(nextNodeId++, startPos, temporary, null);

        expect(KwState);
        while (match(LineBreak)) {} // Optional breaks before {

        attachComments(stateNode);

        // Parse state fields
        stateNode.fields = cast(parseObjectLiteral(), NLiteral);

        return stateNode;
    }

    /**
     * Parses a single field in an object literal.
     * @return Object field node
     */
    function parseObjectField():NObjectField {
        final startPos = tokens[current].pos;
        final name = expectIdentifier();
        final objectField = new NObjectField(nextNodeId++, startPos, name, null);

        expect(Colon);
        attachComments(objectField);

        objectField.value = parseExpression();

        return objectField;
    }

    /**
     * Parses a beat declaration, which represents a story segment.
     * @return Beat declaration node
     */
    function parseBeatDecl():NBeatDecl {
        final startPos = tokens[current].pos;
        final beatNode = new NBeatDecl(nextNodeId++, startPos, null, [], []);

        expect(KwBeat);
        beatNode.name = expectIdentifier();

        while (match(LineBreak)) {} // Optional before block
        expect(LBrace);
        while (match(LineBreak)) {} // Optional after {

        var braceLevel = 1;

        attachComments(beatNode);

        // Parse beat body with proper brace level tracking
        while (!isAtEnd() && braceLevel > 0) {
            switch (tokens[current].type) {
                case RBrace:
                    braceLevel--;
                    if (braceLevel > 0) advance();
                case LBrace:
                    braceLevel++;
                    advance();
                case _:
                    if (braceLevel == 1) {
                        beatNode.body.push(parseNode());
                    } else {
                        advance();
                    }
            }
        }

        expect(RBrace);
        return beatNode;
    }

    /**
     * Checks if the current token begins a block construct.
     * @return True if current token starts a block
     */
    function isBlockStart():Bool {
        return switch (tokens[current].type) {
            case KwIf | KwChoice | Arrow: true;
            case Identifier(_):
                peek().type == Arrow;
            case _: false;
        }
    }

    /**
     * Parses a character declaration with its properties.
     * @return Character declaration node
     */
    function parseCharacterDecl():NCharacterDecl {
        final startPos = tokens[current].pos;
        final characterNode = new NCharacterDecl(nextNodeId++, startPos, null, []);

        expect(KwCharacter);
        characterNode.name = expectIdentifier();

        while (match(LineBreak)) {} // Optional before block
        expect(LBrace);
        while (match(LineBreak)) {} // Optional after {

        attachComments(characterNode);

        // Parse character properties
        while (!check(RBrace) && !isAtEnd()) {
            characterNode.properties.push(parseObjectField());
            while (match(LineBreak)) {} // Optional between fields
        }

        while (match(LineBreak)) {} // Optional before }
        expect(RBrace);

        return characterNode;
    }

    /**
     * Parses a text statement (direct string literal).
     * @return Text statement node
     */
    function parseTextStatement():NTextStatement {
        final startPos = tokens[current].pos;
        final statement = attachComments(new NTextStatement(nextNodeId++, startPos, null));
        statement.content = parseStringLiteral();
        return statement;
    }

    /**
     * Parses a choice statement with its options.
     * @return Choice statement node
     */
    function parseChoiceStatement():NChoiceStatement {
        final startPos = tokens[current].pos;
        final choiceNode = new NChoiceStatement(nextNodeId++, startPos, []);

        expect(KwChoice);
        while (match(LineBreak)) {}

        expect(LBrace);
        while (match(LineBreak)) {}

        attachComments(choiceNode);

        // Parse choice options
        while (!check(RBrace) && !isAtEnd()) {
            choiceNode.options.push(parseChoiceOption());
            while (match(LineBreak)) {}
        }

        expect(RBrace);

        return choiceNode;
    }

    /**
     * Parses a single choice option with its condition and consequences.
     * @return Choice option node
     */
    function parseChoiceOption():NChoiceOption {
        final startPos = tokens[current].pos;
        final choiceOption = attachComments(new NChoiceOption(nextNodeId++, startPos, null, null, []));
        choiceOption.text = parseStringLiteral();

        // Parse optional condition
        if (match(KwIf)) {
            choiceOption.condition = parseParenExpression();
        }

        // Parse option body
        if (check(LBrace)) {
            choiceOption.body = parseStatementBlock();
        } else if (!check(RBrace)) {  // If not end of choice
            // Handle single statement bodies
            if (checkString()) {
                choiceOption.body = [parseTextStatement()];
            } else {
                choiceOption.body = [parseNode()];
            }
        }

        return choiceOption;
    }

    /**
     * Checks if the current token can start an expression.
     * @return True if current token can begin an expression
     */
    function isExpressionStart():Bool {
        return switch (tokens[current].type) {
            case Identifier(_) if (peek().type == Colon): false;
            case Identifier(_) | LString(_, _) | LNumber(_) | LBoolean(_) |
                 LNull | LParen | LBracket | LBrace | OpMinus | OpNot: true;
            case _: false;
        }
    }

    /**
     * Parses an expression statement (expression followed by optional assignment).
     * @return Node representing the expression statement
     */
    function parseExpressionStatement():AstNode {
        final expr = parseExpression();

        if (match(OpAssign) || match(OpPlusAssign) || match(OpMinusAssign) ||
            match(OpMultiplyAssign) || match(OpDivideAssign)) {
            final op = previous().type;
            final assignment = attachComments(new NAssignment(nextNodeId++, expr.pos, expr, op, null));
            assignment.value = parseExpression();
            return assignment;
        }

        return attachComments(expr);
    }

    /**
     * Checks if the current token starts a known node type.
     * @return True if current token begins a known node construct
     */
    function isKnownNodeStart():Bool {
        return switch (tokens[current].type) {
            case KwState | KwBeat | KwCharacter | KwChoice | KwIf | Arrow | LString(_): true;
            case Identifier(_) if (peek().type == Colon): true; // Dialogue
            case Identifier(_) if (peek().type == Arrow): true; // Transition
            case _: false;
        }
    }

    /**
     * Parses an if statement with optional else branch.
     * @return If statement node
     */
    function parseIfStatement():NIfStatement {
        final startPos = tokens[current].pos;
        final ifNode = new NIfStatement(nextNodeId++, startPos, null, null, null);

        expect(KwIf);
        ifNode.condition = parseParenExpression();

        while (match(LineBreak)) {}
        attachComments(ifNode);

        ifNode.thenBranch = new NBlock(nextNodeId++, tokens[current].pos, null);
        ifNode.thenBranch.body = parseStatementBlock();

        // Handle optional else clause
        var elseBranch:Null<Array<AstNode>> = null;
        var elseToken = tokens[current];
        if (elseToken.type == KwElse) {
            advance();
            while (match(LineBreak)) {}
            attachElseComments(ifNode, elseToken);
            if (check(KwIf)) {
                ifNode.elseBranch = new NBlock(nextNodeId++, tokens[current].pos, null);
                ifNode.elseBranch.body = [parseIfStatement()];
            }
            else {
                ifNode.elseBranch = new NBlock(nextNodeId++, tokens[current].pos, null);
                ifNode.elseBranch.body = parseStatementBlock();
            }
        }

        return ifNode;
    }

    /**
     * Parses a transition statement (-> target).
     * @return Transition node
     */
    function parseTransition():NTransition {
        final startPos = tokens[current].pos;
        expect(Arrow);

        // Handle "end of stream" (->.)
        if (match(Dot)) {
            return attachComments(new NTransition(nextNodeId++, startPos, "."));
        }

        final target = expectIdentifier();
        return attachComments(new NTransition(nextNodeId++, startPos, target));
    }

    /**
     * Parses an expression, including assignments.
     * @return Expression node
     */
    function parseExpression():NExpression {
        final expr = parseLogicalOr();

        // Handle assignments if present
        if (check(OpAssign) || check(OpPlusAssign) || check(OpMinusAssign) ||
            check(OpMultiplyAssign) || check(OpDivideAssign)) {
            final op = tokens[current].type;
            advance();
            final assignment = attachComments(new NAssignment(nextNodeId++, expr.pos, expr, op, null));
            assignment.value = parseExpression();
            return assignment;
        }

        return expr;
    }

    /**
     * Parses logical OR expressions (expr || expr).
     * @return Expression node
     */
    function parseLogicalOr():NExpression {
        var expr = parseLogicalAnd();

        while (match(OpOr)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseLogicalAnd();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses logical AND expressions (expr && expr).
     * @return Expression node
     */
    function parseLogicalAnd():NExpression {
        var expr = parseEquality();

        while (match(OpAnd)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseEquality();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses equality expressions (expr == expr, expr != expr).
     * @return Expression node
     */
    function parseEquality():NExpression {
        var expr = parseComparison();

        while (match(OpEquals) || match(OpNotEquals)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseComparison();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses comparison expressions (>, >=, <, <=).
     * @return Expression node
     */
    function parseComparison():NExpression {
        var expr = parseAdditive();

        while (match(OpGreater) || match(OpGreaterEq) || match(OpLess) || match(OpLessEq)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseAdditive();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses additive expressions (+ and -).
     * @return Expression node
     */
    function parseAdditive():NExpression {
        var expr = parseMultiplicative();

        while (match(OpPlus) || match(OpMinus)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseMultiplicative();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses multiplicative expressions (* and /).
     * @return Expression node
     */
    function parseMultiplicative():NExpression {
        var expr = parseUnary();

        while (match(OpMultiply) || match(OpDivide)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseUnary();
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses unary expressions (!expr, -expr).
     * @return Expression node
     */
    function parseUnary():NExpression {
        if (match(OpNot) || match(OpMinus)) {
            final op = previous().type;
            final unary = attachComments(new NUnary(nextNodeId++, tokens[current].pos, op, null));
            unary.operand = parseUnary();
            return unary;
        }

        return parsePrimary();
    }

    /**
     * Parses primary expressions (literals, identifiers, parenthesized expressions).
     * @return Expression node
     */
    function parsePrimary():NExpression {
        final startPos = tokens[current].pos;

        return switch (tokens[current].type) {
            case LString(_, _):
                parseStringLiteral();

            case LNumber(n):
                advance();
                attachComments(new NLiteral(nextNodeId++, startPos, n, Number));

            case LBoolean(b):
                advance();
                attachComments(new NLiteral(nextNodeId++, startPos, b, Boolean));

            case LNull:
                advance();
                attachComments(new NLiteral(nextNodeId++, startPos, null, Null));

            case Identifier(name):
                advance();
                parseIdentifierExpression(startPos, name);

            case LBracket:
                parseArrayLiteral();

            case LBrace:
                parseObjectLiteral();

            case LParen:
                advance();
                final expr = parseExpression();
                expect(RParen);
                expr;

            case _:
                throw new ParseError("Unexpected token in expression", tokens[current].pos);
        }
    }

    /**
     * Parses string literals, handling interpolation and tags.
     * @param stringStart Starting position of the string
     * @return String literal node
     */
    function parseStringLiteral():NStringLiteral {
        final startPos = tokens[current].pos;
        final parts = new Array<NStringPart>();

        switch (tokens[current].type) {
            case LString(content, attachments):
                var currentPos = 0;

                // Handle simple strings without attachments
                if (attachments == null || attachments.length == 0) {
                    final partPos = makeStringPartPosition(startPos, content, 0);
                    partPos.length = startPos.length;
                    final literalId = nextNodeId++;
                    final partId = nextNodeId++;
                    parts.push(new NStringPart(partId, partPos, Raw(content)));
                    advance();
                    return attachComments(new NStringLiteral(literalId, startPos, parts));
                }

                final stringLiteral = attachComments(new NStringLiteral(nextNodeId++, startPos, parts));

                // Process string with attachments (interpolations and tags)
                for (i in 0...attachments.length) {
                    switch (attachments[i]) {
                        case Interpolation(braces, inTag, tokens, start, length):
                            // Skip if we've already processed this region
                            if (currentPos >= start + length)
                                continue;

                            // Add raw text before attachment
                            if (start > currentPos) {
                                final partPos = makeStringPartPosition(startPos, content, currentPos);
                                partPos.length = start - currentPos;
                                parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                                    content.substr(currentPos, start - currentPos)
                                )));
                            }

                            // Process interpolation
                            parts.push(parseStringInterpolation(
                                braces,
                                inTag,
                                tokens,
                                start,
                                length,
                                content
                            ));

                            currentPos = start + length;

                        case Tag(closing, start, length):
                            // Skip if already processed
                            if (currentPos >= start + length)
                                continue;

                            // Add raw text before tag
                            if (start > currentPos) {
                                final partPos = makeStringPartPosition(startPos, content, currentPos);
                                partPos.length = start - currentPos;
                                parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                                    content.substr(currentPos, start - currentPos)
                                )));
                            }

                            // Process tag
                            parts.push(parseStringTag(
                                closing,
                                start,
                                length,
                                content,
                                attachments
                            ));

                            currentPos = start + length;
                    }
                }

                // Add remaining text after last attachment
                if (currentPos < content.length) {
                    final partPos = makeStringPartPosition(startPos, content, currentPos);
                    partPos.length = content.length - currentPos;
                    parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                        content.substr(currentPos)
                    )));
                }

                advance();
                return stringLiteral;

            case _:
                throw new ParseError("Expected string", tokens[current].pos);
        }
    }

    /**
     * Creates a Position object for a part of a string literal.
     * @param stringStart Starting position of the entire string
     * @param content String content
     * @param offset Offset within the string
     * @return Position object for the string part
     */
    function makeStringPartPosition(stringStart:Position, content:String, offset:Int):Position {
        var line = stringStart.line;
        var column = stringStart.column;

        // Track line and column numbers
        for (i in 0...offset) {
            if (content.charCodeAt(i) == "\n".code) {
                line++;
                column = 1;
            } else {
                column++;
            }
        }

        return new Position(line, column, stringStart.offset + offset);
    }

    /**
     * Creates an access expression node.
     * @param pos Position in source
     * @param target Target expression (null for simple identifiers)
     * @param name Identifier name
     * @return Access expression node
     */
    function makeAccess(pos:Position, target:Null<NExpression>, name:String):NAccess {
        if (pos.length == 0 && name != null && name.length > 0) {
            pos = new Position(
                pos.line, pos.column, pos.offset,
                name.length
            );
        }

        return new NAccess(nextNodeId++, pos, target, name);
    }

    /**
     * Parses string interpolation expressions (both simple and complex).
     * @param braces Whether the interpolation uses braces
     * @param inTag Whether the interpolation is inside a tag
     * @param tokens Tokens within the interpolation
     * @param start Start position in source
     * @param length Length of interpolation
     * @param content Original string content
     * @return string part representing the interpolation
     */
    function parseStringInterpolation(braces:Bool, inTag:Bool, tokens:Array<Token>, start:Int, length:Int, content:String):NStringPart {
        final pos = makeStringPartPosition(tokens[0].pos, content, start);
        pos.length = length;

        if (tokens.length == 0) {
            throw new ParseError("Empty interpolation", pos);
        }

        var expr:NExpression = null;

        // Handle simple field access interpolation ($identifier)
        if (!braces && tokens.length > 0) {
            var target:Null<NExpression> = null;
            var prevIsDot:Bool = false;
            for (i in 0...tokens.length) {
                switch (tokens[i].type) {
                    case Identifier(name):
                        if (target == null) {
                            target = attachComments(makeAccess(tokens[i].pos, null, name));
                        }
                        else if (prevIsDot) {
                            target = attachComments(makeAccess(tokens[i].pos, target, name));
                        }
                        else {
                            throw new ParseError("Missing dot in simple interpolation", tokens[i].pos);
                        }
                        prevIsDot = false;
                    case Dot:
                        prevIsDot = true;
                    case _:
                        throw new ParseError("Invalid token in simple interpolation", tokens[i].pos);
                }
            }
            expr = target;
        }
        // Handle complex interpolation with braces (${expression})
        else {
            final tempParser = new Parser(tokens);
            expr = tempParser.parseExpression();

            if (!tempParser.isAtEnd()) {
                throw new ParseError("Unexpected tokens after interpolation expression", tempParser.tokens[tempParser.current].pos);
            }
        }

        final partPos = new Position(
            pos.line,
            pos.column + (braces ? 1 : 0),
            pos.offset - (braces ? 2 : 0),
            length
        );
        return new NStringPart(nextNodeId++, partPos, Expr(expr));
    }

    /**
     * Parses string tags (<tag> or </tag>).
     * @param closing Whether this is a closing tag
     * @param start Start position in source
     * @param length Tag length
     * @param content Original string content
     * @param attachments Array of string attachments
     * @return StringPart representing the tag
     */
    function parseStringTag(closing:Bool, start:Int, length:Int, content:String, attachments:Array<LStringAttachment>):NStringPart {
        final pos = makeStringPartPosition(tokens[current].pos, content, start);
        pos.length = length;

        // Calculate tag content boundaries
        final offsetStart = (closing ? 2 : 1);
        final innerStart = start + offsetStart; // Skip < and optional /
        final innerLength = length - (closing ? 3 : 2); // Account for < > and optional /
        final innerEnd = innerStart + innerLength;
        final tagId = nextNodeId++;

        // Check for interpolations within tag range
        var hasAttachmentsInRange = false;
        if (attachments != null) {
            for (i in 0...attachments.length) {
                switch (attachments[i]) {
                    case Interpolation(_, _, _, aStart, aLength):
                        final aEnd = aStart + aLength;
                        if (aStart >= innerStart && aEnd <= innerEnd) {
                            hasAttachmentsInRange = true;
                            break;
                        }
                    case Tag(_, _, _):
                        continue; // Tags can't be nested
                }
            }
        }

        // Return simple tag if no interpolations
        if (!hasAttachmentsInRange) {
            final partPos = makeStringPartPosition(pos, content, innerStart);
            partPos.length = innerLength;
            final literalId = nextNodeId++;
            final partId = nextNodeId++;
            return new NStringPart(tagId, pos, Tag(
                closing,
                attachComments(new NStringLiteral(
                    literalId,
                    partPos,
                    [new NStringPart(partId, partPos, Raw(content.substr(innerStart, innerLength)))]
                ))
            ));
        }

        // Process tag with interpolations
        final parts = new Array<NStringPart>();
        final stringLiteral = attachComments(new NStringLiteral(nextNodeId++, pos, parts));
        var currentPos = innerStart;

        // Process each attachment within tag bounds
        if (attachments != null) {
            for (i in 0...attachments.length) {
                switch (attachments[i]) {
                    case Interpolation(braces, _, tokens, aStart, aLength):
                        final aEnd = aStart + aLength;
                        if (aStart >= innerStart && aEnd <= innerEnd) {
                            // Add raw text before interpolation
                            if (aStart > currentPos) {
                                final partPos = makeStringPartPosition(pos, content.substr(start), currentPos - start + offsetStart);
                                partPos.length = aStart - currentPos;
                                parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                                    content.substr(currentPos, aStart - currentPos)
                                )));
                            }

                            // Process interpolation
                            parts.push(parseStringInterpolation(
                                braces,
                                true,
                                tokens,
                                aStart,
                                aLength,
                                content
                            ));

                            currentPos = aEnd;
                        }
                    case Tag(_, _, _):
                        continue; // Skip nested tags
                }
            }
        }

        // Add remaining raw text
        if (currentPos < innerEnd) {
            final partPos = makeStringPartPosition(pos, content.substr(start), currentPos - start + offsetStart);
            partPos.length = (innerStart + innerEnd) - currentPos;
            parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                content.substr(currentPos, innerEnd - currentPos)
            )));
        }

        return new NStringPart(tagId, pos, Tag(
            closing,
            stringLiteral
        ));
    }

    /**
     * Parses identifier-based expressions (field access, array access, function calls).
     * @param startPos Starting position
     * @param name Initial identifier name
     * @return Expression node
     */
    function parseIdentifierExpression(startPos:Position, name:String):NExpression {
        var expr:NExpression = attachComments(makeAccess(startPos, null, name));

        // Parse chained accesses (., [], and ())
        while (true) {
            if (match(Dot)) {
                final prop = expectIdentifier();
                expr = attachComments(makeAccess(startPos, expr, prop));
            } else if (match(LBracket)) {
                final index = parseExpression();
                expect(RBracket);
                expr = attachComments(new NArrayAccess(nextNodeId++, startPos, expr, index));
            } else if (match(LParen)) {
                final args = parseCallArguments();
                expr = attachComments(new NCall(nextNodeId++, startPos, expr, args));
            } else {
                break;
            }
        }

        return expr;
    }

    /**
     * Parses array literals ([expr, expr, ...]).
     * @return Expression node for array literal
     */
    function parseArrayLiteral():NExpression {
        final startPos = tokens[current].pos;
        final elements = [];
        final literal = new NLiteral(nextNodeId++, startPos, elements, Array);
        expect(LBracket);

        attachComments(literal);

        var needsSeparator = false;

        while (!check(RBracket) && !isAtEnd()) {
            // Handle separators (commas or line breaks)
            if (needsSeparator) {
                while (match(LineBreak)) {
                    needsSeparator = false;
                }
                if (match(Comma)) {
                    needsSeparator = false;
                }
            }
            while (match(LineBreak)) {
                needsSeparator = false;
            }

            if (!check(RBracket) && needsSeparator) {
                throw new ParseError("Expected comma or line break between elements", tokens[current].pos);
            }

            while (match(LineBreak)) {}

            if (!check(RBracket)) {
                elements.push(parseExpression());
            }

            final prev = previous();
            needsSeparator = (prev.type != Colon && prev.type != LineBreak);
        }

        while (match(LineBreak)) {}
        expect(RBracket);

        return literal;
    }

    /**
     * Parses object literals ({key: value, ...}).
     * @return Expression node for object literal
     */
    function parseObjectLiteral():NExpression {
        final startPos = tokens[current].pos;
        final fields = [];
        final literal = new NLiteral(nextNodeId++, startPos, fields, Object);

        expect(LBrace);
        while (match(LineBreak)) {} // Optional breaks after {

        attachComments(literal);

        var needsSeparator = false;

        while (!check(RBrace) && !isAtEnd()) {
            // Handle separators between fields
            if (needsSeparator) {
                while (match(LineBreak)) {
                    needsSeparator = false;
                }
                if (match(Comma)) {
                    needsSeparator = false;
                }
            }
            while (match(LineBreak)) {
                needsSeparator = false;
            }

            if (!check(RBrace) && needsSeparator) {
                throw new ParseError("Expected comma or line break between fields", tokens[current].pos);
            }

            while (match(LineBreak)) {}

            if (!check(RBrace)) {
                fields.push(parseObjectField());
            }

            final prev = previous();
            needsSeparator = (prev.type != Colon && prev.type != LineBreak);
        }

        while (match(LineBreak)) {}
        expect(RBrace);

        return literal;
    }

    /**
     * Parses function call arguments.
     * @return Array of argument expression nodes
     */
    function parseCallArguments():Array<NExpression> {
        final args = [];
        if (!check(RParen)) {
            do {
                while (match(LineBreak)) {}
                args.push(parseExpression());
                while (match(LineBreak)) {}
            } while (match(Comma));
        }
        expect(RParen);
        return args;
    }

    /**
     * Parses a parenthesized expression.
     * @return Expression node
     */
    function parseParenExpression():NExpression {
        expect(LParen);
        final expr = parseExpression();
        expect(RParen);
        return expr;
    }

    /**
     * Attempts to match and consume a token of the given type.
     * @param type TokenType to match
     * @return True if token was matched and consumed
     */
    function match(type:TokenType):Bool {
        if (check(type)) {
            advance();
            return true;
        }
        return false;
    }

    /**
     * Checks if we're at a line break in the source.
     * @return True if at a line break
     */
    function isAtLineBreak():Bool {
        return lineBreakAfterToken || tokens[current].type == LineBreak;
    }

    /**
     * Expects a token of the given type, throws error if not found.
     * @param type Expected TokenType
     * @return The consumed token
     * @throws ParseError if token type doesn't match
     */
    function expect(type:TokenType):Token {
        if (check(type)) {
            return advance();
        }
        throw new ParseError('Expected ${type}, got ${tokens[current].type}', tokens[current].pos);
    }

    /**
     * Expects and consumes an identifier token.
     * @return The identifier name
     * @throws ParseError if current token is not an identifier
     */
    function expectIdentifier():String {
        return switch (tokens[current].type) {
            case Identifier(name):
                advance();
                name;
            case _:
                throw new ParseError('Expected identifier', tokens[current].pos);
        }
    }

    /**
     * Attaches pending comments to a node.
     * @param node Node to attach comments to
     * @return The node with attached comments
     */
    function attachComments<T:AstNode>(node:T):T {
        if (pendingComments == null || pendingComments.length == 0) {
            return node;
        }

        final nodeStart = node.pos;
        var remainingComments:Array<Comment> = null;

        for (i in 0...pendingComments.length) {
            final comment = pendingComments[i];
            if (comment.pos.line < nodeStart.line) {
                // Leading comments: above the node
                if (node.leadingComments == null) {
                    node.leadingComments = [];
                }
                node.leadingComments.push(comment);
            }
            else if (comment.pos.line == nodeStart.line) {
                // Trailing comments: same line as node
                if (node.trailingComments == null) {
                    node.trailingComments = [];
                }
                node.trailingComments.push(comment);
            }
            else {
                // Save comments after node for later
                if (remainingComments == null) {
                    remainingComments = [];
                }
                remainingComments.push(comment);
            }
        }

        pendingComments = remainingComments;
        return node;
    }

    /**
     * Attaches pending comments to an else clause of an if statement.
     * @param node If statement node
     * @param elseToken The else token
     * @return The node with attached else comments
     */
    function attachElseComments<T:NIfStatement>(node:T, elseToken:Token):T {
        final nodeStart = elseToken.pos;
        final remainingComments = [];

        for (comment in pendingComments) {
            if (comment.pos.line < nodeStart.line) {
                if (node.elseLeadingComments == null) {
                    node.elseLeadingComments = [];
                }
                node.elseLeadingComments.push(comment);
            }
            else if (comment.pos.line == nodeStart.line) {
                if (node.elseTrailingComments == null) {
                    node.elseTrailingComments = [];
                }
                node.elseTrailingComments.push(comment);
            }
            else {
                remainingComments.push(comment);
            }
        }

        pendingComments = remainingComments;
        return node;
    }

    /**
     * Synchronizes the parser state after an error.
     * Advances until a safe point is found to continue parsing.
     */
    function synchronize() {
        advance();

        while (!isAtEnd()) {
            switch (tokens[current].type) {
                case RBrace | KwState | KwBeat | KwCharacter | KwChoice | KwIf:
                    return;
                case Arrow:
                    advance();
                    if (check(Dot) || tokens[current].type.isIdentifier()) {
                        advance();
                    }
                    return;
                case LString(_, _):
                    if (previous().type == RBrace) return;
                    advance();
                case _:
                    advance();
            }
        }
    }

    /**
     * Checks if the current construct requires a new line.
     * @return True if new line is required
     */
    function requiresNewLine():Bool {
        return switch (tokens[current].type) {
            case RBrace | Arrow | KwElse: false;
            case _: true;
        }
    }

    /**
     * Gets the array of parsing errors encountered.
     * @return Array of ParseError objects
     */
    public function getErrors():Array<ParseError> {
        if (errors == null) errors = [];
        return errors;
    }

}