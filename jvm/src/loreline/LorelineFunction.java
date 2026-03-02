package loreline;

/**
 * A custom function that can be called from within a Loreline script.
 */
@FunctionalInterface
public interface LorelineFunction {
    /**
     * Called when the function is invoked from the script.
     *
     * @param interpreter the interpreter instance
     * @param args the arguments passed to the function
     * @return the result of the function
     */
    Object call(Interpreter interpreter, Object[] args);
}
