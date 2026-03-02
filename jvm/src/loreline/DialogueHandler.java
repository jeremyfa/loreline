package loreline;

import java.util.List;

/**
 * Handler for dialogue text output.
 * Called when the script needs to display text to the user.
 */
@FunctionalInterface
public interface DialogueHandler {
    /**
     * Called when dialogue text should be displayed.
     *
     * @param interpreter the interpreter instance
     * @param character the character speaking (null for narrator text)
     * @param text the text content to display
     * @param tags any tags in the text
     * @param advance function to call when the text has been displayed
     */
    void handle(Interpreter interpreter, String character, String text,
                List<TextTag> tags, Runnable advance);
}
