package loreline;

import loreline.Node;
import loreline.Lexer.TokenType;

/**
 * Utility class for reconstructing AST nodes from their JSON representation.
 * This is the reverse of the toJson() methods on each node class.
 */
class JsonToAst {

    /**
     * Reconstructs a Script from its JSON representation.
     * @param json The JSON object (as returned by Script.toJson())
     * @return The reconstructed Script
     * @throws String if the JSON does not represent a Script node
     */
    public static function scriptFromJson(json:Dynamic):Script {
        if (json == null) throw 'Cannot create Script from null JSON';
        final nodeType:String = json.type;
        if (nodeType != "Script") throw 'Expected Script node, got: $nodeType';

        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final bodyArr:Array<Dynamic> = json.body;
        final body:Array<AstNode> = [for (item in bodyArr) cast nodeFromJson(item)];
        final script = new Script(id, pos, body);
        script.indentSize = json.indentSize != null ? (json.indentSize : Int) : 2;
        applyComments(script, json);
        return script;
    }

    /**
     * Reconstructs any AST Node from its JSON representation.
     * Dispatches based on the "type" field.
     * @param json The JSON object (as returned by node.toJson())
     * @return The reconstructed Node
     * @throws String if the node type is unknown
     */
    public static function nodeFromJson(json:Dynamic):Node {
        if (json == null) return null;
        final nodeType:String = json.type;

        return switch nodeType {
            case "Script": scriptFromJson(json);
            case "Comment": commentFromJson(json);
            case "State": stateFromJson(json);
            case "Field": objectFieldFromJson(json);
            case "Character": characterFromJson(json);
            case "Beat": beatFromJson(json);
            case "Part": stringPartFromJson(json);
            case "String": stringLiteralFromJson(json);
            case "Text": textStatementFromJson(json);
            case "Dialogue": dialogueStatementFromJson(json);
            case "Choice": choiceStatementFromJson(json);
            case "Option": choiceOptionFromJson(json);
            case "Block": blockFromJson(json);
            case "If": ifStatementFromJson(json);
            case "Alternative": alternativeFromJson(json);
            case "Call": callFromJson(json);
            case "Transition": transitionFromJson(json);
            case "Insertion": insertionFromJson(json);
            case "Function": functionDeclFromJson(json);
            case "Literal": literalFromJson(json);
            case "Access": accessFromJson(json);
            case "Assign": assignFromJson(json);
            case "ArrayAccess": arrayAccessFromJson(json);
            case "Binary": binaryFromJson(json);
            case "Unary": unaryFromJson(json);
            case "Ternary": ternaryFromJson(json);
            case "Import": importStatementFromJson(json);
            case _: throw 'Unknown node type: $nodeType';
        }
    }

    // --- Individual node constructors ---

    static function commentFromJson(json:Dynamic):Comment {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final isHash:Bool = json.isHash != null ? (json.isHash : Bool) : false;
        return new Comment(id, pos, json.content, json.multiline, isHash);
    }

