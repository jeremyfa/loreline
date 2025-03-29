package loreline;

import loreline.Lexer;
import loreline.Node;

using loreline.Utf8;

// TODO:
// This printer is expected to print valid loreline code,
// but it doesn't take into account the code style yet.

/**
 * A code printer that converts AST nodes back into formatted Loreline source code.
 * Handles indentation, newlines, and pretty-printing of all node types.
 */
class Printer {

    /**
     * Current indentation level.
     */
    var _level:Int;

    /**
     * Previous indentation level.
     */
    var _prevLevel:Int;

    /**
     * Buffer containing the generated output.
     */
    var _buf:Utf8Buf;

    /**
     * State tracking for blank lines at start of output.
     */
    var _beginLine:Int;

    /**
     * Last character written to the output.
     */
    var _lastChar:Int;

    /**
     * Last character written to the output that is visible (not a white space).
     */
    var _lastVisibleChar:Int;

    /**
     * If this value is higher than 0, new lines are not printed
     */
    var _noLn:Int;

    /**
     * Counts the number of empty lines being printed
     */
    var _numEmptyLines:Int;

    /**
     * String used for each level of indentation.
     */
    final _indent:String;

    /**
     * String used for line breaks.
     */
    final _newline:String;

    /**
     * Set to `false` to ignore comments.
     */
    public var enableComments:Bool = true;

    /**
     * Creates a new code printer with customizable formatting options.
     * @param indent String used for each level of indentation (default: 4 spaces)
     * @param newline String used for line breaks (default: \n)
     */
    public function new(indent:String = '  ', newline:String = '\n') {
        _indent = indent;
        _newline = newline;
        _beginLine = 0;
        _lastChar = -1;
        clear();
    }

    /**
     * Resets the printer to its initial state.
     */
    public inline function clear() {
        _noLn = 0;
        _level = 0;
        _prevLevel = 0;
        _numEmptyLines = 0;
        _buf = new Utf8Buf();
    }

    /**
     * Increases the current indentation level by one.
     */
    public inline function indent() {
        _level++;
    }

    /**
     * Decreases the current indentation level by one.
     */
    public inline function unindent() {
        _level--;
    }

    /**
     * Writes a string to the output buffer, handling indentation if at start of line.
     * @param s String to write
     * @return This printer instance for chaining
     */
    public function write(s:String) {
        if (s.uLength() > 0) {
            if (_beginLine > 0) {
                tab();
                _beginLine = 0;
            }
            _buf.add(s);
            _lastChar = s.uCharCodeAt(s.uLength() - 1);
            var i = s.uLength() - 1;
            while (i >= 0) {
                final c = s.uCharCodeAt(i);
                if (c != ' '.code && c != '\n'.code && c != '\r'.code && c != '\t'.code) {
                    _lastVisibleChar = c;
                    break;
                }
                i--;
            }
        }
        return this;
    }

    /**
     * Writes a line break to the output.
     * @return This printer instance for chaining
     */
    public extern inline overload function writeln() {
        return newline();
    }

    /**
     * Writes a string followed by a line break to the output.
     * @param s String to write before the line break
     * @return This printer instance for chaining
     */
    public extern inline overload function writeln(s:String) {
        write(s);
        return newline();
    }

    /**
     * Internal implementation of writeln.
     * @param s Optional string to write before the line break
     * @return This printer instance for chaining
     */
    function _writeln(s:String = "") {
        write(s);
        return newline();
    }

    /**
     * Adds a newline to the output, limiting consecutive blank lines to 1.
     * @return This printer instance for chaining
     */
    public function newline() {
        if (_beginLine < 2 && _noLn == 0) {
            if (_beginLine == 1) {
                _numEmptyLines++;
            }
            _buf.add(_newline);
            _beginLine++;
        }
        return this;
    }

    /**
     * Adds indentation at the current level to the output.
     * @return This printer instance for chaining
     */
    public function tab() {
        for (_ in 0..._level)
            _buf.add(_indent);
        return this;
    }

    /**
     * Alias for newline().
     * @return This printer instance for chaining
     */
    public extern inline overload function line() {
        return newline();
    }

    /**
     * Alias for _line().
     * @param s String to write
     * @return This printer instance for chaining
     */
    public extern inline overload function line(s:String) {
        return _line(s);
    }

