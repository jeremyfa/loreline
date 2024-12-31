package loreline;

import loreline.Lexer;

/**
 * Base class for all AST nodes. Contains position information and basic JSON conversion.
 */
class Node {

    /**
     * A unique identifier for this node within the AST, used to distinguish
     * it from other nodes in the script.
     */
    public var id:Int = -1;

    /**
     * Source code position where this node appears.
     */
    public var pos:Position;

    /**
     * Creates a new AST node.
     * @param pos Position in source where this node appears
     */
    public function new(id:Int, pos:Position) {
        this.id = id;
        this.pos = pos;
    }

    /**
     * Converts the node to a JSON representation.
     * @return Dynamic object containing node type and position
     */
    public function toJson():Dynamic {
        return {
            id: id,
            type: Type.getClassName(Type.getClass(this)).split(".").pop(),
            pos: pos.toJson()
        };
    }

    public function each(handleNode:(node:Node, parent:Node)->Void):Void {

        // Implements in subclasses

    }

}

/**
 * Represents a comment node in the AST. Contains both the comment content
 * and whether it's a multiline comment.
 */
class Comment extends Node {

    /**
     * The actual text content of the comment.
     */
    public var content:String;

    /**
     * Whether this is a multiline comment (/* ... *\/) or single-line comment (//).
     */
    public var multiline:Bool;

    /**
     * Creates a new Comment node.
     * @param pos Position in source where this comment appears
     * @param content The text content of the comment
     * @param multiline Whether this is a multiline comment
     */
    public function new(id:Int, pos:Position, content:String, multiline:Bool) {
        super(id, pos);
        this.content = content;
        this.multiline = multiline;
    }

    /**
     * Converts the comment node to a JSON representation.
     * @return Dynamic object containing comment data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.content = content;
        json.multiline = multiline;
        return json;
    }

}

/**
 * Base class for AST nodes that can have associated comments.
 * Extends Node with support for leading and trailing comments.
 */
class AstNode extends Node {

    /**
     * Comments that appear before this node.
     */
    public var leadingComments:Null<Array<Comment>>;

    /**
     * Comments that appear after this node.
     */
    public var trailingComments:Null<Array<Comment>>;

    /**
     * Creates a new node that supports comments.
     * @param pos Position in source where this node appears
     * @param leadingComments Optional array of comments appearing before the node
     * @param trailingComments Optional array of comments appearing after the node
     */
    public function new(id:Int, pos:Position, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos);
        this.leadingComments = leadingComments;
        this.trailingComments = trailingComments;
    }

    override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (leadingComments != null) {
            for (comment in leadingComments) {
                handleNode(comment, this);
                comment.each(handleNode);
            }
        }

        if (trailingComments != null) {
            for (comment in trailingComments) {
                handleNode(comment, this);
                comment.each(handleNode);
            }
        }

    }

    /**
     * Converts the node and its comments to a JSON representation.
     * @return Dynamic object containing node data and associated comments
     */
    public override function toJson():Dynamic {
        final json = super.toJson();

        if ((leadingComments != null && leadingComments.length > 0) || (trailingComments != null && trailingComments.length > 0)) {
            final comments:Dynamic = {};
            if (leadingComments != null && leadingComments.length > 0) {
                comments.leading = [for (c in leadingComments) c.toJson()];
            }
            if (trailingComments != null && trailingComments.length > 0) {
                comments.trailing = [for (c in trailingComments) c.toJson()];
            }
            json.comments = comments;
        }

        return json;
    }

}

/**
 * Base class for all expression nodes in the AST.
 */
class NExpression extends AstNode {

    /**
     * Converts the expression node to a JSON representation.
     * @return Dynamic object containing expression data
     */
    public override function toJson():Dynamic {
        return super.toJson();
    }

}

/**
 * Represents a state declaration node in the AST.
 * States can be either temporary (new state) or permanent.
 */
class NStateDecl extends AstNode {

    /**
     * Whether this state is temporary (new state).
     */
    public var temporary:Bool;

    /**
     * The fields declared in this state.
     */
    public var fields:NLiteral;

