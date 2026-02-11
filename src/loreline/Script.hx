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
        return json;
    }

    public override function type():String {
        return "Script";
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