    /**
     * Writes an indented line to the output.
     * @param s String to write
     * @return This printer instance for chaining
     */
    function _line(s:String) {
        tab();
        _buf.add(s);
        return newline();
    }

    /**
     * Returns the current content of the output buffer.
     * @return Generated source code
     */
    public function toString() {
        return _buf.toString();
    }

    /**
     * Main entry point for printing an AST node to source code.
     * @param node Root node to print
     * @return Generated source code as string
     */
    public function print(node:Node):String {
        clear();
        _beginLine = 1;
        printNode(node);
        return toString();
    }

    /**
     * Dispatches a node to its appropriate printing function based on type.
     * @param node Node to print
     */
    function printNode(node:Node, sameLine:Bool = false) {
        switch (Type.getClass(node)) {
            case Script:
                printScript(cast node);
            case NStateDecl:
                printStateDecl(cast node);
            case NCharacterDecl:
                printCharacterDecl(cast node);
            case NBeatDecl:
                printBeatDecl(cast node);
            case NFunctionDecl:
                printFunctionDecl(cast node);
            case NTextStatement:
                printTextStatement(cast node);
            case NDialogueStatement:
                printDialogueStatement(cast node);
            case NChoiceStatement:
                printChoiceStatement(cast node);
            case NImportStatement:
                printImportStatement(cast node);
            case NChoiceOption:
                printChoiceOption(cast node);
            case NIfStatement:
                printIfStatement(cast node);
            case NTransition:
                printTransition(cast node, sameLine);
            case NInsertion:
                printInsertion(cast node);
            case NStringLiteral:
                printStringLiteral(cast node);
            case NLiteral:
                printLiteral(cast node);
            case NAccess:
                printAccess(cast node);
            case NArrayAccess:
                printArrayAccess(cast node);
            case NCall:
                printCall(cast node);
            case NBinary:
                printBinary(cast node);
            case NUnary:
                printUnary(cast node);
            case NAssign:
                printAssignment(cast node);
            case _:
                throw 'Unsupported node type: ${Type.getClassName(Type.getClass(node))}';
        }
    }

    /**
     * Prints any leading comments attached to a node.
     * @param node Node with potential comments
     */
    function printLeadingComments(node:AstNode) {
        if (enableComments && node.leadingComments != null) {
            for (comment in node.leadingComments) {
                if (comment.multiline) {
                    writeln('/*${comment.content}*/');
                }
                else {
                    writeln('//${comment.content}');
                }
            }
        }
    }

    /**
     * Prints any trailing comments attached to a node.
     * @param node Node with potential comments
     */
    function printTrailingComments(node:AstNode) {
        if (enableComments && node.trailingComments != null) {
            for (comment in node.trailingComments) {
                if (_lastChar != ' '.code && _beginLine == 0) {
                    write(' ');
                }
                if (comment.multiline) {
                    write('/*${comment.content}*/ ');
                }
                else {
                    writeln('//${comment.content}');
                }
            }
        }
    }

    /**
     * Prints an import statement.
     * @param imp Import statement node
     */
    function printImport(imp:NImportStatement) {
        printLeadingComments(imp);
        writeln('import "${imp.path}"');
        printTrailingComments(imp);
    }

    /**
     * Prints a complete Loreline script node.
     * @param script Script node to print
     */
    function printScript(script:Script) {
        for (decl in script.body) {
            _prevLevel = _level;
            printNode(decl);
        }
    }

    /**
     * Prints a state declaration node.
     * @param state State declaration to print
     */
    function printStateDecl(state:NStateDecl) {
        writeln();
        writeln();
        printLeadingComments(state);
        if (state.temporary) write('new ');
        write('state ');
        printTrailingComments(state);
        if (state.style == Braces) writeln('{');
        else writeln();
        indent();
        var first = true;
        for (field in state.fields) {
            if (!first) {
                if (_beginLine == 0) {
                    writeln();
                }
            }
            first = false;
            printLeadingComments(field);
            write('${field.name}: ');
            printTrailingComments(field);
            printNode(field.value);
        }
        writeln();
        unindent();
        if (state.style == Braces) writeln('}');
    }

