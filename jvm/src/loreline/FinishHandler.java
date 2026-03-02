package loreline;

/**
 * Handler called when script execution finishes.
 */
@FunctionalInterface
public interface FinishHandler {
    /**
     * Called when the script execution completes.
     *
     * @param interpreter the interpreter instance
     */
    void handle(Interpreter interpreter);
}
