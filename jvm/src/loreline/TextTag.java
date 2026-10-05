package loreline;

/**
 * Represents a tag in text content, which can be used for styling or other purposes.
 */
public class TextTag {
    /** Whether this is a closing tag. */
    public final boolean closing;

    /** The value or name of the tag. */
    public final String value;

    /**
     * Where the tag appears in the text, in characters (Unicode code points)
     * from its start, the same on every target. A Java string counts UTF-16
     * units instead, where a character above U+FFFF, such as most emoji, takes
     * two: {@code text.offsetByCodePoints(0, offset)} gives the index in the string.
     */
    public final int offset;

    public TextTag(boolean closing, String value, int offset) {
        this.closing = closing;
        this.value = value;
        this.offset = offset;
    }
}
