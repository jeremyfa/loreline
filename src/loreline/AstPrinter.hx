package loreline;

import loreline.Lexer;
import loreline.Node;

/**
 * AST printer that generates a human-readable string representation of the AST.
 * This is useful for debugging and understanding the structure of parsed scripts.
 */
class AstPrinter {
    /**
     * The current indentation level for pretty-printing
     */
    private var indentLevel:Int = 0;

    /**
     * The string used for each level of indentation
     */
    private var indentString:String;

    /**
     * The buffer for building the output string
     */
    private var buffer:StringBuf;

    /**
     * A flag to know if last char was a line break
     */
    private var lastCharIsLineBreak:Bool = false;

    public function new(indentString:String = "  ") {
        this.indentString = indentString;
    }

    /**
     * Print a node and its children to a string
     */
    public function print(node:Node):String {
        lastCharIsLineBreak = false;
        buffer = new StringBuf();
        printNode(node);
        return buffer.toString();
    }

    private extern inline overload function addLineBreak():Void {
        addChar("\n".code);
    }

    private extern inline overload function add(val:String):Void {
        lastCharIsLineBreak = false;
        buffer.add(val);
    }

    private extern inline overload function add(val:Int):Void {
        lastCharIsLineBreak = false;
        buffer.add(val);
    }

    private extern inline overload function add(val:Float):Void {
        lastCharIsLineBreak = false;
        buffer.add(val);
    }

    private extern inline overload function add(val:Bool):Void {
        lastCharIsLineBreak = false;
        buffer.add(val);
    }

    private extern inline overload function addChar(char:Int):Void {
        final isLineBreak = (char == "\n".code);
        if (!isLineBreak || !lastCharIsLineBreak) {
            lastCharIsLineBreak = isLineBreak;
            buffer.addChar(char);
        }
    }

    /**
     * Add indentation to the buffer based on current level
     */
    private function indent():Void {
        for (i in 0...indentLevel) {
            add(indentString);
        }
    }

    private function printBlockStyle(style:BlockStyle):Void {
        switch style {
            case Plain:
            case Braces:
                add(" style=");
                add(style.toString());
        }
    }

