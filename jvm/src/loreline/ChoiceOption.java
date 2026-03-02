package loreline;

import java.util.List;

/**
 * Represents a choice option presented to the user.
 */
public class ChoiceOption {
    /** The text of the choice option. */
    public final String text;

    /** Any tags associated with the choice text. */
    public final List<TextTag> tags;

    /** Whether this choice option is currently enabled. */
    public final boolean enabled;

    public ChoiceOption(String text, List<TextTag> tags, boolean enabled) {
        this.text = text;
        this.tags = tags;
        this.enabled = enabled;
    }
}
