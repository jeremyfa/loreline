package loreline;

import haxe.Int64;
import haxe.ds.StringMap;
import loreline.Lexer;

enum abstract NodeIdStep(Int) {

    var SECTION = 1;

    var BRANCH = 2;

    var BLOCK = 3;

    var NODE = 4;

}

abstract NodeId(Int64) {

    static inline final OFFSET:Int = 32768;

    static inline final MAX:Int = 65535;

    public static final UNDEFINED:NodeId = new NodeId(0, 0, 0, 0);

    public function new(section:Int, branch:Int, block:Int, node:Int) {
        if (section < 0 || section > MAX) {
            throw 'Section value ($section) should be between 0 and $MAX';
        }
        if (branch < 0 || branch > MAX) {
            throw 'Branch value ($branch) should be between 0 and $MAX';
        }
        if (block < 0 || block > MAX) {
            throw 'Block value ($block) should be between 0 and $MAX';
        }
        if (node < 0 || node > MAX) {
            throw 'Node value ($node) should be between 0 and $MAX';
        }
        this = Int64.make(
            packInt32(section - OFFSET, branch - OFFSET), packInt32(block - OFFSET, node - OFFSET)
        );
    }

    public static function fromInt64(value:Int64):NodeId {
        return cast value;
    }

    public static function fromString(str:String):NodeId {
        final parts = str.split('.');
        return new NodeId(
            Std.parseInt(parts[0]),
            Std.parseInt(parts[1]),
            Std.parseInt(parts[2]),
            Std.parseInt(parts[3])
        );
    }

    public static function fromTwoInt32(high:Int, low:Int):NodeId {
        return fromInt64(Int64.make(high, low));
    }

    inline static function packInt32(high:Int, low:Int):Int {
        if (high < 0) high = (high + 65536) & 0xFFFF;
        if (low < 0) low = (low + 65536) & 0xFFFF;
        return (high << 16) | (low & 0xFFFF);
    }

    inline static function int32GetLow(value:Int):Int {
        var low = value & 0xFFFF;
        return low >= 32768 ? low - 65536 : low;
    }

    inline static function int32SetLow(target:Int, value:Int):Int {
        if (value < 0) value = (value + 65536) & 0xFFFF;
        return (target & 0xFFFF0000) | value;
    }

    inline static function int32GetHigh(value:Int):Int {
        var high = (value >> 16) & 0xFFFF;
        return high >= 32768 ? high - 65536 : high;
    }

    inline static function int32SetHigh(target:Int, value:Int):Int {
        if (value < 0) value = (value + 65536) & 0xFFFF;
        return (target & 0xFFFF) | (value << 16);
    }

    public var section(get,set):Int;
    inline function get_section():Int {
        return int32GetHigh(this.high) + OFFSET;
    }
    inline function set_section(section:Int):Int {
        this = Int64.make(int32SetHigh(this.high, section - OFFSET), this.low);
        return section;
    }

    public var branch(get,set):Int;
    inline function get_branch():Int {
        return int32GetLow(this.high) + OFFSET;
    }
    inline function set_branch(branch:Int):Int {
        this = Int64.make(int32SetLow(this.high, branch - OFFSET), this.low);
        return branch;
    }

    public var block(get,set):Int;
    inline function get_block():Int {
        return int32GetHigh(this.low) + OFFSET;
    }
    inline function set_block(block:Int):Int {
        this = Int64.make(this.high, int32SetHigh(this.low, block - OFFSET));
        return block;
    }

    public var node(get,set):Int;
    inline function get_node():Int {
        return int32GetLow(this.low) + OFFSET;
    }
    inline function set_node(node:Int):Int {
        this = Int64.make(this.high, int32SetLow(this.low, node - OFFSET));
        return node;
    }

    public function nextSection():NodeId {
        final section = abstract.section;
        if (section == MAX) {
            throw 'Node id section overflow';
        }
        return new NodeId(
            section + 1, 0, 0, 0
        );
    }

    public function nextBranch():NodeId {
        final branch = abstract.branch;
        if (branch == MAX) {
            return nextSection();
        }
        return new NodeId(
            section, branch + 1, 0, 0
        );
    }

    public function nextBlock():NodeId {
        final block = abstract.block;
        if (block == MAX) {
            return nextBranch();
        }
        return new NodeId(
            section, branch, block + 1, 0
        );
    }

    public function nextNode():NodeId {
        final node = abstract.node;
        if (node == MAX) {
            return nextBlock();
        }
        return new NodeId(
            section, branch, block, node + 1
        );
    }

    inline public function toInt64():Int64 {
        return this;
    }

    public function toString():String {
        return '${get_section()}.${get_branch()}.${get_block()}.${get_node()}';
    }

    @:op(A == B) static function equals(a:NodeId, b:NodeId):Bool {
        return a.toInt64() == b.toInt64();
    }

}