    /**
     * Print a node with its type, ID, position, and properties
     */
    private function printNode(node:Node):Void {
        if (node == null) {
            add("null");
            return;
        }

        // Handle indentation
        indent();

        // Node type and ID
        add(Type.getClassName(Type.getClass(node)).split(".").pop());
        addChar("(".code);
        add(node.id.toString());
        add(") ");

        // Position
        addChar("[".code);
        add(node.pos.line);
        addChar(":".code);
        add(node.pos.column);
        addChar(":".code);
        add(node.pos.offset);
        addChar(":".code);
        add(node.pos.length);
        addChar("]".code);

        // Type-specific attributes
        switch (Type.getClass(node)) {
            case Script:
                final script:Script = cast node;
                addLineBreak();
                indentLevel++;
                for (child in script.body) {
                    printNode(child);
                    addLineBreak();
                }
                indentLevel--;

            case NStateDecl:
                final state:NStateDecl = cast node;
                add(" temporary=");
                add(state.temporary);
                printBlockStyle(state.style);
                addLineBreak();
                indentLevel++;
                for (field in state.fields) {
                    printNode(field);
                    addLineBreak();
                }
                indentLevel--;

            case NObjectField:
                final field:NObjectField = cast node;
                add(' name="');
                add(field.name);
                add('"');
                if (field.value != null) {
                    addLineBreak();
                    indentLevel++;
                    printNode(field.value);
                    indentLevel--;
                }

            case NCharacterDecl:
                final character:NCharacterDecl = cast node;
                add(' name="');
                add(character.name);
                add('"');

                if (character.namePos != null) {
                    add(" namePos=[");
                    add(character.namePos.line);
                    addChar(":".code);
                    add(character.namePos.column);
                    addChar(":".code);
                    add(character.namePos.offset);
                    addChar(":".code);
                    add(character.namePos.length);
                    addChar("]".code);
                }

                printBlockStyle(character.style);
                addLineBreak();
                indentLevel++;
                for (field in character.fields) {
                    printNode(field);
                    addLineBreak();
                }
                indentLevel--;

            case NBeatDecl:
                final beat:NBeatDecl = cast node;
                add(' name="');
                add(beat.name);
                add('"');
                printBlockStyle(beat.style);
                addLineBreak();
                indentLevel++;
                for (item in beat.body) {
                    printNode(item);
                    addLineBreak();
                }
                indentLevel--;

            case NTextStatement:
                final text:NTextStatement = cast node;
                addLineBreak();
                indentLevel++;
                printNode(text.content);
                indentLevel--;

            case NDialogueStatement:
                final dialogue:NDialogueStatement = cast node;
                add(' character="');
                add(dialogue.character);
                add('"');

                if (dialogue.characterPos != null) {
                    add(" characterPos=[");
                    add(dialogue.characterPos.line);
                    addChar(":".code);
                    add(dialogue.characterPos.column);
                    addChar(":".code);
                    add(dialogue.characterPos.offset);
                    addChar(":".code);
                    add(dialogue.characterPos.length);
                    addChar("]".code);
                }

                addLineBreak();
                indentLevel++;
                printNode(dialogue.content);
                indentLevel--;

            case NStringLiteral:
                final str:NStringLiteral = cast node;
                switch str.quotes {
                    case Unquoted:
                    case DoubleQuotes:
                        add(" quotes=");
                        add(str.quotes.toString());
                }
                if (str.parts.length > 0) {
                    addLineBreak();
                    indentLevel++;
                    for (part in str.parts) {
                        printNode(part);
                        addLineBreak();
                    }
                    indentLevel--;
                }

            case NStringPart:
                final part:NStringPart = cast node;
                add(" type=");
                switch (part.partType) {
                    case Raw(text):
                        add('Raw text="');
                        add(StringTools.replace(StringTools.replace(text, "\\", "\\\\"), '"', '\\"'));
                        add('"');

                    case Expr(expr):
                        add("Expr");
                        if (expr != null) {
                            addLineBreak();
                            indentLevel++;
                            printNode(expr);
                            indentLevel--;
                        }

                    case Tag(closing, content):
                        add("Tag closing=");
                        add(closing);
                        if (content != null) {
                            addLineBreak();
                            indentLevel++;
                            printNode(content);
                            indentLevel--;
                        }
                }

            case NFunctionDecl:
                final func:NFunctionDecl = cast node;
                if (func.name != null) {
                    add(' name="');
                    add(func.name);
                    add('"');
                }
                add(" args=[" + func.args.join(', ') + "]");
                addLineBreak();
                indentLevel++;
                for (line in func.code.split("\n")) {
                    indent();
                    add(line);
                    addLineBreak();
                }
                indentLevel--;

            case NLiteral:
                final literal:NLiteral = cast node;
                add(" type=");
                switch (literal.literalType) {
                    case Number:
                        add("Number value=");
                        final val:Float = literal.value;
                        add(val);

                    case Boolean:
                        add("Boolean value=");
                        final val:Bool = literal.value;
                        add(val);

                    case Null:
                        add("Null value=null");

                    case Array:
                        add("Array");
                        if (literal.value != null) {
                            final arr:Array<Dynamic> = cast literal.value;
                            add(" length=");
                            add(arr.length);
                            if (arr.length > 0) {
                                addLineBreak();
                                indentLevel++;
                                for (i in 0...arr.length) {
                                    indent();
                                    add('[${i}]: ');
                                    if (Std.isOfType(arr[i], Node)) {
                                        addLineBreak();
                                        indentLevel++;
                                        printNode(cast arr[i]);
                                        indentLevel--;
                                    } else {
                                        add(Std.string(arr[i]));
                                    }
                                    addLineBreak();
                                }
                                indentLevel--;
                            }
                        }

                    case Object(style):
                        add("Object");
                        printBlockStyle(style);
                        if (literal.value != null) {
                            final fields:Array<NObjectField> = cast literal.value;
                            if (fields.length > 0) {
                                addLineBreak();
                                indentLevel++;
                                for (field in fields) {
                                    printNode(field);
                                    addLineBreak();
                                }
                                indentLevel--;
                            }
                        }
                }

            case NAccess:
                final access:NAccess = cast node;
                add(' name="');
                add(access.name);
                add('"');
                if (access.target != null) {
                    addLineBreak();
                    indentLevel++;
                    indent();
                    add("target:");
                    addLineBreak();
                    indentLevel++;
                    printNode(access.target);
                    indentLevel--;
                    indentLevel--;
                }

            case NArrayAccess:
                final arrayAccess:NArrayAccess = cast node;
                if (arrayAccess.index != null) {
                    addLineBreak();
                    indentLevel++;
                    indent();
                    add("index:");
                    addLineBreak();
                    indentLevel++;
                    printNode(arrayAccess.index);
                    indentLevel--;
                    indentLevel--;
                }
                if (arrayAccess.target != null) {
                    addLineBreak();
                    indentLevel++;
                    indent();
                    add("target:");
                    addLineBreak();
                    indentLevel++;
                    printNode(arrayAccess.target);
                    indentLevel--;
                    indentLevel--;
                }

            case NBinary:
                final binary:NBinary = cast node;
                add(" op=");
                add(getOperatorName(binary.op));
                addLineBreak();
                indentLevel++;
                indent();
                add("left:");
                addLineBreak();
                indentLevel++;
                printNode(binary.left);
                indentLevel--;
                addLineBreak();
                indent();
                add("right:");
                addLineBreak();
                indentLevel++;
                printNode(binary.right);
                indentLevel--;
                indentLevel--;

            case NUnary:
                final unary:NUnary = cast node;
                add(" op=");
                add(getOperatorName(unary.op));
                add(" operand=");
                if (unary.operand != null) {
                    addLineBreak();
                    indentLevel++;
                    printNode(unary.operand);
                    indentLevel--;
                } else {
                    add("null");
                }

            case NAssign:
                final assign:NAssign = cast node;
                add(" op=");
                add(getOperatorName(assign.op));
                addLineBreak();
                indentLevel++;
                indent();
                add("target:");
                addLineBreak();
                indentLevel++;
                printNode(assign.target);
                indentLevel--;
                addLineBreak();
                indent();
                add("value:");
                addLineBreak();
                indentLevel++;
                printNode(assign.value);
                indentLevel--;
                indentLevel--;

            case NCall:
                final call:NCall = cast node;
                add(" target=");
                if (call.target != null) {
                    addLineBreak();
                    indentLevel++;
                    printNode(call.target);
                    indentLevel--;
                } else {
                    add("null");
                }
                if (call.args.length > 0) {
                    add(" args=[");
                    addLineBreak();
                    indentLevel++;
                    for (i in 0...call.args.length) {
                        indent();
                        add('[${i}]: ');
                        addLineBreak();
                        indentLevel++;
                        printNode(call.args[i]);
                        indentLevel--;
                        addLineBreak();
                    }
                    indentLevel--;
                    indent();
                    addChar("]".code);
                } else {
                    add(" args=[]");
                }

            case NIfStatement:
                final ifStmt:NIfStatement = cast node;
                addLineBreak();
                indentLevel++;
                indent();
                add("condition:");
                addLineBreak();
                indentLevel++;
                printNode(ifStmt.condition);
                indentLevel--;
                addLineBreak();
                indent();
                add("then:");
                addLineBreak();
                indentLevel++;
                if (ifStmt.thenBranch != null) {
                    printNode(ifStmt.thenBranch);
                }
                indentLevel--;

                if (ifStmt.elseBranch != null) {
                    addLineBreak();
                    indent();
                    add("else:");
                    addLineBreak();
                    indentLevel++;
                    printNode(ifStmt.elseBranch);
                    indentLevel--;
                }

                // Print else-related comments if present
                if (ifStmt.elseLeadingComments != null && ifStmt.elseLeadingComments.length > 0) {
                    addLineBreak();
                    indent();
                    add("elseLeadingComments: [");
                    addLineBreak();
                    indentLevel++;
                    for (comment in ifStmt.elseLeadingComments) {
                        indent();
                        add('Comment(${comment.id}) [${comment.pos.line}:${comment.pos.column}:${comment.pos.offset}:${comment.pos.length}]');
                        if (comment.multiline) {
                            add(' multiline=');
                            add(comment.multiline);
                        }
                        add(' content="');
                        add(StringTools.replace(StringTools.replace(comment.content, "\\", "\\\\"), '"', '\\"'));
                        add('"');
                        addLineBreak();
                    }
                    indentLevel--;
                    indent();
                    addChar("]".code);
                }

                if (ifStmt.elseTrailingComments != null && ifStmt.elseTrailingComments.length > 0) {
                    addLineBreak();
                    indent();
                    add("elseTrailingComments: [");
                    addLineBreak();
                    indentLevel++;
                    for (comment in ifStmt.elseTrailingComments) {
                        indent();
                        add('Comment(${comment.id}) [${comment.pos.line}:${comment.pos.column}:${comment.pos.offset}:${comment.pos.length}]');
                        add(' multiline=');
                        add(comment.multiline);
                        add(' content="');
                        add(StringTools.replace(StringTools.replace(comment.content, "\\", "\\\\"), '"', '\\"'));
                        add('"');
                        addLineBreak();
                    }
                    indentLevel--;
                    indent();
                    addChar("]".code);
                }

                indentLevel--;

            case NBlock:
                final block:NBlock = cast node;
                printBlockStyle(block.style);
                if (block.body != null && block.body.length > 0) {
                    addLineBreak();
                    indentLevel++;
                    for (item in block.body) {
                        printNode(item);
                        addLineBreak();
                    }
                    indentLevel--;
                }

            case NChoiceStatement:
                final choice:NChoiceStatement = cast node;
                printBlockStyle(choice.style);
                if (choice.options.length > 0) {
                    addLineBreak();
                    indentLevel++;
                    for (i in 0...choice.options.length) {
                        printNode(choice.options[i]);
                        addLineBreak();
                    }
                    indentLevel--;
                }

            case NChoiceOption:
                final option:NChoiceOption = cast node;
                printBlockStyle(option.style);
                addLineBreak();
                indentLevel++;
                indent();
                add("text:");
                addLineBreak();
                indentLevel++;
                printNode(option.text);
                indentLevel--;

                if (option.condition != null) {
                    addLineBreak();
                    indent();
                    add("condition:");
                    addLineBreak();
                    indentLevel++;
                    printNode(option.condition);
                    indentLevel--;
                }

                if (option.body != null && option.body.length > 0) {
                    addLineBreak();
                    indent();
                    add("body:");
                    addLineBreak();
                    indentLevel++;
                    for (item in option.body) {
                        printNode(item);
                        addLineBreak();
                    }
                    indentLevel--;
                }
                indentLevel--;

            case NTransition:
                final transition:NTransition = cast node;
                add(' target="');
                add(transition.target);
                add('"');

                if (transition.targetPos != null) {
                    add(" targetPos=[");
                    add(transition.targetPos.line);
                    addChar(":".code);
                    add(transition.targetPos.column);
                    addChar(":".code);
                    add(transition.targetPos.offset);
                    addChar(":".code);
                    add(transition.targetPos.length);
                    addChar("]".code);
                }

            case NImport:
                final imp:NImport = cast node;
                add(' path="');
                add(imp.path);
                add('"');

            case _:
                throw "Cannot print node: " + Type.getClassName(Type.getClass(node));
        }

        // Add comments if present
        if (Std.isOfType(node, AstNode)) {
            final astNode:AstNode = cast node;
            printComments(astNode);
        }
    }

