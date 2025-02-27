package loreline;

import loreline.Node;

/**
 * Represents the root node of a Loreline script AST.
 */
class Script extends Node {
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

}