    static function stateFromJson(json:Dynamic):NStateDecl {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final fieldsArr:Array<Dynamic> = json.fields;
        final fields:Array<NObjectField> = [for (f in fieldsArr) cast nodeFromJson(f)];
        final comments = extractComments(json);
        final node = new NStateDecl(id, pos, json.temporary, fields, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        return node;
    }

    static function objectFieldFromJson(json:Dynamic):NObjectField {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final comments = extractComments(json);
        return new NObjectField(id, pos, json.name, cast nodeFromJson(json.value), comments.leading, comments.trailing);
    }

    static function characterFromJson(json:Dynamic):NCharacterDecl {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final namePos = positionFromJson(json.namePos);
        final fieldsArr:Array<Dynamic> = json.fields;
        final fields:Array<NObjectField> = [for (f in fieldsArr) cast nodeFromJson(f)];
        final comments = extractComments(json);
        final node = new NCharacterDecl(id, pos, json.name, namePos, fields, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        return node;
    }

    static function beatFromJson(json:Dynamic):NBeatDecl {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final bodyArr:Array<Dynamic> = json.body;
        final body:Array<AstNode> = [for (item in bodyArr) cast nodeFromJson(item)];
        final comments = extractComments(json);
        final node = new NBeatDecl(id, pos, json.name, body, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        return node;
    }

    static function stringPartFromJson(json:Dynamic):NStringPart {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final partStr:String = json.part;
        final partType:StringPartType = switch partStr {
            case "Raw": Raw(json.text);
            case "Expr": Expr(cast nodeFromJson(json.expression));
            case "Tag": Tag(json.closing, cast nodeFromJson(json.content));
            case _: throw 'Unknown string part type: $partStr';
        }
        final comments = extractComments(json);
        return new NStringPart(id, pos, partType, comments.leading, comments.trailing);
    }

    static function stringLiteralFromJson(json:Dynamic):NStringLiteral {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final quotes = quotesFromString(json.quotes);
        final partsArr:Array<Dynamic> = json.parts;
        final parts:Array<NStringPart> = [for (p in partsArr) cast nodeFromJson(p)];
        final comments = extractComments(json);
        return new NStringLiteral(id, pos, quotes, parts, comments.leading, comments.trailing);
    }

    static function textStatementFromJson(json:Dynamic):NTextStatement {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final content:NStringLiteral = cast nodeFromJson(json.content);
        final comments = extractComments(json);
        final node = new NTextStatement(id, pos, content, comments.leading, comments.trailing);
        if (json.condition != null) {
            node.condition = cast nodeFromJson(json.condition);
            node.conditionStyle = conditionStyleFromString(json.conditionStyle);
            node.conditionPos = positionFromJson(json.conditionPos);
        }
        return node;
    }

    static function dialogueStatementFromJson(json:Dynamic):NDialogueStatement {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final characterPos = positionFromJson(json.characterPos);
        final content:NStringLiteral = cast nodeFromJson(json.content);
        final comments = extractComments(json);
        final node = new NDialogueStatement(id, pos, json.character, characterPos, content, comments.leading, comments.trailing);
        if (json.condition != null) {
            node.condition = cast nodeFromJson(json.condition);
            node.conditionStyle = conditionStyleFromString(json.conditionStyle);
            node.conditionPos = positionFromJson(json.conditionPos);
        }
        return node;
    }

    static function choiceStatementFromJson(json:Dynamic):NChoiceStatement {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final optionsArr:Array<Dynamic> = json.options;
        final options:Array<NChoiceOption> = [for (o in optionsArr) cast nodeFromJson(o)];
        final comments = extractComments(json);
        final node = new NChoiceStatement(id, pos, options, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        return node;
    }

    static function choiceOptionFromJson(json:Dynamic):NChoiceOption {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final text:NStringLiteral = json.text != null ? cast nodeFromJson(json.text) : null;
        final insertion:NInsertion = json.insertion != null ? cast nodeFromJson(json.insertion) : null;
        final condition:NExpr = json.condition != null ? cast nodeFromJson(json.condition) : null;
        final condStyle = json.conditionStyle != null ? conditionStyleFromString(json.conditionStyle) : ConditionStyle.Plain;
        final bodyArr:Array<Dynamic> = json.body;
        final body:Array<AstNode> = [for (item in bodyArr) cast nodeFromJson(item)];
        final comments = extractComments(json);
        final node = new NChoiceOption(id, pos, text, insertion, condition, condStyle, body, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        if (json.once != null && (json.once : Bool)) node.once = true;
        if (json.conditionPos != null) node.conditionPos = positionFromJson(json.conditionPos);
        return node;
    }

    static function blockFromJson(json:Dynamic):NBlock {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final bodyArr:Array<Dynamic> = json.body;
        final body:Array<AstNode> = [for (item in bodyArr) cast nodeFromJson(item)];
        final comments = extractComments(json);
        final node = new NBlock(id, pos, body, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);
        return node;
    }

    static function ifStatementFromJson(json:Dynamic):NIfStatement {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final condition:NExpr = cast nodeFromJson(json.condition);
        final condStyle = conditionStyleFromString(json.conditionStyle);

        // Reconstruct thenBranch as NBlock from flat array + style
        final thenArr:Array<Dynamic> = json.thenBranch;
        final thenBody:Array<AstNode> = [for (item in thenArr) cast nodeFromJson(item)];
        final thenBlock = new NBlock(NodeId.UNDEFINED, pos, thenBody);
        thenBlock.style = blockStyleFromString(json.thenStyle);

        // Reconstruct elseBranch if present
        var elseBlock:NBlock = null;
        if (json.elseBranch != null) {
            final elseArr:Array<Dynamic> = json.elseBranch;
            final elseBody:Array<AstNode> = [for (item in elseArr) cast nodeFromJson(item)];
            elseBlock = new NBlock(NodeId.UNDEFINED, pos, elseBody);
            elseBlock.style = blockStyleFromString(json.elseStyle);
        }

        // Extract comments including else-specific comments
        final comments = extractComments(json);
        var elseLeading:Array<Comment> = null;
        var elseTrailing:Array<Comment> = null;
        if (json.comments != null) {
            if (json.comments.elseLeading != null) {
                final arr:Array<Dynamic> = json.comments.elseLeading;
                elseLeading = [for (c in arr) commentFromJson(c)];
            }
            if (json.comments.elseTrailing != null) {
                final arr:Array<Dynamic> = json.comments.elseTrailing;
                elseTrailing = [for (c in arr) commentFromJson(c)];
            }
        }

        return new NIfStatement(id, pos, condition, condStyle, thenBlock, elseBlock, comments.leading, comments.trailing, elseLeading, elseTrailing);
    }

    static function alternativeFromJson(json:Dynamic):NAlternative {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final mode = alternativeModeFromString(json.mode);
        final itemsArr:Array<Dynamic> = json.items;
        final items:Array<NBlock> = [for (item in itemsArr) cast nodeFromJson(item)];
        final comments = extractComments(json);
        final node = new NAlternative(id, pos, mode, items, comments.leading, comments.trailing);
        node.style = blockStyleFromString(json.style);

        // Reconstruct separatorComments
        if (json.separatorComments != null) {
            final sepArr:Array<Dynamic> = json.separatorComments;
            node.separatorComments = [for (commentsGroup in sepArr) {
                if (commentsGroup != null) {
                    final group:Array<Dynamic> = commentsGroup;
                    [for (c in group) commentFromJson(c)];
                } else {
                    null;
                }
            }];
        }

        return node;
    }

    static function callFromJson(json:Dynamic):NCall {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final target:NExpr = cast nodeFromJson(json.target);
        final argsArr:Array<Dynamic> = json.args;
        final args:Array<NExpr> = [for (a in argsArr) cast nodeFromJson(a)];
        final comments = extractComments(json);
        return new NCall(id, pos, target, args, comments.leading, comments.trailing);
    }

    static function transitionFromJson(json:Dynamic):NTransition {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final targetPos = positionFromJson(json.targetPos);
        final comments = extractComments(json);
        return new NTransition(id, pos, json.target, targetPos, comments.leading, comments.trailing);
    }

    static function insertionFromJson(json:Dynamic):NInsertion {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final targetPos = positionFromJson(json.targetPos);
        final comments = extractComments(json);
        return new NInsertion(id, pos, json.target, targetPos, comments.leading, comments.trailing);
    }

    static function functionDeclFromJson(json:Dynamic):NFunctionDecl {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final name:Null<String> = json.name;
        final argsArr:Array<Dynamic> = json.args;
        final args:Array<String> = [for (a in argsArr) (a : String)];
        final comments = extractComments(json);
        return new NFunctionDecl(id, pos, name, args, json.code, json.external, comments.leading, comments.trailing);
    }

    static function literalFromJson(json:Dynamic):NLiteral {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final litStr:String = json.literal;
        final comments = extractComments(json);

        var literalType:LiteralType;
        var value:Any;

        switch litStr {
            case "Number":
                literalType = Number;
                value = json.value;
            case "Boolean":
                literalType = Boolean;
                value = json.value;
            case "Null":
                literalType = Null;
                value = null;
            case "Array":
                literalType = LiteralType.Array;
                if (json.value != null) {
                    final arr:Array<Dynamic> = json.value;
                    value = [for (elem in arr) {
                        if (Reflect.hasField(elem, "type")) {
                            nodeFromJson(elem);
                        } else {
                            (elem : Any);
                        }
                    }];
                } else {
                    value = null;
                }
            case "Object":
                final style = blockStyleFromString(json.style);
                literalType = LiteralType.Object(style);
                if (json.value != null) {
                    final arr:Array<Dynamic> = json.value;
                    value = ([for (f in arr) cast nodeFromJson(f)] : Array<NObjectField>);
                } else {
                    value = ([] : Array<NObjectField>);
                }
            case _:
                throw 'Unknown literal type: $litStr';
        }

        return new NLiteral(id, pos, value, literalType, comments.leading, comments.trailing);
    }

    static function accessFromJson(json:Dynamic):NAccess {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final target:Null<NExpr> = json.target != null ? cast nodeFromJson(json.target) : null;
        final comments = extractComments(json);
        return new NAccess(id, pos, target, json.name, comments.leading, comments.trailing);
    }

    static function assignFromJson(json:Dynamic):NAssign {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final target:NExpr = cast nodeFromJson(json.target);
        final op = tokenTypeFromString(json.op);
        final value:NExpr = cast nodeFromJson(json.value);
        final comments = extractComments(json);
        return new NAssign(id, pos, target, op, value, comments.leading, comments.trailing);
    }

    static function arrayAccessFromJson(json:Dynamic):NArrayAccess {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final target:NExpr = cast nodeFromJson(json.target);
        final index:NExpr = cast nodeFromJson(json.index);
        final comments = extractComments(json);
        return new NArrayAccess(id, pos, target, index, comments.leading, comments.trailing);
    }

    static function binaryFromJson(json:Dynamic):NBinary {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final left:NExpr = cast nodeFromJson(json.left);
        final op = tokenTypeFromString(json.op);
        final right:NExpr = cast nodeFromJson(json.right);
        final comments = extractComments(json);
        return new NBinary(id, pos, left, op, right, comments.leading, comments.trailing);
    }

    static function unaryFromJson(json:Dynamic):NUnary {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final op = tokenTypeFromString(json.op);
        final operand:NExpr = cast nodeFromJson(json.operand);
        final comments = extractComments(json);
        return new NUnary(id, pos, op, operand, comments.leading, comments.trailing);
    }

    static function ternaryFromJson(json:Dynamic):NTernary {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final condition:NExpr = cast nodeFromJson(json.condition);
        final trueExpr:NExpr = cast nodeFromJson(json.trueExpr);
        final falseExpr:NExpr = cast nodeFromJson(json.falseExpr);
        final comments = extractComments(json);
        return new NTernary(id, pos, condition, trueExpr, falseExpr, comments.leading, comments.trailing);
    }

    static function importStatementFromJson(json:Dynamic):NImportStatement {
        final id = idFromJson(json);
        final pos = positionFromJson(json.pos);
        final path:NStringLiteral = cast nodeFromJson(json.path);
        final script:Script = json.script != null ? scriptFromJson(json.script) : null;
        final comments = extractComments(json);
        return new NImportStatement(id, pos, path, script, comments.leading, comments.trailing);
    }

    // --- Helper methods ---

    static function idFromJson(json:Dynamic):NodeId {
        final idStr:String = json.id;
        return idStr != null ? NodeId.fromString(idStr) : NodeId.UNDEFINED;
    }

    static function positionFromJson(json:Dynamic):Position {
        if (json == null) return new Position(0, 0, 0, 0);
        final length:Int = json.length != null ? (json.length : Int) : 0;
        return new Position(json.line, json.column, json.offset, length);
    }

    static function extractComments(json:Dynamic):{leading:Array<Comment>, trailing:Array<Comment>} {
        if (json.comments == null) return {leading: null, trailing: null};

        var leading:Array<Comment> = null;
        var trailing:Array<Comment> = null;

        if (json.comments.leading != null) {
            final arr:Array<Dynamic> = json.comments.leading;
            leading = [for (c in arr) commentFromJson(c)];
        }
        if (json.comments.trailing != null) {
            final arr:Array<Dynamic> = json.comments.trailing;
            trailing = [for (c in arr) commentFromJson(c)];
        }

        return {leading: leading, trailing: trailing};
    }

    static function applyComments(node:AstNode, json:Dynamic):Void {
        final comments = extractComments(json);
        node.leadingComments = comments.leading;
        node.trailingComments = comments.trailing;
    }

    static function blockStyleFromString(s:String):BlockStyle {
        return switch s {
            case "Braces": Braces;
            case _: Plain;
        }
    }

    static function conditionStyleFromString(s:String):ConditionStyle {
        return switch s {
            case "Parens": Parens;
            case _: Plain;
        }
    }

    static function alternativeModeFromString(s:String):AlternativeMode {
        return switch s {
            case "Cycle": Cycle;
            case "Once": Once;
            case "Pick": Pick;
            case "Shuffle": Shuffle;
            case _: Sequence;
        }
    }

    static function quotesFromString(s:String):Quotes {
        return switch s {
            case "DoubleQuotes": DoubleQuotes;
            case _: Unquoted;
        }
    }

    static function tokenTypeFromString(s:String):TokenType {
        return switch s {
            case "OpAssign": OpAssign;
            case "OpPlusAssign": OpPlusAssign;
            case "OpMinusAssign": OpMinusAssign;
            case "OpMultiplyAssign": OpMultiplyAssign;
            case "OpDivideAssign": OpDivideAssign;
            case "OpUnquotedAssign": OpUnquotedAssign;
            case "OpPlus": OpPlus;
            case "OpMinus": OpMinus;
            case "OpMultiply": OpMultiply;
            case "OpDivide": OpDivide;
            case "OpModulo": OpModulo;
            case "OpEquals": OpEquals;
            case "OpNotEquals": OpNotEquals;
            case "OpGreater": OpGreater;
            case "OpLess": OpLess;
            case "OpGreaterEq": OpGreaterEq;
            case "OpLessEq": OpLessEq;
            case "OpNot": OpNot;
            case _ if (StringTools.startsWith(s, "OpAnd")): OpAnd(s.indexOf("true") != -1);
            case _ if (StringTools.startsWith(s, "OpOr")): OpOr(s.indexOf("true") != -1);
            case _: throw 'Unknown operator: $s';
        }
    }
}