    /**
     * Creates a new state declaration node.
     * @param pos Position in source where this state appears
     * @param temporary Whether this is a temporary state
     * @param fields The fields contained in this state
     * @param leadingComments Optional comments before the state
     * @param trailingComments Optional comments after the state
     */
    public function new(id:Int, pos:Position, temporary:Bool, fields:NLiteral, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.temporary = temporary;
        this.fields = fields;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (fields != null) {
            handleNode(fields, this);
            fields.each(handleNode);
        }
    }

    /**
     * Converts the state declaration to a JSON representation.
     * @return Dynamic object containing state data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.temporary = temporary;
        json.fields = fields.toJson();
        return json;
    }

}

/**
 * Represents an object field in the AST (name-value pair).
 */
class NObjectField extends AstNode {

    /**
     * Name of the field.
     */
    public var name:String;

    /**
     * Value expression of the field.
     */
    public var value:NExpression;

    /**
     * Creates a new object field node.
     * @param pos Position in source where this field appears
     * @param name Name of the field
     * @param value Value expression for the field
     * @param leadingComments Optional comments before the field
     * @param trailingComments Optional comments after the field
     */
    public function new(id:Int, pos:Position, name:String, value:NExpression, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.value = value;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (value != null) {
            handleNode(value, this);
            value.each(handleNode);
        }
    }

    /**
     * Converts the object field to a JSON representation.
     * @return Dynamic object containing field data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.name = name;
        json.value = value.toJson();
        return json;
    }

}

/**
 * Represents a character declaration in the AST.
 */
class NCharacterDecl extends AstNode {

    /**
     * Name of the character.
     */
    public var name:String;

    /**
     * Properties defined for this character.
     */
    public var properties:Array<NObjectField>;

