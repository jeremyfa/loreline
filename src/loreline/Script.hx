package loreline;

import loreline.Node;

/**
 * Represents the root node of a Loreline script AST.
 */
class Script extends Node {
    /**
     * Array of top-level declarations in the script.
     */
    public var declarations:Array<AstNode>;

    /**
     * Creates a new script root node.
     * @param pos Position in source where this script starts
     * @param declarations Array of top-level declarations
     */
    public function new(id:Int, pos:Position, declarations:Array<AstNode>) {
        super(id, pos);
        this.declarations = declarations;
    }

    /**
     * Converts the script to a JSON representation.
     * @return Dynamic object containing all script data
     */
    public override function toJson():Dynamic {
        final json = super.toJson();
        json.declarations = [for (decl in declarations) decl.toJson()];
        return json;
    }

    public override function each(handleNode:(node:Node, parent:Node)->Void):Void {
        super.each(handleNode);

        if (declarations != null) {
            for (i in 0...declarations.length) {
                final child = declarations[i];
                handleNode(child, this);
                child.each(handleNode);
            }
        }
    }

}