    /**
     * Prints a character declaration node.
     * @param char Character declaration to print
     */
    function printCharacterDecl(char:NCharacterDecl) {
        writeln();
        writeln();
        printLeadingComments(char);
        write('character ${char.name} ');
        printTrailingComments(char);
        if (char.style == Braces) writeln('{');
        else writeln();
        indent();
        for (prop in char.fields) {
            printLeadingComments(prop);
            write('${prop.name}: ');
            printTrailingComments(prop);
            printNode(prop.value);
            if (_beginLine == 0) {
                writeln();
            }
        }
        unindent();
        if (char.style == Braces) writeln('}');
    }

    /**
     * Prints a beat declaration node.
     * @param beat Beat declaration to print
     */
    function printBeatDecl(beat:NBeatDecl) {
        writeln();
        writeln();
        printLeadingComments(beat);
        write('beat ${beat.name} ');
        printTrailingComments(beat);
        if (beat.style == Braces) writeln('{');
        writeln();
        writeln();
        indent();
        for (i in 0...beat.body.length) {
            _prevLevel = _level;
            printNode(beat.body[i]);
            if (i < beat.body.length - 1) {
                writeln();
            }
        }
        unindent();
        if (_beginLine == 0) writeln();
        if (_lastVisibleChar != '}'.code) writeln();
        if (beat.style == Braces) writeln('}');
    }

    /**
     * Prints a function declaration node.
     * @param func Function declaration to print
     */
    function printFunctionDecl(func:NFunctionDecl) {
        writeln();
        writeln();
        printLeadingComments(func);
        write(func.code);
        printTrailingComments(func);
    }

    /**
     * Prints a text statement node.
     * @param text Text statement to print
     */
    function printTextStatement(text:NTextStatement) {
        if (_level == _prevLevel) {
            writeln();
        }
        printLeadingComments(text);
        printNode(text.content);
        printTrailingComments(text);
    }

    /**
     * Prints a dialogue statement node.
     * @param dialogue Dialogue statement to print
     */
    function printDialogueStatement(dialogue:NDialogueStatement) {
        if (_level == _prevLevel) {
            writeln();
        }
        printLeadingComments(dialogue);
        write('${dialogue.character}: ');
        printTrailingComments(dialogue);
        printNode(dialogue.content);
    }

    /**
     * Prints a choice statement node.
     * @param choice Choice statement to print
     */
    function printChoiceStatement(choice:NChoiceStatement) {
        writeln();
        writeln();
        printLeadingComments(choice);
        write('choice ');
        printTrailingComments(choice);
        if (choice.style == Braces) writeln('{');
        else writeln();
        indent();
        if (choice.options.length > 0) {
            _noLn++;
            for (option in choice.options) {
                printNode(option);
                writeln();
            }
        }
        unindent();
        if (choice.style == Braces) writeln('}');
    }

    /**
     * Prints an import statement node.
     * @param imp Import statement to print
     */
    function printImportStatement(imp:NImportStatement) {
        writeln();
        writeln();
        printLeadingComments(imp);
        write('import ');
        printStringLiteral(imp.path);
        printTrailingComments(imp);
    }

    /**
     * Prints a choice option node.
     * @param option Choice option to print
     */
    function printChoiceOption(option:NChoiceOption) {
        writeln();
        writeln();
        _noLn = 0;
        printLeadingComments(option);
        printNode(option.text);
        printTrailingComments(option);
        if (option.condition != null) {
            write(' if ');
            printInLineExpression(option.condition, option.conditionStyle == Parens);
        }
        if (option.body.length > 0) {
            if (option.condition == null && option.body.length == 1 && (Std.isOfType(option.body[0], NTransition))) {
                _prevLevel = _level;
                write(' ');
                printNode(option.body[0], true);
                if (_beginLine == 0) writeln();
            }
            else {
                if (option.style == Braces)
                    writeln(' {');
                else
                    writeln();
                _prevLevel = _level;
                indent();
                for (node in option.body) {
                    printNode(node);
                    if (_beginLine == 0 && node != option.body[option.body.length - 1]) {
                        writeln();
                    }
                    _prevLevel = _level;
                }
                unindent();
                writeln();
                if (option.style == Braces)
                    writeln('}');
            }
        }
        else {
            writeln();
        }
    }

