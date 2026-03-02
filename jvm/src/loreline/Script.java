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
}
