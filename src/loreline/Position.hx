package loreline;

/**
 * Represents a position within source code, tracking line number, column, and offset information.
 * Used throughout the compiler to pinpoint locations of tokens, nodes, and error messages.
 */
class Position {

    /**
     * The line number in the source code, starting from 1.
     */
    public var line:Int;

    /**
     * The column number in the source code, starting from 1.
     * Represents the character position within the current line.
     */
    public var column:Int;

    /**
     * The absolute character offset from the start of the source code.
     * Used for precise positioning and span calculations.
     */
    public var offset:Int;

    /**
     * The length of the source text span this position represents.
     * A value of 0 indicates a point position rather than a span.
     */
    public var length:Int;

    /**
     * Creates a new position instance with the specified coordinates.
     * @param line Line number in the source (1-based)
     * @param column Column number in the source (1-based)
     * @param offset Character offset from start of source
     * @param length Optional length of the source span (default: 0)
     */
    public function new(line:Int, column:Int, offset:Int, length:Int = 0) {
        this.line = line;
        this.column = column;
        this.offset = offset;
        this.length = length;
    }

    /**
     * Converts the position to a human-readable string representation.
     * Useful for error messages and debugging.
     * @return String in format "(line X col Y)"
     */
    public function toString():String {
        return '(line $line col $column)';
    }

    /**
     * Converts the position to a JSON-compatible object structure.
     * Only includes the length field if it's non-zero.
     * @return Dynamic object containing position data
     */
    public function toJson():Dynamic {
        final json = {
            line: line,
            column: column,
            offset: offset
        };
        if (length != 0) {
            Reflect.setField(json, "length", length);
        }
        return json;
    }

}