    /**
     * Prints an if statement node, handling both simple if and if-else structures.
     * @param ifStmt If statement to print
     * @param isElseIf Whether this is part of an else-if chain
     */
    function printIfStatement(ifStmt:NIfStatement, isElseIf:Bool = false) {
        if (_level == _prevLevel) {
            writeln();
        }
        printLeadingComments(ifStmt);
        write('if ');
        printInLineExpression(ifStmt.condition, ifStmt.conditionStyle == Parens);
        printTrailingComments(ifStmt);
        if (ifStmt.thenBranch.style == Braces) write(' {');
        writeln();
        _prevLevel = _level;
        indent();
        var emptyLinesBeforeIf = _numEmptyLines;
        for (node in ifStmt.thenBranch.body) {
            printNode(node);
            writeln();
            _prevLevel = _level;
        }
        unindent();
        if (ifStmt.thenBranch.style == Braces) write('}');
        if (ifStmt.elseBranch != null) {
            if (ifStmt.elseBranch.body.length == 1 && ifStmt.elseBranch.body[0] is NIfStatement) {
                final subIf:NIfStatement = cast ifStmt.elseBranch.body[0];
                if (_numEmptyLines - emptyLinesBeforeIf > 0 || needsEmptyLines(subIf))
                    writeln();
                write('else ');
                printIfStatement(cast ifStmt.elseBranch.body[0], true);
            }
            else {
                if (_numEmptyLines - emptyLinesBeforeIf > 0)
                    writeln();
                if (ifStmt.elseBranch.style == Braces) writeln('else {');
                else writeln('else');
                _prevLevel = _level;
                indent();
                for (node in ifStmt.elseBranch.body) {
                    printNode(node);
                    writeln();
                    _prevLevel = _level;
                }
                unindent();
                if (ifStmt.elseBranch.style == Braces) writeln('}');
            }
        }
    }

    function needsEmptyLines(node:AstNode) {

        // Not optimal, but accurate
        final printer = new Printer(_indent, "\n");
        return printer.print(node).indexOf("\n\n") != -1;

    }

    /**
     * Prints a transition node.
     * @param trans Transition to print
     */
    function printTransition(trans:NTransition, sameLine:Bool) {
        if (!sameLine && _prevLevel == _level) {
            writeln();
        }
        printLeadingComments(trans);
        write('-> ${trans.target}');
        printTrailingComments(trans);
    }

    /**
     * Prints an insertion node.
     * @param insert Insertion to print
     */
    function printInsertion(insert:NInsertion) {
        if (_prevLevel == _level) {
            writeln();
        }
        printLeadingComments(insert);
        write('+ ${insert.target}');
        printTrailingComments(insert);
    }

    /**
     * Prints a string literal node, handling both plain strings and strings with quotes.
     * @param str String literal to print
     * @param surroundWithQuotes Whether to add quotation marks
     */
    function printStringLiteral(str:NStringLiteral) {
        final surroundWithQuotes = (str.quotes == DoubleQuotes);
        if (surroundWithQuotes) {
            printLeadingComments(str);
            write('"');
        }
        for (part in str.parts) {
            switch (part.partType) {
                case Raw(text):
                    write(text);
                case Expr(expr):
                    // TODO differenciate simple and complex interpolation
                    final needsBraces = !Std.isOfType(expr, NAccess);
                    write('$');
                    if (needsBraces) write('{');
                    printNode(expr);
                    if (needsBraces) write('}');
                case Tag(closing, content):
                    write(closing ? '</' : '<');
                    printStringLiteral(content);
                    write('>');
            }
        }
        if (surroundWithQuotes) {
            write('"');
            printTrailingComments(str);
        }
    }

