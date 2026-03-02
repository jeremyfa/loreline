package loreline;

import java.util.Map;

/**
 * Options for configuring a Loreline interpreter.
 */
public class InterpreterOptions {
    /** Optional map of custom functions to make available in the script. */
    public Map<String, LorelineFunction> functions;

    /** Whether to enable strict variable access (throw on undefined variables). */
    public boolean strictAccess;

    /** Optional translations map for localization. */
    public Object translations;

    /** A custom instantiator to create fields objects. */
    public CreateFieldsHandler customCreateFields;

    public InterpreterOptions() {
    }

    /**
     * Handler for creating custom fields objects.
     */
    @FunctionalInterface
    public interface CreateFieldsHandler {
        Object create(Interpreter interpreter, String type);
    }
}