    /**
     * Creates a new character declaration node.
     * @param pos Position in source where this character appears
     * @param name Name of the character
     * @param properties Array of property definitions
     * @param leadingComments Optional comments before the character
     * @param trailingComments Optional comments after the character
     */
    public function new(id:Int, pos:Position, name:String, properties:Array<NObjectField>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.properties = properties;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (properties != null) {
            for (i in 0...properties.length) {
                final child = properties[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the character declaration to a JSON representation.
     * @return Dynamic object containing character data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.name = name;
        json.properties = [for (prop in properties) prop.toJson()];
        return json;
    }

}

/**
 * Represents a beat (scene) declaration in the AST.
 */
class NBeatDecl extends AstNode {

    /**
     * Name of the beat.
     */
    public var name:String;

    /**
     * Array of nodes that make up the beat's content.
     */
    public var body:Array<AstNode>;

    /**
     * Creates a new beat declaration node.
     * @param pos Position in source where this beat appears
     * @param name Name of the beat
     * @param body Array of nodes comprising the beat's content
     * @param leadingComments Optional comments before the beat
     * @param trailingComments Optional comments after the beat
     */
    public function new(id:Int, pos:Position, name:String, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.body = body;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (body != null) {
            for (i in 0...body.length) {
                final child = body[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the beat declaration to a JSON representation.
     * @return Dynamic object containing beat data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.name = name;
        json.body = [for (node in body) node.toJson()];
        return json;
    }

}

/**
 * Represents the different types of string parts that can appear in string literals.
 */
enum StringPartType {

    /**
     * Raw text content.
     */
    Raw(text:String);

    /**
     * Interpolated expression (${...} or $identifier).
     */
    Expr(expr:NExpression);

    /**
     * Text formatting tag (<tag> or </tag>).
     */
    Tag(closing:Bool, expr:NStringLiteral);

}

/**
 * Represents a string part that can appear in string literals.
 */
class NStringPart extends NExpression {

    /**
     * The type of string part
     */
    public var type:StringPartType;

    /**
     * Creates a new string part node.
     * @param pos Position in source where this string part appears
     * @param type The type of string part (raw text, interpolations, and tags)
     * @param leadingComments Optional comments before the string
     * @param trailingComments Optional comments after the string
     */
    public function new(id:Int, pos:Position, type:StringPartType, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.type = type;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        switch type {
            case Raw(_):
            case Expr(expr) | Tag(_, expr):
                handleNode(expr, this);
                expr.each(handleNode);
        }

    }

    /**
     * Converts the string part to a JSON representation.
     * @return Dynamic object containing string part data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        switch type {
            case Raw(text):
                json.type = "Raw";
                json.text = text;
            case Expr(expr):
                json.type = "Expr";
                json.expression = expr.toJson();
            case Tag(closing, expr):
                json.type = "Tag";
                json.closing = closing;
                json.content = expr.toJson();
        }
        return json;
    }

}

/**
 * Represents a string literal in the AST, supporting interpolation and tags.
 */
class NStringLiteral extends NExpression {
    /**
     * Array of parts that make up this string literal.
     */
    public var parts:Array<NStringPart>;

    /**
     * Creates a new string literal node.
     * @param pos Position in source where this string appears
     * @param parts Array of string parts (raw text, interpolations, and tags)
     * @param leadingComments Optional comments before the string
     * @param trailingComments Optional comments after the string
     */
    public function new(id:Int, pos:Position, parts:Array<NStringPart>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.parts = parts;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (parts != null) {
            for (i in 0...parts.length) {
                final part = parts[i];
                handleNode(part, this);
                part.each(handleNode);
            }
        }
    }

    /**
     * Converts the string literal to a JSON representation.
     * @return Dynamic object containing string data and its parts
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        final parts:Array<Any> = [
            for (part in parts) part.toJson()
        ];
        json.parts = parts;
        return json;
    }

}

/**
 * Represents a text statement in the AST.
 */
class NTextStatement extends AstNode {
    /**
     * The content of the text statement.
     */
    public var content:NStringLiteral;

    /**
     * Creates a new text statement node.
     * @param pos Position in source where this text appears
     * @param content String literal containing the text content
     * @param leadingComments Optional comments before the text
     * @param trailingComments Optional comments after the text
     */
    public function new(id:Int, pos:Position, content:NStringLiteral, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.content = content;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (content != null) {
            handleNode(content, this);
            content.each(handleNode);
        }
    }

    /**
     * Converts the text statement to a JSON representation.
     * @return Dynamic object containing text data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.content = content.toJson();
        return json;
    }
}

/**
 * Represents a dialogue statement in the AST (character: "text").
 */
class NDialogueStatement extends AstNode {
    /**
     * Name of the speaking character.
     */
    public var character:String;

    /**
     * Content of the dialogue.
     */
    public var content:NStringLiteral;

    /**
     * Creates a new dialogue statement node.
     * @param pos Position in source where this dialogue appears
     * @param character Name of the speaking character
     * @param content String literal containing the dialogue text
     * @param leadingComments Optional comments before the dialogue
     * @param trailingComments Optional comments after the dialogue
     */
    public function new(id:Int, pos:Position, character:String, content:NStringLiteral, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.character = character;
        this.content = content;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (content != null) {
            handleNode(content, this);
            content.each(handleNode);
        }
    }

    /**
     * Converts the dialogue statement to a JSON representation.
     * @return Dynamic object containing dialogue data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.character = character;
        json.content = content.toJson();
        return json;
    }
}

/**
 * Represents a choice statement in the AST.
 */
class NChoiceStatement extends AstNode {
    /**
     * Array of available options in this choice.
     */
    public var options:Array<NChoiceOption>;

    /**
     * Creates a new choice statement node.
     * @param pos Position in source where this choice appears
     * @param options Array of available choice options
     * @param leadingComments Optional comments before the choice
     * @param trailingComments Optional comments after the choice
     */
    public function new(id:Int, pos:Position, options:Array<NChoiceOption>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.options = options;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (options != null) {
            for (i in 0...options.length) {
                final child = options[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the choice statement to a JSON representation.
     * @return Dynamic object containing choice data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.options = [for (option in options) option.toJson()];
        return json;
    }
}

/**
 * Represents a single option within a choice statement.
 */
class NChoiceOption extends AstNode {
    /**
     * The text displayed for this option.
     */
    public var text:NStringLiteral;

    /**
     * Optional condition that must be true for this option to be available.
     */
    public var condition:Null<NExpression>;

    /**
     * Array of nodes to execute when this option is chosen.
     */
    public var body:Array<AstNode>;

    /**
     * Creates a new choice option node.
     * @param pos Position in source where this option appears
     * @param text String literal containing the option text
     * @param condition Optional condition for option availability
     * @param body Array of nodes to execute when chosen
     * @param leadingComments Optional comments before the option
     * @param trailingComments Optional comments after the option
     */
    public function new(id:Int, pos:Position, text:NStringLiteral, condition:Null<NExpression>, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.text = text;
        this.condition = condition;
        this.body = body;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (condition != null) {
            handleNode(condition, this);
            condition.each(handleNode);
        }
        if (body != null) {
            for (i in 0...body.length) {
                final child = body[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the choice option to a JSON representation.
     * @return Dynamic object containing option data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.text = text.toJson();
        if (condition != null) json.condition = condition.toJson();
        json.body = [for (node in body) node.toJson()];
        return json;
    }
}

/**
 * Represents a block with a sequence multiple nodes
 */
class NBlock extends AstNode {

    /**
     * Array of nodes that make up the beat's content.
     */
    public var body:Array<AstNode>;

    /**
     * Creates a new block node.
     * @param pos Position in source where this beat appears
     * @param body Array of nodes comprising the block's content
     * @param leadingComments Optional comments before the beat
     * @param trailingComments Optional comments after the beat
     */
    public function new(id:Int, pos:Position, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.body = body;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (body != null) {
            for (i in 0...body.length) {
                final child = body[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the beat declaration to a JSON representation.
     * @return Dynamic object containing beat data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.body = [for (node in body) node.toJson()];
        return json;
    }

}

/**
 * Represents an if statement in the AST, with optional else branch.
 */
class NIfStatement extends AstNode {
    /**
     * The condition to evaluate.
     */
    public var condition:NExpression;

    /**
     * Array of nodes to execute if condition is true.
     */
    public var thenBranch:NBlock;

    /**
     * Optional array of nodes to execute if condition is false.
     */
    public var elseBranch:Null<NBlock>;

    /**
     * Comments that appear before the else keyword.
     */
    public var elseLeadingComments:Null<Array<Comment>>;

    /**
     * Comments that appear after the else keyword.
     */
    public var elseTrailingComments:Null<Array<Comment>>;

    /**
     * Creates a new if statement node.
     * @param pos Position in source where this if statement appears
     * @param condition Expression to evaluate
     * @param thenBranch Nodes to execute if condition is true
     * @param elseBranch Optional nodes to execute if condition is false
     * @param leadingComments Optional comments before the if
     * @param trailingComments Optional comments after the if
     * @param elseLeadingComments Optional comments before the else
     * @param elseTrailingComments Optional comments after the else
     */
    public function new(id:Int, pos:Position, condition:NExpression, thenBranch:NBlock, elseBranch:Null<NBlock>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>, ?elseLeadingComments:Array<Comment>, ?elseTrailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.condition = condition;
        this.thenBranch = thenBranch;
        this.elseBranch = elseBranch;
        this.elseLeadingComments = elseLeadingComments;
        this.elseTrailingComments = elseTrailingComments;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (condition != null) {
            handleNode(condition, this);
            condition.each(handleNode);
        }
        if (thenBranch != null) {
            handleNode(thenBranch, this);
            thenBranch.each(handleNode);
        }
        if (elseBranch != null) {
            handleNode(elseBranch, this);
            elseBranch.each(handleNode);
        }
        if (elseLeadingComments != null) {
            for (comment in elseLeadingComments) {
                handleNode(comment, this);
                comment.each(handleNode);
            }
        }
        if (elseTrailingComments != null) {
            for (comment in elseTrailingComments) {
                handleNode(comment, this);
                comment.each(handleNode);
            }
        }
    }

    /**
     * Converts the if statement to a JSON representation.
     * @return Dynamic object containing if statement data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.condition = condition.toJson();
        json.thenBranch = [for (node in thenBranch.body) node.toJson()];
        if (elseBranch != null) {
            json.elseBranch = [for (node in elseBranch.body) node.toJson()];
            if ((elseLeadingComments != null && elseLeadingComments.length > 0) || (elseTrailingComments != null && elseTrailingComments.length > 0)) {
                final comments:Dynamic = json.comments ?? {};
                if (elseLeadingComments != null && elseLeadingComments.length > 0) {
                    comments.elseLeading = [for (c in elseLeadingComments) c.toJson()];
                }
                if (elseTrailingComments != null && elseTrailingComments.length > 0) {
                    comments.elseTrailing = [for (c in elseTrailingComments) c.toJson()];
                }
                json.comments = comments;
            }
        }
        return json;
    }
}

/**
 * Represents a function call expression in the AST.
 */
class NCall extends NExpression {
    /**
     * The expression being called.
     */
    public var target:NExpression;

    /**
     * Array of argument expressions passed to the call.
     */
    public var args:Array<NExpression>;

    /**
     * Creates a new call expression node.
     * @param pos Position in source where this call appears
     * @param target Expression being called
     * @param args Array of argument expressions
     * @param leadingComments Optional comments before the call
     * @param trailingComments Optional comments after the call
     */
    public function new(id:Int, pos:Position, target:NExpression, args:Array<NExpression>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.args = args;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (target != null) {
            handleNode(target, this);
            target.each(handleNode);
        }

        if (args != null) {
            for (arg in args) {
                handleNode(arg, this);
                arg.each(handleNode);
            }
        }
    }

    /**
     * Converts the call expression to a JSON representation.
     * @return Dynamic object containing call data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.target = target.toJson();
        json.args = [for (arg in args) arg.toJson()];
        return json;
    }
}

/**
 * Represents a transition to another beat (->).
 */
class NTransition extends AstNode {
    /**
     * Name of the target beat.
     */
    public var target:String;

    /**
     * Creates a new transition node.
     * @param pos Position in source where this transition appears
     * @param target Name of the target beat
     * @param leadingComments Optional comments before the transition
     * @param trailingComments Optional comments after the transition
     */
    public function new(id:Int, pos:Position, target:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
    }

    /**
     * Converts the transition to a JSON representation.
     * @return Dynamic object containing transition data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.target = target;
        return json;
    }
}

/**
 * Represents literal values in the AST (numbers, booleans, arrays, objects).
 */
class NLiteral extends NExpression {
    /**
     * The literal value.
     */
    public var value:Any;

    /**
     * Type of the literal value.
     */
    public var type:LiteralType;

    /**
     * Creates a new literal node.
     * @param pos Position in source where this literal appears
     * @param value The literal value
     * @param type Type of the literal
     * @param leadingComments Optional comments before the literal
     * @param trailingComments Optional comments after the literal
     */
    public function new(id:Int, pos:Position, value:Any, type:LiteralType, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.value = value;
        this.type = type;
    }

    /**
     * Converts the literal to a JSON representation.
     * @return Dynamic object containing literal data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.literalType = Std.string(type);
        switch (type) {
            case Array:
                json.value = [for (elem in (value:Array<Dynamic>)) {
                    if (Std.isOfType(elem, Node)) {
                        (elem:Node).toJson();
                    } else {
                        elem;
                    }
                }];
            case Object:
                if (value != null) {
                    json.value = [for (field in (value:Array<NObjectField>)) field.toJson()];
                }
                else {
                    json.value = [];
                }
            case _:
                json.value = value;
        }
        return json;
    }
}

/**
 * Possible types for literal values.
 */
enum LiteralType {
    /** Numeric literal */
    Number;
    /** Boolean literal */
    Boolean;
    /** Null literal */
    Null;
    /** Array literal */
    Array;
    /** Object literal */
    Object;
}

/**
 * Represents a field access expression (obj.field).
 */
class NAccess extends NExpression {
    /**
     * Optional target object being accessed.
     */
    public var target:Null<NExpression>;

    /**
     * Name of the accessed field.
     */
    public var name:String;

    /**
     * Creates a new field access node.
     * @param pos Position in source where this access appears
     * @param target Optional target object expression
     * @param name Name of the accessed field
     * @param leadingComments Optional comments before the access
     * @param trailingComments Optional comments after the access
     */
    public function new(id:Int, pos:Position, target:Null<NExpression>, name:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.name = name;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (target != null) {
            handleNode(target, this);
            target.each(handleNode);
        }
    }

    /**
     * Converts the field access to a JSON representation.
     * @return Dynamic object containing access data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        if (target != null) json.target = target.toJson();
        json.name = name;
        return json;
    }
}

/**
 * Represents an assignment expression (a = b, a += b, etc).
 */
class NAssignment extends NExpression {
    /**
     * Target expression being assigned to.
     */
    public var target:NExpression;

    /**
     * Assignment operator type.
     */
    public var op:TokenType;

    /**
     * Value being assigned.
     */
    public var value:NExpression;

    /**
     * Creates a new assignment node.
     * @param pos Position in source where this assignment appears
     * @param target Target expression being assigned to
     * @param op Assignment operator type
     * @param value Value being assigned
     * @param leadingComments Optional comments before the assignment
     * @param trailingComments Optional comments after the assignment
     */
    public function new(id:Int, pos:Position, target:NExpression, op:TokenType, value:NExpression, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.op = op;
        this.value = value;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (target != null) {
            handleNode(target, this);
            target.each(handleNode);
        }

        if (value != null) {
            handleNode(value, this);
            value.each(handleNode);
        }
    }

    /**
     * Converts the assignment to a JSON representation.
     * @return Dynamic object containing assignment data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.target = target.toJson();
        json.op = Std.string(op);
        json.value = value.toJson();
        return json;
    }
}

/**
 * Represents an array access expression (array[index]).
 */
class NArrayAccess extends NExpression {
    /**
     * Target array being accessed.
     */
    public var target:NExpression;

    /**
     * Index expression.
     */
    public var index:NExpression;

    /**
     * Creates a new array access node.
     * @param pos Position in source where this access appears
     * @param target Target array expression
     * @param index Index expression
     * @param leadingComments Optional comments before the access
     * @param trailingComments Optional comments after the access
     */
    public function new(id:Int, pos:Position, target:NExpression, index:NExpression, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.index = index;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (target != null) {
            handleNode(target, this);
            target.each(handleNode);
        }

        if (index != null) {
            handleNode(index, this);
            index.each(handleNode);
        }
    }

    /**
     * Converts the array access to a JSON representation.
     * @return Dynamic object containing array access data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.target = target.toJson();
        json.index = index.toJson();
        return json;
    }
}

/**
 * Represents a binary operation expression (a + b, a && b, etc).
 */
class NBinary extends NExpression {
    /**
     * Left operand expression.
     */
    public var left:NExpression;

    /**
     * Operator type.
     */
    public var op:TokenType;

    /**
     * Right operand expression.
     */
    public var right:NExpression;

    /**
     * Creates a new binary operation node.
     * @param pos Position in source where this operation appears
     * @param left Left operand expression
     * @param op Binary operator type
     * @param right Right operand expression
     * @param leadingComments Optional comments before the operation
     * @param trailingComments Optional comments after the operation
     */
    public function new(id:Int, pos:Position, left:NExpression, op:TokenType, right:NExpression, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.left = left;
        this.op = op;
        this.right = right;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (left != null) {
            handleNode(left, this);
            left.each(handleNode);
        }

        if (right != null) {
            handleNode(right, this);
            right.each(handleNode);
        }
    }

    /**
     * Converts the binary operation to a JSON representation.
     * @return Dynamic object containing operation data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.left = left.toJson();
        json.op = Std.string(op);
        json.right = right.toJson();
        return json;
    }
}

/**
 * Represents a unary operation expression (!x, -x, etc).
 */
class NUnary extends NExpression {
    /**
     * Operator type.
     */
    public var op:TokenType;

    /**
     * Operand expression.
     */
    public var operand:NExpression;

    /**
     * Creates a new unary operation node.
     * @param pos Position in source where this operation appears
     * @param op Unary operator type
     * @param operand Operand expression
     * @param leadingComments Optional comments before
     * @param trailingComments Optional comments after the operation
     */
    public function new(id:Int, pos:Position, op:TokenType, operand:NExpression, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.op = op;
        this.operand = operand;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (operand != null) {
            handleNode(operand, this);
            operand.each(handleNode);
        }
    }

    /**
     * Converts the unary operation to a JSON representation.
     * @return Dynamic object containing operation data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.op = Std.string(op);
        json.operand = operand.toJson();
        return json;
    }
}

/**
 * Represents an import statement
 */
class NImport extends AstNode {
    /**
     * The path of the file to import
     */
    public var path:String;

    /**
     * Creates a new import statement node.
     * @param pos Position in source where this import appears
     * @param path The path of the file to import
     * @param leadingComments Optional comments before
     * @param trailingComments Optional comments after the operation
     */
    public function new(id:Int, pos:Position, path:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.path = path;
    }

    public override function toJson():Dynamic {
        final json = super.toJson();
        json.path = path;
        return json;
    }
}
