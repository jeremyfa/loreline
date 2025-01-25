package loreline;

using loreline.Utf8;

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
        return '($line:$column:$offset:$length)';
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

    /**
     * Creates a new position that is offset from this position.
     * This maintains the same line/column tracking but with an adjusted offset.
     * Supports both positive and negative offsets.
     * @param content String content to analyze for line/column tracking
     * @param additionalOffset Number of characters to offset from current position (can be negative)
     * @param newLength Optional new length for the offset position (default: 0)
     * @return New Position object at the offset location
     */
    public function withOffset(content:String, additionalOffset:Int, newLength:Int = 0):Position {
        // Handle zero offset
        if (additionalOffset == 0) {
            return new Position(line, column, offset, newLength);
        }

        var currentLine = line;
        var currentColumn = column;
        var currentOffset = offset;

        if (additionalOffset > 0) {
            // Moving forward in the text
            var chars = 0;
            while (chars < additionalOffset) {
                if (currentOffset < content.uLength() && content.uCharCodeAt(currentOffset) == '\n'.code) {
                    currentLine++;
                    currentColumn = 1;
                } else {
                    currentColumn++;
                }
                chars++;
                currentOffset++;
            }
        } else {
            // Moving backward in the text
            var chars = 0;
            while (chars > additionalOffset) {
                currentOffset--;
                if (currentOffset >= 0 && content.uCharCodeAt(currentOffset) == '\n'.code) {
                    currentLine--;
                    // Need to scan backward to find the previous line's length
                    var col = 1;
                    var scanPos = currentOffset - 1;
                    while (scanPos >= 0) {
                        var c = content.uCharCodeAt(scanPos);
                        if (c == '\n'.code) break;
                        col++;
                        scanPos--;
                    }
                    currentColumn = col;
                } else {
                    currentColumn--;
                }
                chars--;
            }
        }

        // Ensure we don't go before the start of the file
        if (currentOffset < 0) {
            currentOffset = 0;
            currentLine = 1;
            currentColumn = 1;
        }

        return new Position(
            currentLine,
            currentColumn,
            currentOffset,
            newLength
        );
    }

    /**
     * Creates a new position that extends from this position's start to another position's end.
     * Useful for creating spans that encompass multiple tokens or nodes.
     * @param endPos Position marking the end of the span
     * @return New Position object representing the extended span
     */
    public function extendedTo(endPos:Position):Position {
        return new Position(
            line,
            column,
            offset,
            (endPos.offset + endPos.length) - offset
        );
    }

}