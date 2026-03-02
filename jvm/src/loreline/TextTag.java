package loreline;

/**
 * Represents a tag in text content, which can be used for styling or other purposes.
 */
public class TextTag {
    /** Whether this is a closing tag. */
    public final boolean closing;

    /** The value or name of the tag. */
    public final String value;

    /** The offset in the text where this tag appears. */
    public final int offset;

    public TextTag(boolean closing, String value, int offset) {
        this.closing = closing;
        this.value = value;
        this.offset = offset;
    }
}
