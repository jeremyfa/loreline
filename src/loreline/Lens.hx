package loreline;

import loreline.Node;
import loreline.Position;

/**
 * Definition reference found in a script
 */
@:structInit class Definition {
    /** The node where this definition appears */
    public var node:Node;
    /** The exact position of the definition */
    public var pos:Position;
    /** Any references to this definition */
    public var references:Array<Reference> = [];
}

/**
 * Reference to a definition found in a script
 */
@:structInit class Reference {
    /** The node containing this reference */
    public var node:Node;
    /** The exact position of the reference */
    public var pos:Position;
}

/**
 * Utility class for analyzing Loreline scripts without executing them.
 * Provides methods for finding nodes, variables, references, etc.
 */
class Lens {
    /** The script being analyzed */
    final script:Script;

    /** Map of all nodes by their unique ID */
    final nodesById:Map<Int, Node> = [];

    /** Map of node IDs to their parent nodes */
    final parentNodes:Map<Int, Node> = [];

    /** Map of node IDs to their child nodes */
    final childNodes:Map<Int, Array<Node>> = [];

    public function new(script:Script) {
        this.script = script;
        initialize();
    }

    /**
     * Initialize all the lookups and analysis data
     */
    function initialize() {
        // First pass: Build node maps and collect definitions
        script.each((node, parent) -> {
            // Track nodes by ID
            nodesById.set(node.id, node);

            // Track parent relationships
            if (parent != null) {
                parentNodes.set(node.id, parent);

                // And track the other way around
                var children = childNodes.get(parent.id);
                if (children == null) {
                    children = [];
                    childNodes.set(parent.id, children);
                }
                children.push(node);
            }
        });
    }

    /**
     * Gets the nodes at the given position
     * @param pos Position to check
     * @return Most specific node at that position, or null if none found
     */
    public function getNodeAtPosition(pos:Position):Null<Node> {
        var bestMatch:Null<Node> = null;

        script.each((node, parent) -> {
            final nodePos = node.pos;
            if (nodePos.length > 0 &&
                nodePos.offset <= pos.offset &&
                nodePos.offset + nodePos.length >= pos.offset) {

                bestMatch = node;
            }
        });

        return bestMatch;
    }

    /**
     * Gets all nodes of a specific type
     * @param nodeType Class type to find
     * @return Array of matching nodes
     */
    public function getNodesOfType<T:Node>(nodeType:Class<T>):Array<T> {
        final matches:Array<T> = [];
        script.each((node, _) -> {
            if (Std.isOfType(node, nodeType)) {
                matches.push(cast node);
            }
        });
        return matches;
    }

    /**
     * Gets the parent node of a given node
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getParentNode(node:Node):Null<Node> {
        return parentNodes.get(node.id);
    }

    /**
     * Gets the parent node of a given node
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getParentOfType<T:Node>(node:Node, type:Class<T>):Null<T> {
        var current:Any = node;
        while (current != null) {
            current = getParentNode(current);
            if (current != null && Type.getClass(current) == type) {
                return current;
            }
        }
        return null;
    }

    /**
     * Gets all ancestor nodes of a given node
     * @param node Starting node
     * @return Array of ancestor nodes from immediate parent to root
     */
    public function getAncestors(node:Node):Array<Node> {
        final ancestors:Array<Node> = [];
        var current = node;
        while (current != null) {
            current = parentNodes.get(current.id);
            if (current != null) {
                ancestors.push(current);
            }
        }
        return ancestors;
    }

    /**
     * Finds all nodes that match a predicate function
     * @param predicate Function that returns true for matching nodes
     * @return Array of matching nodes
     */
    public function findNodes(predicate:(node:Node) -> Bool):Array<Node> {
        final matches:Array<Node> = [];
        script.each((node, _) -> {
            if (predicate(node)) {
                matches.push(node);
            }
        });
        return matches;
    }

    /**
     * Finds and returns the beat declaration referenced by the given transition.
     * This method searches through the beat declarations to find a match based on the transition's properties.
     * @param transition The transition object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findReferencedBeat(transition:NTransition):Null<NBeatDecl> {

        var result:Null<NBeatDecl> = null;

        var parent = parentNodes.get(transition.id);
        while (result == null && parent != null) {
            parent.each((node, _) -> {
                if (Type.getClass(node) == NBeatDecl) {
                    final beatDecl:NBeatDecl = cast node;
                    if (beatDecl.name == transition.target) {
                        result = beatDecl;
                    }
                }
            });
            parent = parentNodes.get(parent.id);
        }

        return result;

    }

}