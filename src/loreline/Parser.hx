package loreline;

import loreline.Lexer;
import loreline.Node;

using loreline.Utf8;

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

    /** Root beat, when adding narrative flow directly at the script root */
    var rootBeat:NBeatDecl;

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
        this.nextNodeId = 0;
        this.rootBeat = null;
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
                        pendingComments.push(new Comment(nextNodeId++, currentPos(), content, false));
                    case CommentMultiLine(content):
                        if (pendingComments == null) pendingComments = [];
                        pendingComments.push(new Comment(nextNodeId++, currentPos(), content, true));
                    case LineBreak:
                        lastLineBreak = currentPos();
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
     * Gets the previously consumed token.
     * @return The previous token
     */
    function prevWithType(type:TokenType):Token {
        var n = current - 1;
        while (n >= 0) {
            if (tokens[n].type.equals(type)) {
                return tokens[n];
            }
            n--;
        }
        return null;
    }

    /**
     * Gets the previously consumed token that was an identifier.
     * @return The previous token that was an identifier
     */
    function prevIdentifier():Token {
        var n = current - 1;
        while (n >= 0) {
            switch tokens[n].type {
                case Identifier(_):
                    return tokens[n];
                case _:
            }
            n--;
        }
        return null;
    }

    /**
     * Gets the previously consumed token that was not a white space or comment.
     * @return The previous token that is not a white space or comment
     */
    function prevNonWhitespaceOrComment():Token {
        var n = current - 1;
        while (n >= 0) {
            switch tokens[n].type {
                case CommentLine(_) | CommentMultiLine(_) | Indent | Unindent | LineBreak:
                    // Skip
                case _:
                    return tokens[n];
            }
            n--;
        }
        return null;
    }

    /**
     * Gets the next token that is not a white space or comment.
     * @return The next token that is not a white space or comment
     */
    function nextNonWhitespaceOrComment():Token {
        var n = current;
        while (n < tokens.length) {
            switch tokens[n].type {
                case CommentLine(_) | CommentMultiLine(_) | Indent | Unindent | LineBreak:
                    // Skip
                case _:
                    return tokens[n];
            }
            n++;
        }
        return null;
    }

    /**
     * Gets the next token that is not a line break or comment.
     * @return The next token that is not a line break or comment
     */
    function nextNonLineBreakOrComment():Token {
        var n = current;
        while (n < tokens.length) {
            switch tokens[n].type {
                case CommentLine(_) | CommentMultiLine(_) | LineBreak:
                    // Skip
                case _:
                    return tokens[n];
            }
            n++;
        }
        return null;
    }

    function currentPos():Position {
        return tokens[current]?.pos ?? new Position(1, 1, 0, 0);
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

        final startPos = currentPos();
        final nodes = [];
        final script = new Script(nextNodeId++, startPos, nodes);

        while (!isAtEnd()) {
            try {
                final node = parseNode(true);
                if (node != null) {
                    nodes.push(node);
                }
                while (match(LineBreak)) {} // Skip line breaks between top-level nodes
            } catch (e:ParseError) {
                addError(e);
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
                    currentPos(),
                    switch(tokens[current].type) {
                        case CommentLine(content): content;
                        case CommentMultiLine(content): content;
                        case _: "";
                    },
                    tokens[current].type.match(CommentMultiLine(_))
                ));
            }
            advance();
            if (isAtEnd()) {
                throw new ParseError("Unexpected end of file", currentPos());
            }
        }

        if (isAtEnd()) {
            throw new ParseError("Unexpected end of file", currentPos());
        }

        inline function ensureInBeat(node:AstNode):AstNode {
            return topLevel ? wrapInRootBeat(node) : node;
        }

        return switch (tokens[current].type) {
            case KwImport: parseImport();
            case KwState: parseStateDecl(false);
            case KwNew:
                advance();
                if (!check(KwState)) {
                    throw new ParseError("Expected 'state' after 'new'", currentPos());
                }
                ensureInBeat(parseStateDecl(true));
            case KwBeat: parseBeatDecl();
            case KwCharacter if (topLevel): parseCharacterDecl();
            case LString(_, _, _): ensureInBeat(parseTextStatement());
            case Identifier(_) if (peek().type == Colon): ensureInBeat(parseDialogueStatement());
            case Identifier(_) | LNumber(_) | LBoolean(_) |
                 LNull | LParen | LBracket | LBrace | OpMinus | OpNot: parseExpressionStatement();
            case KwChoice: ensureInBeat(parseChoiceStatement());
            case KwIf: ensureInBeat(parseIfStatement());
            case Arrow: ensureInBeat(parseTransition());
            case _:
                throw new ParseError('Unexpected token: ${tokens[current].type}', currentPos());
        }
    }

    function wrapInRootBeat(node:AstNode):Null<NBeatDecl> {

        var body:Array<AstNode>;
        var result = null;
        if (rootBeat == null) {
            final startPos = currentPos();
            body = [];
            rootBeat = new NBeatDecl(nextNodeId++, startPos, "_", body);
            result = rootBeat;
        }
        else {
            body = rootBeat.body;
        }

        body.push(node);

        return result;

    }

    /**
     * Parses an import statement (import "file.lor")
     * @return Import statement node
     */
    function parseImport():NImport {
        final startPos = currentPos();
        final imp = new NImport(nextNodeId++, startPos, null);

        expect(KwImport);

        final path = switch tokens[current].type {
            case LString(s, _): s;
            case _: throw new ParseError("Expected string literal for import path", currentPos());
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
        final startPos = currentPos();
        final dialogue = new NDialogueStatement(nextNodeId++, startPos, null, null, null);

        // Parse character name
        dialogue.character = switch (tokens[current].type) {
            case Identifier(name): name;
            case _: throw new ParseError("Expected character name", currentPos());
        };
        dialogue.characterPos = tokens[current].pos;
        advance(); // Move past identifier

        expect(Colon); // Move past colon

        attachComments(dialogue);

        // Parse dialogue content
        dialogue.content = parseStringLiteral();

        // Update position
        dialogue.pos = dialogue.pos.extendedTo(dialogue.content.pos);

        return dialogue;
    }

    /**
     * Parses a block of statements enclosed in braces.
     * @return Array of parsed statement nodes
     */
    function parseStatementBlock(statements:Array<AstNode>):BlockStyle {

        final blockEnd:TokenType = parseBlockStart().type == Indent ? Unindent : RBrace;

        while (!check(blockEnd) && !isAtEnd()) {
            // Handle line breaks and comments
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}

            if (check(blockEnd)) break;

            // Parse statement
            try {
                statements.push(parseNode());
            } catch (e:ParseError) {
                if (errors == null) errors = [];
                errors.push(e);
                synchronize();
                if (check(blockEnd)) break;
            }

            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        }

        expect(blockEnd);

        return (blockEnd == RBrace) ? Braces : Plain;

    }

    /**
     * Parses a state declaration, which can be temporary or permanent.
     * @param temporary Whether this is a temporary state (new state)
     * @return State declaration node
     */
    function parseStateDecl(temporary:Bool):NStateDecl {
        final startPos = currentPos();
        final stateNode = new NStateDecl(nextNodeId++, startPos, temporary, []);

        expect(KwState);

        final blockEnd:TokenType = parseBlockStart().type == Indent ? Unindent : RBrace;
        stateNode.style = (blockEnd == RBrace) ? Braces : Plain;

        attachComments(stateNode);

        // Parse character fields
        while (!check(blockEnd) && !isAtEnd()) {
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
            stateNode.fields.push(parseObjectField());
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        }

        while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        expect(blockEnd);

        stateNode.pos = stateNode.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return stateNode;
    }

    /**
     * Parses a single field in an object literal.
     * @return Object field node
     */
    function parseObjectField():NObjectField {
        final startPos = currentPos();
        final name = expectIdentifier();
        final objectField = new NObjectField(nextNodeId++, startPos, name, null);

        expect(Colon);
        attachComments(objectField);

        if (checkBlockStart()) {
            objectField.value = parseObjectLiteral();
        }
        else {
            objectField.value = parseExpression();
        }
        objectField.pos = objectField.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return objectField;
    }

    /**
     * Parses a beat declaration, which represents a story segment.
     * @return Beat declaration node
     */
    function parseBeatDecl():NBeatDecl {
        final startPos = currentPos();
        final beatNode = new NBeatDecl(nextNodeId++, startPos, null, [], []);

        expect(KwBeat);
        beatNode.pos = startPos.extendedTo(currentPos());
        // final namePos = currentPos();
        // beatNode.pos.length += namePos.offset + namePos.length - (beatNode.pos.offset + beatNode.pos.length);
        beatNode.name = expectIdentifier();

        final blockStart = parseBlockStart();
        final blockEnd:TokenType = blockStart.type == Indent ? Unindent : RBrace;
        beatNode.style = (blockEnd == RBrace) ? Braces : Plain;

        attachComments(beatNode);

        // Parse character fields
        while (!check(blockEnd) && !isAtEnd()) {
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
            beatNode.body.push(parseNode());
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        }

        while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        expect(blockEnd);

        beatNode.pos = beatNode.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return beatNode;
    }

    function checkBlockStart():Bool {

        var indentToken:Token = null;
        var braceToken:Token = null;
        var numIndents = 0;
        var i = 0;
        while (current + i < tokens.length) {
            final token = tokens[current + i];
            i++;

            if (token.type == LineBreak) continue;
            if (token.type == Indent) {
                numIndents++;
                indentToken = token;
                continue;
            }
            if (token.type == LBrace) {
                if (braceToken == null) {
                    braceToken = token;
                }
                continue;
            }
            break;
        }

        if (braceToken != null) {
            return true;
        }
        else if (indentToken != null) {
            if (numIndents > 1) {
                throw new ParseError('Invalid indentation level', indentToken.pos);
            }
            return true;
        }
        else {
            return false;
        }

    }

    function parseBlockStart():Token {

        var indentToken:Token = null;
        var braceToken:Token = null;
        var numIndents = 0;
        while (!isAtEnd()) {
            if (match(LineBreak)) continue;
            if (match(Indent)) {
                numIndents++;
                indentToken = prevWithType(Indent);
                continue;
            }
            if (match(LBrace)) {
                if (braceToken == null) {
                    braceToken = prevWithType(LBrace);
                }
                continue;
            }
            break;
        }

        if (braceToken != null) {
            return braceToken;
        }
        else if (indentToken != null) {
            if (numIndents > 1) {
                throw new ParseError('Invalid indentation level', indentToken.pos);
            }
            return indentToken;
        }
        else {
            addError(new ParseError('Expected ${TokenType.LBrace} or ${TokenType.Indent}, got ${tokens[current].type}', currentPos()));
            return new Token(Indent, currentPos());
        }

    }

    /**
     * Parses a character declaration with its fields.
     * @return Character declaration node
     */
    function parseCharacterDecl():NCharacterDecl {
        final startPos = currentPos();
        final characterNode = new NCharacterDecl(nextNodeId++, startPos, null, null, []);

        expect(KwCharacter);
        characterNode.name = expectIdentifier();
        characterNode.namePos = prevNonWhitespaceOrComment().pos;

        final blockEnd:TokenType = parseBlockStart().type == Indent ? Unindent : RBrace;
        characterNode.style = (blockEnd == RBrace) ? Braces : Plain;

        attachComments(characterNode);

        // Parse character fields
        while (!check(blockEnd) && !isAtEnd()) {
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
            characterNode.fields.push(parseObjectField());
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        }

        while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        expect(blockEnd);

        characterNode.pos = characterNode.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return characterNode;
    }

    /**
     * Parses a text statement (direct string literal).
     * @return Text statement node
     */
    function parseTextStatement():NTextStatement {
        final startPos = currentPos();
        final statement = attachComments(new NTextStatement(nextNodeId++, startPos, null));
        statement.content = parseStringLiteral();
        return statement;
    }

    /**
     * Parses a choice statement with its options.
     * @return Choice statement node
     */
    function parseChoiceStatement():NChoiceStatement {
        final startPos = currentPos();
        final choiceNode = new NChoiceStatement(nextNodeId++, startPos, []);

        expect(KwChoice);

        final blockEnd:TokenType = parseBlockStart().type == Indent ? Unindent : RBrace;
        choiceNode.style = (blockEnd == RBrace) ? Braces : Plain;

        attachComments(choiceNode);

        // Parse choice options
        while (!check(blockEnd) && !isAtEnd()) {
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
            choiceNode.options.push(parseChoiceOption(blockEnd));
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        }

        expect(blockEnd);

        // Update statement position to wrap all its sub expressions
        choiceNode.pos = choiceNode.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return choiceNode;
    }

    /**
     * Parses a single choice option with its condition and consequences.
     * @return Choice option node
     */
    function parseChoiceOption(blockEnd:TokenType):NChoiceOption {
        final startPos = currentPos();
        final choiceOption = attachComments(new NChoiceOption(nextNodeId++, startPos, null, null, []));
        choiceOption.text = parseStringLiteral();

        // Parse optional condition
        if (match(KwIf)) {
            choiceOption.condition = parseConditionExpression();
        }

        // Parse option body
        if (checkBlockStart()) {
            choiceOption.body = [];
            choiceOption.style = parseStatementBlock(choiceOption.body);
        }
        else if (!check(blockEnd)) {  // If not end of choice
            choiceOption.body = [parseNode()];
            choiceOption.style = Plain;
        }

        choiceOption.pos = choiceOption.pos.extendedTo(prevNonWhitespaceOrComment().pos);

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
            final assignment = attachComments(new NAssign(nextNodeId++, expr.pos, expr, op, null));
            assignment.value = parseExpression();
            assignment.pos = assignment.pos.extendedTo(assignment.value.pos);
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
        final startPos = currentPos();
        final ifNode = new NIfStatement(nextNodeId++, startPos, null, null, null);

        expect(KwIf);
        ifNode.condition = parseConditionExpression();

        while (match(LineBreak)) {}
        attachComments(ifNode);

        ifNode.thenBranch = new NBlock(nextNodeId++, currentPos(), null);
        ifNode.thenBranch.body = [];
        ifNode.thenBranch.style = parseStatementBlock(ifNode.thenBranch.body);

        // Handle optional else clause
        var elseToken = tokens[current];
        if (elseToken != null && elseToken.type == KwElse) {
            advance();
            while (match(LineBreak)) {}
            attachElseComments(ifNode, elseToken);
            if (check(KwIf)) {
                ifNode.elseBranch = new NBlock(nextNodeId++, currentPos(), null);
                ifNode.elseBranch.body = [parseIfStatement()];
                ifNode.elseBranch.style = Plain;
            }
            else {
                ifNode.elseBranch = new NBlock(nextNodeId++, currentPos(), null);
                ifNode.elseBranch.body = [];
                ifNode.elseBranch.style = parseStatementBlock(ifNode.elseBranch.body);
            }
        }

        // Update statement position to wrap all its sub expressions
        ifNode.pos = ifNode.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return ifNode;
    }

    /**
     * Parses a transition statement (-> target).
     * @return Transition node
     */
    function parseTransition():NTransition {
        final startPos = currentPos();
        expect(Arrow);

        // Handle "end of stream" (-> .)
        if (match(Dot)) {
            return attachComments(new NTransition(nextNodeId++, startPos.extendedTo(prevNonWhitespaceOrComment().pos), ".", prevNonWhitespaceOrComment().pos));
        }

        final target = expectIdentifier();
        return attachComments(new NTransition(nextNodeId++, startPos.extendedTo(prevNonWhitespaceOrComment().pos), target, prevNonWhitespaceOrComment().pos));
    }

    /**
     * Parses an expression, including assignments.
     * @return Expression node
     */
    function parseExpression():NExpr {
        try {
            final expr = parseLogicalOr();

            // Handle assignments if present
            if (check(OpAssign) || check(OpPlusAssign) || check(OpMinusAssign) ||
                check(OpMultiplyAssign) || check(OpDivideAssign)) {
                final op = tokens[current].type;
                advance();
                final assignment = attachComments(new NAssign(nextNodeId++, expr.pos, expr, op, null));
                assignment.value = parseExpression();
                assignment.pos = assignment.pos.extendedTo(assignment.value.pos);
                return assignment;
            }

            return expr;
        }
        catch (e:Any) {
            if (e is ParseError) {
                addError(cast e);
            }
            return new NLiteral(nextNodeId++, currentPos(), null, Null);
        }
    }

    /**
     * Parses logical OR expressions (expr || expr).
     * @return Expression node
     */
    function parseLogicalOr():NExpr {
        var expr = parseLogicalAnd();

        while (match(OpOr(false))) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseLogicalAnd();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses logical AND expressions (expr && expr).
     * @return Expression node
     */
    function parseLogicalAnd():NExpr {
        var expr = parseEquality();

        while (match(OpAnd(false))) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseEquality();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses equality expressions (expr == expr, expr != expr).
     * @return Expression node
     */
    function parseEquality():NExpr {
        var expr = parseComparison();

        while (match(OpEquals) || match(OpNotEquals)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseComparison();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses comparison expressions (>, >=, <, <=).
     * @return Expression node
     */
    function parseComparison():NExpr {
        var expr = parseAdditive();

        while (match(OpGreater) || match(OpGreaterEq) || match(OpLess) || match(OpLessEq)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseAdditive();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses additive expressions (+ and -).
     * @return Expression node
     */
    function parseAdditive():NExpr {
        var expr = parseMultiplicative();

        while (match(OpPlus) || match(OpMinus)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseMultiplicative();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses multiplicative expressions (* and /).
     * @return Expression node
     */
    function parseMultiplicative():NExpr {
        var expr = parseUnary();

        while (match(OpMultiply) || match(OpDivide) || match(OpModulo)) {
            final op = previous().type;
            final binary = attachComments(new NBinary(nextNodeId++, expr.pos, expr, op, null));
            binary.right = parseUnary();
            binary.pos = binary.pos.extendedTo(binary.right.pos);
            expr = binary;
        }

        return expr;
    }

    /**
     * Parses unary expressions (!expr, -expr).
     * @return Expression node
     */
    function parseUnary():NExpr {
        if (match(OpNot) || match(OpMinus)) {
            final op = previous().type;
            final unary = attachComments(new NUnary(nextNodeId++, previous().pos, op, null));
            unary.operand = parseUnary();
            unary.pos = unary.pos.extendedTo(unary.operand.pos);
            return unary;
        }

        return parsePrimary();
    }

    /**
     * Parses primary expressions (literals, identifiers, parenthesized expressions).
     * @return Expression node
     */
    function parsePrimary():NExpr {
        final startPos = currentPos();

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
                throw new ParseError("Unexpected token in expression", currentPos());
        }
    }

    /**
     * Parses string literals, handling interpolation and tags.
     * @param stringStart Starting position of the string
     * @return String literal node
     */
    function parseStringLiteral():NStringLiteral {
        final stringLiteralPos = currentPos();
        final parts = new Array<NStringPart>();

        switch (tokens[current].type) {
            case LString(quotes, content, attachments):
                final startPos = if (quotes != Unquoted) {
                    stringLiteralPos.withOffset(content, 1, stringLiteralPos.length - 2);
                }
                else {
                    stringLiteralPos;
                }

                var currentPos = 0;

                // Handle simple strings without attachments
                if (attachments == null || attachments.length == 0) {
                    final partPos = makeStringPartPosition(startPos, content, 0);
                    partPos.length = startPos.length;
                    final literalId = nextNodeId++;
                    final partId = nextNodeId++;
                    parts.push(new NStringPart(partId, partPos, Raw(content)));
                    advance();
                    return attachComments(new NStringLiteral(literalId, stringLiteralPos, quotes, parts));
                }

                final stringLiteral = attachComments(new NStringLiteral(nextNodeId++, stringLiteralPos, quotes, parts));

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
                                    content.uSubstr(currentPos, start - currentPos)
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
                                    content.uSubstr(currentPos, start - currentPos)
                                )));
                            }

                            // Process tag
                            parts.push(parseStringTag(
                                closing,
                                start,
                                length,
                                content,
                                quotes,
                                attachments
                            ));

                            currentPos = start + length;
                    }
                }

                // Add remaining text after last attachment
                if (currentPos < content.uLength()) {
                    final partPos = makeStringPartPosition(startPos, content, currentPos);
                    partPos.length = content.uLength() - currentPos;
                    parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                        content.uSubstr(currentPos)
                    )));
                }

                advance();
                return stringLiteral;

            case _:
                throw new ParseError('Expected string, got ${tokens[current].type}', currentPos());
        }
    }

    /**
     * Creates a Position object for a part of a string literal.
     * @param stringStart Starting position of the entire string content
     * @param content String content
     * @param offset Offset within the string
     * @return Position object for the string part
     */
    function makeStringPartPosition(stringStart:Position, content:String, offset:Int):Position {
        var line = stringStart.line;
        var column = stringStart.column;

        // Track line and column numbers
        for (i in 0...offset) {
            if (content.uCharCodeAt(i) == "\n".code) {
                line++;
                column = 1;
            }
            else {
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
    function makeAccess(pos:Position, target:Null<NExpr>, name:String, namePos:Position):NAccess {
        if (name != null) {
            if (name.uLength() == 0) {
                addError(new ParseError("Invalid access: " + (name != null ? "'" + name + "'" : "null"), pos));
            }
            if (target != null) {
                if (namePos != null) {
                    pos = new Position(
                        target.pos.line, target.pos.column, target.pos.offset,
                        namePos.offset + name.uLength() - target.pos.offset
                    );
                }
                else {
                    throw new ParseError("Invalid access (missing name position)", pos);
                }
            }
            else if (pos.length == 0) {
                pos = new Position(
                    pos.line, pos.column, pos.offset,
                    namePos?.length ?? name.uLength()
                );
            }
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
        final pos = makeStringPartPosition(tokens[0]?.pos ?? currentPos(), content, start);
        pos.length = length;

        if (tokens.length == 0) {
            addError(new ParseError("Empty interpolation", tokens[0]?.pos ?? currentPos()));
            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
        }

        var expr:NExpr = null;

        // Handle simple field access interpolation ($identifier)
        if (!braces && tokens.length > 0) {
            var target:Null<NExpr> = null;
            var i = 0;
            var prevIsDot = false;

            while (i < tokens.length) {
                final token = tokens[i];
                i++;

                switch (token.type) {
                    case Identifier(name):
                        if (target == null) {
                            target = attachComments(makeAccess(token.pos, null, name, null));
                        }
                        else if (prevIsDot) {
                            target = attachComments(makeAccess(token.pos, target, name, token.pos));
                        }
                        else {
                            addError(new ParseError("Missing dot in field access", token.pos));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }
                        prevIsDot = false;

                    case LBracket:
                        // Handle array access: read until matching RBracket
                        if (target == null) {
                            addError(new ParseError("Array access without target", token.pos));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }

                        final arrayStart = token.pos;
                        final arrayTokens = [];
                        var bracketLevel = 1;
                        var lastRBracket = null;

                        while (i < tokens.length && bracketLevel > 0) {
                            final t = tokens[i];
                            i++;

                            switch (t.type) {
                                case LBracket:
                                    bracketLevel++;
                                    arrayTokens.push(t);
                                case RBracket:
                                    bracketLevel--;
                                    if (bracketLevel > 0) {
                                        arrayTokens.push(t);
                                    }
                                    lastRBracket = t;
                                case _:
                                    arrayTokens.push(t);
                            }
                        }

                        if (bracketLevel > 0) {
                            addError(new ParseError("Unterminated array access", arrayStart));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }

                        // Parse array index expression
                        final tempParser = new Parser(arrayTokens);
                        tempParser.nextNodeId = nextNodeId;
                        final indexExpr = tempParser.parseExpression();
                        nextNodeId = tempParser.nextNodeId;

                        // Create array access node
                        final accessPos = pos.extendedTo(tokens[i-1].pos);
                        accessPos.length += 1;
                        target = attachComments(new NArrayAccess(nextNodeId++, accessPos, target, indexExpr));
                        prevIsDot = false;

                    case LParen:
                        // Handle function call: read until matching RParen
                        if (target == null) {
                            addError(new ParseError("Function call without target", token.pos));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }

                        final callStart = token.pos;
                        final argTokens = [];
                        var currentArgTokens = [];
                        var parenLevel = 1;

                        while (i < tokens.length && parenLevel > 0) {
                            final t = tokens[i];
                            i++;

                            switch (t.type) {
                                case LParen:
                                    parenLevel++;
                                    currentArgTokens.push(t);
                                case RParen:
                                    parenLevel--;
                                    if (parenLevel > 0) {
                                        currentArgTokens.push(t);
                                    }
                                    else if (currentArgTokens.length > 0) {
                                        argTokens.push(currentArgTokens);
                                    }
                                case Comma if (parenLevel == 1):
                                    if (currentArgTokens.length > 0) {
                                        argTokens.push(currentArgTokens);
                                        currentArgTokens = [];
                                    }
                                case _:
                                    currentArgTokens.push(t);
                            }
                        }

                        if (parenLevel > 0) {
                            addError(new ParseError("Unterminated function call", callStart));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }

                        // Parse argument expressions
                        final args:Array<NExpr> = [];
                        for (argTokenGroup in argTokens) {
                            final tempParser = new Parser(argTokenGroup);
                            tempParser.nextNodeId = nextNodeId;
                            args.push(tempParser.parseExpression());
                            nextNodeId = tempParser.nextNodeId;
                        }

                        // Create call node
                        target = attachComments(new NCall(nextNodeId++, callStart.extendedTo(tokens[i-1].pos), target, args));
                        prevIsDot = false;

                    case Dot:
                        if (target == null) {
                            addError(new ParseError("Leading dot in field access", token.pos));
                            return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                        }
                        prevIsDot = true;

                    case _:
                        addError(new ParseError('Unexpected token in field access: ${token.type}', token.pos));
                        return new NStringPart(nextNodeId++, pos, Expr(new NLiteral(nextNodeId++, tokens[0]?.pos ?? currentPos(), null, Null)));
                }
            }

            if (prevIsDot) {
                addError(new ParseError("Trailing dot in field access", tokens[tokens.length - 1].pos));
            }

            expr = target;
        }
        // Handle complex interpolation with braces (${expression})
        else {
            final tempParser = new Parser(tokens);
            tempParser.nextNodeId = nextNodeId;
            expr = tempParser.parseExpression();
            nextNodeId = tempParser.nextNodeId;

            if (!tempParser.isAtEnd()) {
                addError(new ParseError("Unexpected tokens after interpolation expression", tempParser.tokens[tempParser.current].pos));
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
    function parseStringTag(closing:Bool, start:Int, length:Int, content:String, quotes:Quotes, attachments:Array<LStringAttachment>):NStringPart {
        var pos = makeStringPartPosition(currentPos(), content, start);
        pos.length = length;

        if (quotes != Unquoted) {
            pos = pos.withOffset(content, 1, pos.length);
        }

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
                    Unquoted,
                    [new NStringPart(partId, partPos, Raw(content.uSubstr(innerStart, innerLength)))]
                ))
            ));
        }

        // Process tag with interpolations
        final parts = new Array<NStringPart>();
        final stringLiteral = attachComments(new NStringLiteral(nextNodeId++, pos, Unquoted, parts));
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
                                final partPos = makeStringPartPosition(pos, content.uSubstr(start), currentPos - start + offsetStart);
                                partPos.length = aStart - currentPos;
                                parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                                    content.uSubstr(currentPos, aStart - currentPos)
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
            final partPos = makeStringPartPosition(pos, content.uSubstr(start), currentPos - start + offsetStart);
            partPos.length = (innerStart + innerEnd) - currentPos;
            parts.push(new NStringPart(nextNodeId++, partPos, Raw(
                content.uSubstr(currentPos, innerEnd - currentPos)
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
    function parseIdentifierExpression(startPos:Position, name:String):NExpr {
        var expr:NExpr = attachComments(makeAccess(startPos, null, name, null));

        // Parse chained accesses (., [], and ())
        while (true) {
            if (match(Dot)) {
                // Create placeholder identifier if none follows the dot
                var prop = null;
                var propPos = currentPos();

                if (checkIdentifier()) {
                    prop = expectIdentifier();
                } else {
                    // Create error for missing identifier but continue parsing
                    addError(new ParseError("Expected identifier after '.'", currentPos()));
                    prop = ""; // Empty identifier as placeholder
                }

                expr = attachComments(makeAccess(startPos, expr, prop, propPos));
            }
            else if (match(LBracket)) {
                final index = parseExpression();
                expect(RBracket);
                final accessPos = startPos.extendedTo(previous().pos);
                expr = attachComments(new NArrayAccess(nextNodeId++, accessPos, expr, index));
            }
            else if (match(LParen)) {
                final args = parseCallArguments();
                expr = attachComments(new NCall(nextNodeId++, startPos.extendedTo(previous().pos), expr, args));
            }
            else {
                break;
            }
        }

        return expr;
    }

    /**
     * Parses array literals ([expr, expr, ...]).
     * @return Expression node for array literal
     */
    function parseArrayLiteral():NExpr {
        final startPos = currentPos();
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
            while (match(LineBreak) || match(Indent) || match(Unindent)) {
                needsSeparator = false;
            }

            if (!check(RBracket) && needsSeparator) {
                throw new ParseError("Expected comma or line break between elements", currentPos());
            }

            while (match(LineBreak) || match(Indent) || match(Unindent)) {}

            if (!check(RBracket)) {
                elements.push(parseExpression());
            }

            final prev = previous();
            needsSeparator = (prev.type != Colon && prev.type != LineBreak);
        }

        while (match(LineBreak) || match(Indent) || match(Unindent)) {}
        expect(RBracket);

        literal.pos = literal.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return literal;
    }

    /**
     * Parses object literals ({key: value, ...}).
     * @return Expression node for object literal
     */
    function parseObjectLiteral():NExpr {
        final startPos = currentPos();
        final fields = [];

        final blockEnd:TokenType = parseBlockStart().type == Indent ? Unindent : RBrace;
        final style:BlockStyle = (blockEnd == RBrace) ? Braces : Plain;
        final literal = new NLiteral(nextNodeId++, blockEnd != RBrace ? nextNonWhitespaceOrComment().pos : startPos, fields, Object(style));

        attachComments(literal);

        var needsSeparator = false;

        while (!check(blockEnd) && !isAtEnd()) {
            // Handle separators between fields
            if (needsSeparator) {
                while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {
                    needsSeparator = false;
                }
                if (match(Comma)) {
                    needsSeparator = false;
                }
            }
            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {
                needsSeparator = false;
            }

            if (!check(blockEnd) && needsSeparator) {
                throw new ParseError("Expected comma or line break between fields", currentPos());
            }

            while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}

            if (!check(blockEnd)) {
                fields.push(parseObjectField());
            }

            final prev = previous();
            needsSeparator = (prev.type != Colon && prev.type != LineBreak);
        }

        while (match(LineBreak) || (blockEnd != Unindent && match(Unindent))) {}
        expect(blockEnd);

        literal.pos = literal.pos.extendedTo(prevNonWhitespaceOrComment().pos);

        return literal;
    }

    /**
     * Parses function call arguments.
     * @return Array of argument expression nodes
     */
    function parseCallArguments():Array<NExpr> {
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
     * Parses a condition expression.
     * @return Expression node
     */
    function parseConditionExpression():NExpr {
        final hasParen = match(LParen);
        var expr:NExpr = null;
        try {
            expr = parseExpression();
        }
        catch (e:ParseError) {
            addError(e);
            expr = new NLiteral(nextNodeId++, currentPos(), null, Null);
        }
        if (hasParen) expect(RParen);
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
        else {
            final error = new ParseError('Expected ${type}, got ${isAtEnd() ? 'EoF' : Std.string(tokens[current].type)}', tokens[Std.int(Math.min(current, tokens.length - 1))].pos);
            switch type {
                case RBrace | RParen | Unindent:
                    addError(error);
                    return new Token(type, currentPos());
                case _:
            }
            throw error;
        }
    }

    /**
     * Check if next token is an identifier token.
     * @return `true` if the next token is an identifier
     */
    function checkIdentifier():Bool {
        return switch (tokens[current].type) {
            case Identifier(name):
                true;
            case _:
                false;
        }
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
                throw new ParseError('Expected identifier, got ${tokens[current].type}', currentPos());
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

        if (pendingComments != null) {
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
        }

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
                case RBrace | KwState | KwBeat | KwCharacter | KwChoice | KwIf | Indent:
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

    function addError(error:ParseError):ParseError {
        if (errors == null) errors = [];
        if (!errors.contains(error)) {
            errors.push(error);
        }
        return error;
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