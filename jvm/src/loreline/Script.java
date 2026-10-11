package loreline;

/**
 * Represents the root node of a parsed Loreline script AST.
 * This is the result of calling {@link Loreline#parse(String)} or similar parse methods.
 */
public class Script extends Node {
    final loreline.runtime.Script runtimeScript;

    Script(loreline.runtime.Script runtimeScript) {
        super(runtimeScript);
        this.runtimeScript = runtimeScript;
    }

    /**
     * Gets a field of the story's metadata block, like its title, author or
     * IFID. Values have the same types as state fields.
     *
     * @param name the name of the field
     * @return the field value or null if the block doesn't give it
     */
    public Object getMetadataField(String name) {
        return runtimeScript.getMetadataField(name);
    }

    /**
     * Reconstructs a Script from a JSON string.
     *
     * @param json a JSON string (as returned by {@link #toJson()})
     * @return the reconstructed Script
     */
    public static Script fromJson(String json) {
        Object parsed = loreline.runtime.Json.parse(json);
        loreline.runtime.Script runtimeScript = loreline.runtime.Script.fromJson(parsed);
        return new Script(runtimeScript);
    }
}