@:allow(loreline.NodeIdMapIterator)
class NodeIdMap<V> {

    final map:Int64Map<V>;

    inline public function new() {
        map = new Int64Map<V>();
    }

    inline public function get(key:NodeId):Null<V> {
        return map.get(key.toInt64());
    }

    inline public function set(key:NodeId, value:V):Void {
        map.set(key.toInt64(), value);
    }

    inline public function remove(key:NodeId):Void {
        map.remove(key.toInt64());
    }

    inline public function exists(key:NodeId):Bool {
        return map.exists(key.toInt64());
    }

    inline public function clear() {
        map.clear();
    }

    public inline function iterator():NodeIdMapIterator<V> {
        return new NodeIdMapIterator<V>(map);
    }

    public inline function keys():NodeIdMapKeyIterator<V> {
        return new NodeIdMapKeyIterator(map);
    }

    public inline function keyValueIterator():NodeIdMapKeyValueIterator<V> {
        return new NodeIdMapKeyValueIterator(map);
    }

}

typedef NodeIdMapKeyVal<V> = {
    key:NodeId,
    value:V
}

private class NodeIdMapIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        @:privateAccess while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        @:privateAccess return index < map._values.length;
    }

    public inline function next():V {
        var v = @:privateAccess map._values[index];
        index++;
        skipNulls();
        return v;
    }
}

private class NodeIdMapKeyIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        @:privateAccess while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        @:privateAccess return index < map._values.length;
    }

    public inline function next():NodeId {
        @:privateAccess var k1 = map._keys1[index];
        @:privateAccess var k2 = map._keys2[index];
        index++;
        skipNulls();
        return NodeId.fromTwoInt32(k1, k2);
    }
}

private class NodeIdMapKeyValueIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        @:privateAccess while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        @:privateAccess return index < map._values.length;
    }

    public inline function next():NodeIdMapKeyVal<V> {
        @:privateAccess var k1 = map._keys1[index];
        @:privateAccess var k2 = map._keys2[index];
        @:privateAccess var v = map._values[index];
        index++;
        skipNulls();
        return {
            key: NodeId.fromTwoInt32(k1, k2),
            value: v
        };
    }
}

/**
 * Base class for all AST nodes. Contains position information and basic JSON conversion.
 */
class Node {

    /**
     * A unique identifier for this node within the AST, used to distinguish
     * it from other nodes in the script.
     */
    public var id:NodeId = NodeId.UNDEFINED;

    /**
     * Source code position where this node appears.
     */
    public var pos:Position;

    /**
     * Creates a new AST node.
     * @param pos Position in source where this node appears
     */
    public function new(id:NodeId, pos:Position) {
        this.id = id;
        this.pos = pos;
    }

    public function type():String {
        return "node";
    }

