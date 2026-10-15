package loreline;

using loreline.TextUnits;

/**
 * A position in the source code: its line, column and offset, and the length
 * of the span it covers. Used for tokens, nodes and error messages.
 *
 * `column`, `offset` and `length` count the units of the target's strings: UTF-16 units on JS, C#, Java and C++, UTF-8 bytes on Lua and in the C API, code points on Python, PHP, GDScript and Neko. A character above U+FFFF is 2, 4 or 1 of them. The language server
 * passes them to editors unchanged, as UTF-16 units, which they are where it
 * runs. The one thing counted in characters is `TextTag.offset`, which games
 * read on every target.
 */
class Position {

    /**
     * The line number in the source code, starting from 1.
     */
    public var line:Int;

    /**
     * The column in the source code, starting from 1, in units of the target
     * (see `loreline.TextUnits`), not in characters.
     */
    public var column:Int;

    /**
     * The offset from the start of the source code, in units of the target
     * (see `loreline.TextUnits`), not in characters.
     */
    public var offset:Int;

    /**
     * The length of the span, in units of the target. 0 for a point rather
     * than a span.
     */
    public var length:Int;

    /**
     * Creates a new position instance with the specified coordinates.
     * @param line Line number in the source (1-based)
     * @param column Column number in the source (1-based)
     * @param offset Offset from the start of the source, in units of the target
     * @param length Optional length of the source span (default: 0)
     */
    public function new(line:Int, column:Int, offset:Int, length:Int = 0) {
        this.line = line;
        this.column = column;
        this.offset = offset;
        this.length = length;
    }

    /**
     * Creates a Position object by analyzing a string content up to the specified offset.
     * Calculates the correct line and column numbers based on line breaks in the content.
     *
     * @param content The string content to analyze
     * @param offset The offset from the start of the content, in units of the target
     * @param length The length of the position (or 0 if not provided)
     * @return A new Position object with proper line and column information
     */
    public static function fromContentAndIndex(content:String, offset:Int, length:Int = 0):Position {
        var line = 1;
        var column = 1;
        var currentOffset = 0;
        var len = content.uLength();

        if (offset > len) offset = len;
        if (offset < 0) offset = 0;

        // Scan through content to calculate line and column
        while (currentOffset < offset) {
            if (content.uCharCodeAt(currentOffset) == '\n'.code) {
                line++;
                column = 1;
            } else {
                column++;
            }
            currentOffset++;
        }

        return new Position(line, column, offset, length);
    }

    /**
     * Converts the position to a human-readable string representation.
     * Useful for error messages and debugging.
     * @return The position as `(line:column:offset:length)`
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
     * @param additionalOffset Number of units to offset from current position (can be negative)
     * @param newLength Optional new length for the offset position (default: 0)
     * @return New Position object at the offset location
     */
    public function withOffset(content:String, additionalOffset:Int, newLength:Int = 0, contentStart:Int = 0):Position {
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
                if (currentOffset < (contentStart + content.uLength()) && content.uCharCodeAt(currentOffset - contentStart) == '\n'.code) {
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
                if (currentOffset >= 0 && content.uCharCodeAt(currentOffset - contentStart) == '\n'.code) {
                    currentLine--;
                    // Need to scan backward to find the previous line's length
                    var col = 1;
                    var scanPos = currentOffset - 1;
                    while (scanPos >= 0) {
                        var c = content.uCharCodeAt(scanPos - contentStart);
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