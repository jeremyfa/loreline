package loreline;

import loreline.Node;

/**
 * Represents the root node of a Loreline script AST.
 */
#if js
@:expose
#end
class Script extends AstNode {
    /**
     * The detected indentation size of the source (e.g., 2 or 4 spaces).
     */
    public var indentSize:Int = 2;

    /**
     * The file path this script was parsed from.
     * May be null if the script was parsed without a file path.
     */
    public var filePath:String = null;

    /**
     * Array of top-level declarations in the script.
     */
    public var body:Array<AstNode>;

    /**
     * Creates a new script root node.
     * @param id The node id of this script
     * @param pos Position in source where this script starts
     * @param body Array of top-level declarations
     */
    public function new(id:NodeId, pos:Position, body:Array<AstNode>) {
        super(id, pos);
        this.body = body;
    }

    /**
     * Converts the script to a JSON representation.
     * @return Dynamic object containing all script data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.body = [for (decl in body) decl.toJson()];
        json.indentSize = indentSize;
        if (filePath != null) json.filePath = filePath;
        return json;
    }

    /**
     * Reconstructs a Script from its JSON representation.
     * @param json The JSON object (as returned by script.toJson())
     * @return The reconstructed Script
     */
    @:keep public static function fromJson(json:Dynamic):Script {
        return JsonToAst.scriptFromJson(json);
    }

    public override function type():String {
        return "Script";
    }

    /**
     * The metadata block of this file, or null when it has none. The block of
     * a file it imports isn't the story's: only the file played has one.
     */
    public function metadataBlock():Null<NMetadataDecl> {
        if (body != null) {
            for (node in body) {
                if (node is NMetadataDecl) return cast node;
            }
        }
        return null;
    }

    /**
     * The value of a field of the story's metadata block, like its `title`,
     * `author` or `ifid`, or null when the block doesn't give it. Values have
     * the same types as the fields of a state: text, numbers, booleans,
     * lists and objects.
     * @param name The name of the field
     * @return The value of the field, or null
     */
    public function getMetadataField(name:String):Any {
        final metadata = metadataBlock();
        if (metadata == null) return null;
        final value = metadata.get(name);
        return value != null ? constantValue(value) : null;
    }

    /**
     * The value of a constant expression of a metadata block, of the types
     * the runtime gives values on this target. Nothing else can be written
     * there, the parser makes sure of it.
     */
    static function constantValue(expr:NExpr):Any {
        if (expr is NStringLiteral) {
            final text = new StringBuf();
            for (part in (cast expr:NStringLiteral).parts) {
                switch part.partType {
                    case Raw(raw): text.add(raw);
                    case _:
                }
            }
            return text.toString();
        }
        if (expr is NLiteral) {
            final literal:NLiteral = cast expr;
            switch literal.literalType {
                case Array:
                    return Arrays.fromValues([for (element in (literal.value:Array<Dynamic>)) constantValue(element)]);
                case Object(_):
                    final fields:Any = Objects.createFields();
                    for (field in (literal.value:Array<NObjectField>)) {
                        Objects.setField(null, fields, field.name, field.value != null ? constantValue(field.value) : null);
                    }
                    return fields;
                case _:
                    return literal.value;
            }
        }
        return null;
    }

    public function eachExcludingImported(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (body != null) {
            for (child in body) {
                handleNode(child, this);
                if (!(child is NImportStatement)) {
                    child.each(handleNode);
                }
            }
        }
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (body != null) {
            for (child in body) {
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

    public function iterator():ScriptBodyIterator {
        return new ScriptBodyIterator(body);
    }

}

@:allow(loreline.Script)
private class ScriptBodyIterator {
    var body:Array<AstNode>;
    var index:Int;
    var flatBody:Array<AstNode>;

    public function new(body:Array<AstNode>) {
        this.body = body;
        index = 0;
        flatBody = [];
        fillBody(body);
    }

    function fillBody(body) {
        for (i in 0...body.length) {
            final node = body[i];
            if (node is NImportStatement) {
                final importNode:NImportStatement = cast node;
                if (importNode.script != null) {
                    fillBody(importNode.script.body);
                }
            }
            flatBody.push(body[i]);
        }
    }

    public function hasNext():Bool {
        @:privateAccess return index < flatBody.length;
    }

    public function next():AstNode {
        final v = flatBody[index];
        index++;
        return v;
    }
}
