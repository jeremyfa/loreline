package loreline;

import java.util.List;
import java.util.function.IntConsumer;

/**
 * Handler for choice presentation.
 * Called when the script needs to present choices to the user.
 */
@FunctionalInterface
public interface ChoiceHandler {
    /**
     * Called when choices should be presented.
     *
     * @param interpreter the interpreter instance
     * @param options the available choice options
     * @param select function to call with the index of the selected choice
     */
    void handle(Interpreter interpreter, List<ChoiceOption> options,
                IntConsumer select);
}