    /**
     * Converts the node to a JSON representation.
     * @return Dynamic object containing node type and position
     */
    public function toJson():Dynamic {
        return {
            id: id.toString(),
            type: type(),
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
    public function new(id:NodeId, pos:Position, content:String, multiline:Bool) {
        super(id, pos);
        this.content = content;
        this.multiline = multiline;
    }

    override function type():String {
        return "Comment";
    }

    /**
     * Converts the comment node to a JSON representation.
     * @return Dynamic object containing comment data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
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
    public function new(id:NodeId, pos:Position, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos);
        this.leadingComments = leadingComments;
        this.trailingComments = trailingComments;
    }

    override function type():String {
        return "AstNode";
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
        final json:Dynamic = super.toJson();

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
class NExpr extends AstNode {

    /**
     * Converts the expression node to a JSON representation.
     * @return Dynamic object containing expression data
     */
    public override function toJson():Dynamic {
        return super.toJson();
    }

    override function type():String {
        return "Expr";
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
     * Fields defined for this state.
     */
    public var fields:Array<NObjectField>;

    /**
     * Block style of this state
     */
    public var style:BlockStyle;

    /**
     * Creates a new state declaration node.
     * @param pos Position in source where this state appears
     * @param temporary Whether this is a temporary state
     * @param fields Array of property definitions
     * @param leadingComments Optional comments before the state
     * @param trailingComments Optional comments after the state
     */
    public function new(id:NodeId, pos:Position, temporary:Bool, fields:Array<NObjectField>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.temporary = temporary;
        this.fields = fields;
        this.style = Plain;
    }

    override function type():String {
        return "State";
    }

    public function get(name:String):NExpr {

        for (field in fields) {
            if (field.name == name) {
                return field.value;
            }
        }

        return null;

    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (fields != null) {
            for (i in 0...fields.length) {
                final child = fields[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    /**
     * Converts the state declaration to a JSON representation.
     * @return Dynamic object containing state data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        json.temporary = temporary;
        json.fields = [for (prop in fields) prop.toJson()];
        json.style = style.toString();
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
    public var value:NExpr;

    /**
     * Creates a new object field node.
     * @param pos Position in source where this field appears
     * @param name Name of the field
     * @param value Value expression for the field
     * @param leadingComments Optional comments before the field
     * @param trailingComments Optional comments after the field
     */
    public function new(id:NodeId, pos:Position, name:String, value:NExpr, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.value = value;
    }

    override function type():String {
        return "Field";
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
        final json:Dynamic = super.toJson();
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
     * Position of the name part.
     */
    public var namePos:Position;

    /**
     * Fields defined for this character.
     */
    public var fields:Array<NObjectField>;

    /**
     * Block style of this character
     */
    public var style:BlockStyle;

    /**
     * Creates a new character declaration node.
     * @param pos Position in source where this character appears
     * @param name Name of the character
     * @param fields Array of property definitions
     * @param leadingComments Optional comments before the character
     * @param trailingComments Optional comments after the character
     */
    public function new(id:NodeId, pos:Position, name:String, namePos:Position, fields:Array<NObjectField>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.namePos = namePos;
        this.fields = fields;
        this.style = Plain;
    }

    override function type():String {
        return "Character";
    }

    public function get(name:String):NExpr {

        for (field in fields) {
            if (field.name == name) {
                return field.value;
            }
        }

        return null;

    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (fields != null) {
            for (i in 0...fields.length) {
                final child = fields[i];
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
        final json:Dynamic = super.toJson();
        json.name = name;
        json.namePos = namePos.toJson();
        json.fields = [for (prop in fields) prop.toJson()];
        json.style = style.toString();
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
     * Block style of this beat
     */
    public var style:BlockStyle;

    /**
     * Creates a new beat declaration node.
     * @param pos Position in source where this beat appears
     * @param name Name of the beat
     * @param body Array of nodes comprising the beat's content
     * @param leadingComments Optional comments before the beat
     * @param trailingComments Optional comments after the beat
     */
    public function new(id:NodeId, pos:Position, name:String, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.body = body;
        this.style = Plain;
    }

    override function type():String {
        return "Beat";
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
        final json:Dynamic = super.toJson();
        json.name = name;
        json.body = [for (node in body) node.toJson()];
        json.style = style.toString();
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
    Expr(expr:NExpr);

    /**
     * Text formatting tag (<tag> or </tag>).
     */
    Tag(closing:Bool, expr:NStringLiteral);

}

enum abstract BlockStyle(Int) {

    var Plain = 0;

    var Braces = 1;

    public function toString() {
        return switch abstract {
            case Plain: "Plain";
            case Braces: "Braces";
        }
    }

}

/**
 * Represents a string part that can appear in string literals.
 */
class NStringPart extends NExpr {

    /**
     * The type of string part
     */
    public var partType:StringPartType;

    /**
     * Creates a new string part node.
     * @param pos Position in source where this string part appears
     * @param type The type of string part (raw text, interpolations, and tags)
     * @param leadingComments Optional comments before the string
     * @param trailingComments Optional comments after the string
     */
    public function new(id:NodeId, pos:Position, partType:StringPartType, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.partType = partType;
    }

    override function type():String {
        return "Part";
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        switch partType {
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
        final json:Dynamic = super.toJson();
        switch partType {
            case Raw(text):
                json.part = "Raw";
                json.text = text;
            case Expr(expr):
                json.part = "Expr";
                json.expression = expr.toJson();
            case Tag(closing, expr):
                json.part = "Tag";
                json.closing = closing;
                json.content = expr.toJson();
        }
        return json;
    }

}

/**
 * Represents a string literal in the AST, supporting interpolation and tags.
 */
class NStringLiteral extends NExpr {
    /**
     * Array of parts that make up this string literal.
     */
    public var parts:Array<NStringPart>;

    /**
     * The type of quotes used for this string literal
     */
    public var quotes:Quotes;

    /**
     * Creates a new string literal node.
     * @param pos Position in source where this string appears
     * @param parts Array of string parts (raw text, interpolations, and tags)
     * @param leadingComments Optional comments before the string
     * @param trailingComments Optional comments after the string
     */
    public function new(id:NodeId, pos:Position, quotes:Quotes, parts:Array<NStringPart>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.parts = parts;
        this.quotes = quotes;
    }

    override function type():String {
        return "String";
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
        final json:Dynamic = super.toJson();
        final parts:Array<Any> = [
            for (part in parts) part.toJson()
        ];
        json.parts = parts;
        json.quotes = quotes.toString();
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
    public function new(id:NodeId, pos:Position, content:NStringLiteral, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.content = content;
    }

    override function type():String {
        return "Text";
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
        final json:Dynamic = super.toJson();
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
     * Position of the character label
     */
    public var characterPos:Position;

    /**
     * Content of the dialogue.
     */
    public var content:NStringLiteral;

    /**
     * Creates a new dialogue statement node.
     * @param pos Position in source where this dialogue appears
     * @param character Name of the speaking character
     * @param characterPos  Position of the character label
     * @param content String literal containing the dialogue text
     * @param leadingComments Optional comments before the dialogue
     * @param trailingComments Optional comments after the dialogue
     */
    public function new(id:NodeId, pos:Position, character:String, characterPos:Position, content:NStringLiteral, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.character = character;
        this.characterPos = characterPos;
        this.content = content;
    }

    override function type():String {
        return "Dialogue";
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
        final json:Dynamic = super.toJson();
        json.character = character;
        json.characterPos = characterPos.toJson();
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
     * The block style of the choice statement
     */
    public var style:BlockStyle;

    /**
     * Creates a new choice statement node.
     * @param pos Position in source where this choice appears
     * @param options Array of available choice options
     * @param leadingComments Optional comments before the choice
     * @param trailingComments Optional comments after the choice
     */
    public function new(id:NodeId, pos:Position, options:Array<NChoiceOption>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.options = options;
        this.style = Plain;
    }

    override function type():String {
        return "Choice";
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
        final json:Dynamic = super.toJson();
        json.options = [for (option in options) option.toJson()];
        json.style = style.toString();
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
    public var condition:Null<NExpr>;

    /**
     * Array of nodes to execute when this option is chosen.
     */
    public var body:Array<AstNode>;

    /**
     * The block style of the body
     */
    public var style:BlockStyle;

    /**
     * Creates a new choice option node.
     * @param pos Position in source where this option appears
     * @param text String literal containing the option text
     * @param condition Optional condition for option availability
     * @param body Array of nodes to execute when chosen
     * @param leadingComments Optional comments before the option
     * @param trailingComments Optional comments after the option
     */
    public function new(id:NodeId, pos:Position, text:NStringLiteral, condition:Null<NExpr>, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.text = text;
        this.condition = condition;
        this.body = body;
        this.style = Plain;
    }

    override function type():String {
        return "Option";
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
        if (text != null) {
            handleNode(text, this);
            text.each(handleNode);
        }
        if (condition != null) {
            handleNode(condition, this);
            condition.each(handleNode);
        }
    }

    /**
     * Converts the choice option to a JSON representation.
     * @return Dynamic object containing option data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        json.text = text.toJson();
        if (condition != null) json.condition = condition.toJson();
        json.body = [for (node in body) node.toJson()];
        json.style = style.toString();
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
     * The block style of the body.
     */
    public var style:BlockStyle;

    /**
     * Creates a new block node.
     * @param pos Position in source where this beat appears
     * @param body Array of nodes comprising the block's content
     * @param leadingComments Optional comments before the beat
     * @param trailingComments Optional comments after the beat
     */
    public function new(id:NodeId, pos:Position, body:Array<AstNode>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.body = body;
        this.style = Plain;
    }

    override function type():String {
        return "Block";
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
        final json:Dynamic = super.toJson();
        json.body = [for (node in body) node.toJson()];
        json.style = style.toString();
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
    public var condition:NExpr;

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
    public function new(id:NodeId, pos:Position, condition:NExpr, thenBranch:NBlock, elseBranch:Null<NBlock>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>, ?elseLeadingComments:Array<Comment>, ?elseTrailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.condition = condition;
        this.thenBranch = thenBranch;
        this.elseBranch = elseBranch;
        this.elseLeadingComments = elseLeadingComments;
        this.elseTrailingComments = elseTrailingComments;
    }

    override function type():String {
        return "If";
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
        final json:Dynamic = super.toJson();
        json.condition = condition.toJson();
        json.thenBranch = [for (node in thenBranch.body) node.toJson()];
        json.thenStyle = thenBranch.style.toString();
        if (elseBranch != null) {
            json.elseBranch = [for (node in elseBranch.body) node.toJson()];
            json.elseStyle = elseBranch.style.toString();
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
class NCall extends NExpr {
    /**
     * The expression being called.
     */
    public var target:NExpr;

    /**
     * Array of argument expressions passed to the call.
     */
    public var args:Array<NExpr>;

    /**
     * Creates a new call expression node.
     * @param pos Position in source where this call appears
     * @param target Expression being called
     * @param args Array of argument expressions
     * @param leadingComments Optional comments before the call
     * @param trailingComments Optional comments after the call
     */
    public function new(id:NodeId, pos:Position, target:NExpr, args:Array<NExpr>, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.args = args;
    }

    override function type():String {
        return "Call";
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
        final json:Dynamic = super.toJson();
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
     * Position of the target part of the transition
     */
    public var targetPos:Position;

    /**
     * Creates a new transition node.
     * @param pos Position in source where this transition appears
     * @param target Name of the target beat
     * @param targetPos Position of the target part of the transition
     * @param leadingComments Optional comments before the transition
     * @param trailingComments Optional comments after the transition
     */
    public function new(id:NodeId, pos:Position, target:String, targetPos:Position, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.targetPos = targetPos;
    }

    override function type():String {
        return "Transition";
    }

    /**
     * Converts the transition to a JSON representation.
     * @return Dynamic object containing transition data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        json.target = target;
        json.targetPos = targetPos.toJson();
        return json;
    }
}

/**
 * Represents a callable function in the AST
 */
class NFunctionDecl extends NExpr {
    /**
     * The function name (if any)
     */
    public var name:Null<String>;

    /**
     * Argument names
     */
    public var args:Array<String>;

    /**
     * The actual code of the function (including the signature)
     */
    public var code:String;


    /**
     * Creates a new function node.
     * @param pos Position in source where this function appears
     * @param name The function name (if any)
     * @param args Argument names
     * @param code The actual code of the function (including the signature)
     * @param leadingComments Optional comments before the function
     * @param trailingComments Optional comments after the function
     */
     public function new(id:NodeId, pos:Position, name:Null<String>, args:Array<String>, code:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.name = name;
        this.args = args;
        this.code = code;
    }

    override function type():String {
        return "Function";
    }

    /**
     * Converts the literal to a JSON representation.
     * @return Dynamic object containing literal data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        if (name != null) {
            json.name = name;
        }
        json.args = [].concat(args);
        json.code = code;
        return json;
    }
}

/**
 * Represents literal values in the AST (numbers, booleans, arrays, objects).
 */
class NLiteral extends NExpr {
    /**
     * The literal value.
     */
    public var value:Any;

    /**
     * Type of the literal value.
     */
    public var literalType:LiteralType;

    /**
     * Creates a new literal node.
     * @param pos Position in source where this literal appears
     * @param value The literal value
     * @param type Type of the literal
     * @param leadingComments Optional comments before the literal
     * @param trailingComments Optional comments after the literal
     */
    public function new(id:NodeId, pos:Position, value:Any, literalType:LiteralType, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.value = value;
        this.literalType = literalType;
    }

    override function type():String {
        return "Literal";
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        switch literalType {
            case Array:
                if (value != null) {
                    for (elem in (value:Array<Dynamic>)) {
                        if (Std.isOfType(elem, Node)) {
                            final node:Node = cast elem;
                            handleNode(node, this);
                            node.each(handleNode);
                        }
                    }
                }
            case Object(style):
                if (value != null) {
                    for (field in (value:Array<NObjectField>)) {
                        if (Std.isOfType(field.value, Node)) {
                            final node:Node = cast field.value;
                            handleNode(node, this);
                            node.each(handleNode);
                        }
                    }
                }
            case Boolean | Null | Number:
        }
    }

    /**
     * Converts the literal to a JSON representation.
     * @return Dynamic object containing literal data
     */
    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        json.literal = literalType.getName();
        switch literalType {
            case Array:
                if (value != null) {
                    json.value = [for (elem in (value:Array<Dynamic>)) {
                        if (Std.isOfType(elem, Node)) {
                            (elem:Node).toJson();
                        }
                        else {
                            elem;
                        }
                    }];
                }
            case Object(style):
                if (value != null) {
                    json.value = [for (field in (value:Array<NObjectField>)) field.toJson()];
                }
                else {
                    json.value = [];
                }
                json.style = style.toString();
            case Boolean | Null | Number:
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
    Object(style:BlockStyle);
}

/**
 * Represents a field access expression (obj.field).
 */
class NAccess extends NExpr {
    /**
     * Optional target object being accessed.
     */
    public var target:Null<NExpr>;

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
    public function new(id:NodeId, pos:Position, target:Null<NExpr>, name:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.name = name;
    }

    override function type():String {
        return "Access";
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
        final json:Dynamic = super.toJson();
        if (target != null) json.target = target.toJson();
        json.name = name;
        return json;
    }
}

/**
 * Represents an assignment expression (a = b, a += b, etc).
 */
class NAssign extends NExpr {
    /**
     * Target expression being assigned to.
     */
    public var target:NExpr;

    /**
     * Assignment operator type.
     */
    public var op:TokenType;

    /**
     * Value being assigned.
     */
    public var value:NExpr;

    /**
     * Creates a new assignment node.
     * @param pos Position in source where this assignment appears
     * @param target Target expression being assigned to
     * @param op Assignment operator type
     * @param value Value being assigned
     * @param leadingComments Optional comments before the assignment
     * @param trailingComments Optional comments after the assignment
     */
    public function new(id:NodeId, pos:Position, target:NExpr, op:TokenType, value:NExpr, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.op = op;
        this.value = value;
    }

    override function type():String {
        return "Assign";
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
        final json:Dynamic = super.toJson();
        json.target = target.toJson();
        json.op = Std.string(op);
        json.value = value.toJson();
        return json;
    }
}

/**
 * Represents an array access expression (array[index]).
 */
class NArrayAccess extends NExpr {
    /**
     * Target array being accessed.
     */
    public var target:NExpr;

    /**
     * Index expression.
     */
    public var index:NExpr;

    /**
     * Creates a new array access node.
     * @param pos Position in source where this access appears
     * @param target Target array expression
     * @param index Index expression
     * @param leadingComments Optional comments before the access
     * @param trailingComments Optional comments after the access
     */
    public function new(id:NodeId, pos:Position, target:NExpr, index:NExpr, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.target = target;
        this.index = index;
    }

    override function type():String {
        return "ArrayAccess";
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
        final json:Dynamic = super.toJson();
        json.target = target.toJson();
        json.index = index.toJson();
        return json;
    }
}

/**
 * Represents a binary operation expression (a + b, a && b, etc).
 */
class NBinary extends NExpr {
    /**
     * Left operand expression.
     */
    public var left:NExpr;

    /**
     * Operator type.
     */
    public var op:TokenType;

    /**
     * Right operand expression.
     */
    public var right:NExpr;

    /**
     * Creates a new binary operation node.
     * @param pos Position in source where this operation appears
     * @param left Left operand expression
     * @param op Binary operator type
     * @param right Right operand expression
     * @param leadingComments Optional comments before the operation
     * @param trailingComments Optional comments after the operation
     */
    public function new(id:NodeId, pos:Position, left:NExpr, op:TokenType, right:NExpr, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.left = left;
        this.op = op;
        this.right = right;
    }

    override function type():String {
        return "Binary";
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
        final json:Dynamic = super.toJson();
        json.left = left.toJson();
        json.op = Std.string(op);
        json.right = right.toJson();
        return json;
    }
}

/**
 * Represents a unary operation expression (!x, -x, etc).
 */
class NUnary extends NExpr {
    /**
     * Operator type.
     */
    public var op:TokenType;

    /**
     * Operand expression.
     */
    public var operand:NExpr;

    /**
     * Creates a new unary operation node.
     * @param pos Position in source where this operation appears
     * @param op Unary operator type
     * @param operand Operand expression
     * @param leadingComments Optional comments before
     * @param trailingComments Optional comments after the operation
     */
    public function new(id:NodeId, pos:Position, op:TokenType, operand:NExpr, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.op = op;
        this.operand = operand;
    }

    override function type():String {
        return "Unary";
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
        final json:Dynamic = super.toJson();
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
    public function new(id:NodeId, pos:Position, path:String, ?leadingComments:Array<Comment>, ?trailingComments:Array<Comment>) {
        super(id, pos, leadingComments, trailingComments);
        this.path = path;
    }

    override function type():String {
        return "Import";
    }

    public override function toJson():Dynamic {
        final json:Dynamic = super.toJson();
        json.path = path;
        return json;
    }
}