    /**
     * Print comments attached to a node
     */
    private function printComments(node:AstNode):Void {
        if (node.leadingComments != null && node.leadingComments.length > 0) {
            addLineBreak();
            indentLevel++;
            indent();
            add("leadingComments: [");
            addLineBreak();
            indentLevel++;
            for (comment in node.leadingComments) {
                indent();
                add('Comment(${comment.id}) [${comment.pos.line}:${comment.pos.column}:${comment.pos.offset}:${comment.pos.length}]');
                add(' multiline=');
                add(comment.multiline);
                add(' content="');
                add(StringTools.replace(StringTools.replace(comment.content, "\\", "\\\\"), '"', '\\"'));
                add('"');
                addLineBreak();
            }
            indentLevel--;
            indent();
            addChar("]".code);
            indentLevel--;
        }

        if (node.trailingComments != null && node.trailingComments.length > 0) {
            addLineBreak();
            indentLevel++;
            indent();
            add("trailingComments: [");
            addLineBreak();
            indentLevel++;
            for (comment in node.trailingComments) {
                indent();
                add('Comment(${comment.id}) [${comment.pos.line}:${comment.pos.column}:${comment.pos.offset}:${comment.pos.length}]');
                add(' multiline=');
                add(comment.multiline);
                add(' content="');
                add(StringTools.replace(StringTools.replace(comment.content, "\\", "\\\\"), '"', '\\"'));
                add('"');
                addLineBreak();
            }
            indentLevel--;
            indent();
            addChar("]".code);
            indentLevel--;
        }
    }

    /**
     * Get string representation of token type for operators
     */
    private function getOperatorName(op:TokenType):String {
        return switch (op) {
            case OpPlus: "OpPlus";
            case OpMinus: "OpMinus";
            case OpMultiply: "OpMultiply";
            case OpDivide: "OpDivide";
            case OpModulo: "OpModulo";
            case OpAssign: "OpAssign";
            case OpPlusAssign: "OpPlusAssign";
            case OpMinusAssign: "OpMinusAssign";
            case OpMultiplyAssign: "OpMultiplyAssign";
            case OpDivideAssign: "OpDivideAssign";
            case OpEquals: "OpEquals";
            case OpNotEquals: "OpNotEquals";
            case OpGreater: "OpGreater";
            case OpGreaterEq: "OpGreaterEq";
            case OpLess: "OpLess";
            case OpLessEq: "OpLessEq";
            case OpAnd(word): word ? "OpAnd(and)" : "OpAnd(&&)";
            case OpOr(word): word ? "OpOr(or)" : "OpOr(||)";
            case OpNot: "OpNot";
            case _: Std.string(op);
        }
    }

}