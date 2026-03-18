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