    /**
     * Prints a literal value node (numbers, booleans, arrays, objects).
     * @param lit Literal node to print
     */
    function printLiteral(lit:NLiteral) {
        printLeadingComments(lit);
        switch (lit.literalType) {
            case Number:
                write(Std.string(lit.value));
            case Boolean:
                write(lit.value ? 'true' : 'false');
            case Null:
                write('null');
            case Array:
                var first = true;
                write('[');
                for (elem in (lit.value:Array<Dynamic>)) {
                    if (!first) write(', ');
                    first = false;
                    printNode(elem);
                }
                write(']');
            case Object(style):
                if (style == Braces) writeln('{');
                indent();
                var first = true;
                for (field in (lit.value:Array<NObjectField>)) {
                    if (!first) {
                        if (_beginLine == 0) {
                            writeln();
                        }
                    }
                    first = false;
                    printLeadingComments(field);
                    write('${field.name}: ');
                    printTrailingComments(field);
                    printNode(field.value);
                }
                writeln();
                unindent();
                if (style == Braces) write('}');
        }
        printTrailingComments(lit);
    }

    /**
     * Prints a field access expression (object.field).
     * @param access Field access node to print
     */
    function printAccess(access:NAccess) {
        printLeadingComments(access);
        if (access.target != null) {
            printNode(access.target);
            write('.');
        }
        write(access.name);
        printTrailingComments(access);
    }

    /**
     * Prints an array access expression (array[index]).
     * @param access Array access node to print
     */
    function printArrayAccess(access:NArrayAccess) {
        printLeadingComments(access);
        printNode(access.target);
        write('[');
        printNode(access.index);
        write(']');
        printTrailingComments(access);
    }

    /**
     * Prints a function call expression.
     * @param call Function call node to print
     */
    function printCall(call:NCall) {
        printLeadingComments(call);
        printNode(call.target);
        write('(');
        var first = true;
        for (arg in call.args) {
            if (!first) write(', ');
            first = false;
            printNode(arg);
        }
        write(')');
        printTrailingComments(call);
    }

    /**
     * Prints a binary operation expression (a + b, a && b, etc).
     * Handles operator precedence with parentheses when needed.
     * @param binary Binary operation node to print
     */
    function printBinary(binary:NBinary, skipParen:Bool = false) {
        printLeadingComments(binary);
        final needsParens = !skipParen && switch binary.op {
            case OpAnd(word) | OpOr(word): true;
            case _: false;
        };
        if (needsParens) write('(');
        printNode(binary.left);
        write(' ${getOperator(binary.op)} ');
        printNode(binary.right);
        if (needsParens) write(')');
        printTrailingComments(binary);
    }

    /**
     * Prints a unary operation expression (!x, -x).
     * @param unary Unary operation node to print
     */
    function printUnary(unary:NUnary) {
        printLeadingComments(unary);
        write(getOperator(unary.op));
        printTrailingComments(unary);
        printNode(unary.operand);
    }

    /**
     * Prints an assignment expression (a = b, a += b).
     * @param assign Assignment node to print
     */
    function printAssignment(assign:NAssign) {
        printLeadingComments(assign);
        printNode(assign.target);
        printTrailingComments(assign);
        write(' ${getOperator(assign.op)} ');
        printNode(assign.value);
    }

    /**
     * Prints an in-line expression optionally wrapped in parentheses.
     * @param expr Expression to wrap in parentheses
     */
    function printInLineExpression(expr:NExpr, parens:Bool) {
        if (parens) write('(');
        if (expr is NBinary) {
            printBinary(cast expr, true);
        }
        else {
            printNode(expr);
        }
        if (parens) write(')');
    }

    /**
     * Converts a token type to its corresponding operator string representation.
     * @param op Token type to convert
     * @return String representation of the operator
     * @throws String if the operator is not supported
     */
    function getOperator(op:TokenType):String {
        return switch (op) {
            case OpAssign: "=";
            case OpPlusAssign: "+=";
            case OpMinusAssign: "-=";
            case OpMultiplyAssign: "*=";
            case OpDivideAssign: "/=";
            case OpPlus: "+";
            case OpMinus: "-";
            case OpMultiply: "*";
            case OpDivide: "/";
            case OpModulo: "%";
            case OpEquals: "==";
            case OpNotEquals: "!=";
            case OpGreater: ">";
            case OpLess: "<";
            case OpGreaterEq: ">=";
            case OpLessEq: "<=";
            case OpAnd(false): "&&";
            case OpOr(false): "||";
            case OpAnd(true): "and";
            case OpOr(true): "or";
            case OpNot: "!";
            case _: throw 'Unsupported operator: $op';
        }
    }
}