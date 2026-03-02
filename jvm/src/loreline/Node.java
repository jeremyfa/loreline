package loreline;

/**
 * Base class for all Loreline AST nodes.
 * Provides access to the node type, unique ID, and JSON export.
 */
public class Node {

    /**
     * The underlying runtime node instance.
     */
    public final loreline.runtime.Node runtimeNode;

    /**
     * The type of the node as a string (e.g. "Script", "Beat", "Text", "Dialogue").
     */
    public final String type;

    /**
     * The unique ID of this node within a single script hierarchy, as a raw Int64 value.
     * Use {@link #nodeIdToString()} for a human-readable representation.
     */
    public final long id;

    Node(loreline.runtime.Node runtimeNode) {
        this.runtimeNode = runtimeNode;
        this.type = runtimeNode.type();
        this.id = runtimeNode.id.thisVal;
    }

    /**
     * Returns the human-readable node ID string (e.g. "1.0.0.0").
     *
     * @return the node ID as a dotted string
     */
    public String nodeIdToString() {
        return runtimeNode.id.toString();
    }

    /**
     * Converts the node to a JSON string representation.
     * This can be used for debugging or serialization purposes.
     *
     * @param pretty whether to format the JSON with indentation and line breaks
     * @return a JSON string representation of the node
     */
    public String toJson(boolean pretty) {
        return loreline.runtime.Json.stringify(runtimeNode.toJson(), pretty);
    }

    /**
     * Converts the node to a compact JSON string representation.
     *
     * @return a JSON string representation of the node
     */
    public String toJson() {
        return toJson(false);
    }
}
