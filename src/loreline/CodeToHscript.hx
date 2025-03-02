package loreline;

using StringTools;
using loreline.Utf8;

/**
 * Preprocesses Loreline script code to make it compatible with HScript.
 * This class converts Loreline syntax into valid HScript syntax by:
 * - Converting 'and' and 'or' operators to '&&' and '||'
 * - Adding parentheses around control structure conditions
 * - Adding semicolons and braces where needed
 * - Processing string literals and comments
 */
class CodeToHscript {
    /**
     * List of control flow keywords that may need special handling
     */
    static final CONTROL_KEYWORDS = ["for", "while", "if", "else", "switch", "catch"];

    /**
     * Current position in the input string
     */
    var index:Int = 0;

    /**
     * The input Loreline script code
     */
    var input:String = null;

    /**
     * Buffer for the processed output
     */
    var output:Utf8Buf = null;

    /**
     * Buffer for tracking the current line
     */
    var lineOutput:Utf8Buf = null;

    /**
     * Length of the input string
     */
    var length:Int = 0;

    /**
     * Current indentation level
     */
    var indent:Int = 0;

    /**
     * Whether currently processing a comment
     */
    var inComment:Bool = false;

    /**
     * Whether currently processing a string literal
     */
    var inString:Bool = false;

    /**
     * Tracks position offsets for error reporting
     */
    var posOffsets:Array<Int> = null;

    /**
     * Current position offset
     */
    var currentPosOffset:Int = 0;

    /**
     * Tracks open parentheses depth
     */
    var parens:Int = 0;

    /**
     * Tracks open brackets depth
     */
    var brackets:Int = 0;

    /**
     * Whether currently processing a control structure
     */
    var inControl:Bool = false;

    /**
     * Whether currently processing a control structure without explicit parentheses
     */
    var inControlWithoutParens:Bool = false;

    /**
     * Current indentation level
     */
    var indentLevel:Int = 0;

    /**
     * Stack of indentation levels
     */
    var indentStack:Array<Int> = null;

    /**
     * Creates a new CodeToHscript instance.
     */
    public function new() {}

    /**
     * Processes a Loreline script code string and converts it to HScript compatible code.
     *
     * @param input The Loreline script code to process
     * @return The processed HScript compatible code
     */
    public function process(input:String) {
        input = input + "\n//"; // Small hack to make sure last dedent is processed

        this.input = input;
        this.index = 0;
        this.output = new Utf8Buf();
        this.lineOutput = new Utf8Buf();
        this.length = input.uLength();
        this.indent = 0;
        this.inComment = false;
        this.inString = false;
        this.posOffsets = [];
        this.currentPosOffset = 0;
        this.parens = 0;
        this.brackets = 0;
        this.inControl = false;
        this.inControlWithoutParens = false;
        this.indentStack = [];
        this.indentLevel = 0;

        processInput();

        return this.output.toString();
    }

    /**
     * Main input processing loop that handles each character in the input.
     */
    function processInput() {
        while (index < length) {
            final c = input.uCharCodeAt(index);

            if (c == "\"".code) {
                processString();
            } else if (c == "/".code) {
                final cc = input.uCharCodeAt(index + 1);
                if (cc == "/".code || cc == "*".code) {
                    processComment();
                } else {
                    index++;
                    add(c);
                }
            } else if (c == "\n".code) {
                processLineBreak();
            } else {
                if (isAlphaNumeric(c) && index > 0 && !isAlphaNumeric(input.uCharCodeAt(index - 1))) {
                    if (c == "a".code) {
                        // Convert and
                        if (input.uCharCodeAt(index + 1) == "n".code && input.uCharCodeAt(index + 2) == "d".code && !isAlphaNumeric(input.uCharCodeAt(index + 3))) {
                            index++;
                            add("&".code);
                            index++;
                            add("&".code);
                            index++;
                            add(" ".code);
                        }
                        else {
                            index++;
                            add(c);
                        }
                    }
                    else if (c == "o".code) {
                        // Convert or
                        if (input.uCharCodeAt(index + 1) == "r".code && !isAlphaNumeric(input.uCharCodeAt(index + 2))) {
                            index++;
                            add("|".code);
                            index++;
                            add("|".code);
                            index++;
                            add(" ".code);
                        }
                        else {
                            index++;
                            add(c);
                        }
                    }
                    else {
                        index++;
                        add(c);
                    }
                }
                else {
                    index++;
                    add(c);
                }
            }
        }
    }

    /**
     * Processes a string literal, preserving its content and escape sequences.
     */
    function processString() {
        inString = true;

        // Add the opening quote
        index++;
        add("\"".code);

        // Process the string content
        while (index < length) {
            final c = input.uCharCodeAt(index);

            if (c == "\"".code) {
                // End of string found
                index++;
                add("\"".code);
                inString = false;
                break;
            } else if (c == "\\".code && index + 1 < length) {
                // Handle escaped characters
                final nextChar = input.uCharCodeAt(index + 1);
                if (nextChar == "\"".code || nextChar == "\\".code || nextChar == "n".code || nextChar == "r".code || nextChar == "t".code) {
                    // Add the escape sequence (both chars)
                    index++;
                    add(c);
                    index++;
                    add(nextChar);
                } else {
                    // Not a common escape sequence, just add the backslash
                    index++;
                    add(c);
                }
            } else {
                // Regular character
                index++;
                add(c);
            }
        }
    }

    /**
     * Processes comments, preserving their layout while replacing content with spaces
     * to maintain character positions for error reporting.
     */
    function processComment() {
        inComment = true;

        // Get the second character that determines comment type
        final c = input.uCharCodeAt(index + 1);

        if (c == "/".code) {
            // Single line comment (// ...)
            index++; // Skip the //
            add(" ".code);
            index++;
            add(" ".code);

            // Replace each character with space until we hit a line break or EOF
            while (index < length) {
                final cc = input.uCharCodeAt(index);
                if (cc == "\n".code) {
                    break; // Keep the line break intact, but don't process it here
                }
                index++;
                add(" ".code); // Replace with space
            }
        } else if (c == "*".code) {
            // Multi-line comment (/* ... */)
            index++; // Skip the /*
            add(" ".code);
            index++;
            add(" ".code);

            while (index < length) {
                final cc = input.uCharCodeAt(index);

                if (cc == "*".code && index + 1 < length && input.uCharCodeAt(index + 1) == "/".code) {
                    // End of comment found
                    index++;
                    add(" ".code); // Replace "*" with space
                    index++;
                    add(" ".code); // Replace "/" with space
                    break;
                } else if (cc == "\n".code) {
                    // Preserve line breaks
                    index++;
                    add("\n".code);
                } else {
                    // Replace with space
                    index++;
                    add(" ".code);
                }
            }
        }

        inComment = false;
    }

    /**
     * Processes a line break character.
     */
    function processLineBreak() {
        index++;
        add("\n".code);
    }

    /**
     * Checks if a line ends with a specific character.
     *
     * @param line The line to check
     * @param c The character code to look for
     * @return True if the line ends with the character, false otherwise
     */
    function endsWithChar(line:String, c:Int):Bool {
        // Check if the line ends with an opening brace '{'
        if (line.uLength() == 0)
            return false;

        final trimmed = line.rtrim();
        final len = trimmed.uLength();
        return len > 0 && trimmed.uCharCodeAt(len - 1) == c;
    }

    /**
     * Checks if the next non-whitespace, non-comment character in the input is a specific character.
     *
     * @param c The character code to look for
     * @param pos The position to start looking from
     * @return True if the next meaningful character is the one we're looking for, false otherwise
     */
    function followsWithChar(c:Int, pos:Int):Bool {
        // Skip whitespace, newlines, and comments to check if the next meaningful character is c
        var tempIndex = pos;
        var tempInComment = false;
        var tempInString = false;

        while (tempIndex < length) {
            final cc = input.uCharCodeAt(tempIndex);

            // Skip whitespace and newlines
            if (cc == " ".code || cc == "\t".code || cc == "\n".code || cc == "\r".code) {
                tempIndex++;
                continue;
            }

            // Check for comments
            if (cc == "/".code && tempIndex + 1 < length) {
                final nextChar = input.uCharCodeAt(tempIndex + 1);

                // Single-line comment
                if (nextChar == "/".code) {
                    tempIndex += 2;
                    // Skip to end of line
                    while (tempIndex < length && input.uCharCodeAt(tempIndex) != "\n".code) {
                        tempIndex++;
                    }
                    if (tempIndex < length)
                        tempIndex++; // Skip the newline
                    continue;
                }

                // Multi-line comment
                if (nextChar == "*".code) {
                    tempIndex += 2;
                    // Skip to end of comment
                    while (tempIndex + 1 < length) {
                        if (input.uCharCodeAt(tempIndex) == "*".code && input.uCharCodeAt(tempIndex + 1) == "/".code) {
                            tempIndex += 2;
                            break;
                        }
                        tempIndex++;
                    }
                    continue;
                }
            }

            // We found the next meaningful character
            return cc == c;
        }

        return false;
    }

    /**
     * Checks if a line ends with a specific character or if the character follows in the input.
     *
     * @param line The line to check
     * @param c The character code to look for
     * @param pos The position to start looking from if the character is not at the end of the line
     * @return True if the character is found at the end of the line or as the next meaningful character
     */
    function endsOrFollowsWithChar(line:String, c:Int, pos:Int):Bool {
        return endsWithChar(line, c) || followsWithChar(c, pos);
    }

    /**
     * Calculates the indentation change between the current line and the next non-empty line.
     *
     * @param line The current line
     * @param pos The position to start looking from for the next line
     * @return A positive number for indent, negative for dedent, or zero for no change
     */
    function nextLineIndentOffset(line:String, pos:Int):Int {
        // Return indent offset: positive for indent, negative for dedent, zero for same indentation

        // Count leading spaces and tabs to determine indentation of current line
        var currentLine = line.ltrim();

        // Consider there is no indentation change if the line is empty
        if (currentLine.length == 0) {
            return 0;
        }

        var currentIndent = line.uLength() - currentLine.uLength();

        while (pos < length) {
            // TODO could be improved to avoid allocations
            var endLine = input.uIndexOf("\n", pos);
            if (endLine == -1)
                endLine = length;
            var nextLine = input.uSubstring(pos, endLine);
            var trimmed = nextLine.ltrim();
            if (trimmed.length > 0) {
                var nextIndent = nextLine.uLength() - trimmed.uLength();
                return nextIndent - currentIndent;
            }
            pos = endLine + 1;
        }

        return 0;
    }

    /**
     * Checks if the next non-whitespace, non-comment token is the "if" keyword.
     * Used to detect "else if" constructs that shouldn't add braces between else and if.
     *
     * @param pos The position to start looking from
     * @return True if the next token is "if", false otherwise
     */
    function followsWithIf(pos:Int):Bool {
        // Skip whitespace, newlines, and comments to check if the next meaningful token is "if"
        var tempIndex = pos;

        while (tempIndex < length) {
            final cc = input.uCharCodeAt(tempIndex);

            // Skip whitespace and newlines
            if (cc == " ".code || cc == "\t".code || cc == "\n".code || cc == "\r".code) {
                tempIndex++;
                continue;
            }

            // Check for comments
            if (cc == "/".code && tempIndex + 1 < length) {
                final nextChar = input.uCharCodeAt(tempIndex + 1);

                // Single-line comment
                if (nextChar == "/".code) {
                    tempIndex += 2;
                    // Skip to end of line
                    while (tempIndex < length && input.uCharCodeAt(tempIndex) != "\n".code) {
                        tempIndex++;
                    }
                    continue;
                }

                // Multi-line comment
                if (nextChar == "*".code) {
                    tempIndex += 2;
                    // Skip to end of comment
                    while (tempIndex + 1 < length) {
                        if (input.uCharCodeAt(tempIndex) == "*".code && input.uCharCodeAt(tempIndex + 1) == "/".code) {
                            tempIndex += 2;
                            break;
                        }
                        tempIndex++;
                    }
                    continue;
                }
            }

            // Check if we have "if" followed by a non-alphanumeric character
            if (tempIndex + 1 < length && input.uCharCodeAt(tempIndex) == "i".code && input.uCharCodeAt(tempIndex + 1) == "f".code) {
                // Make sure "if" is not part of another identifier like "iffy"
                if (tempIndex + 2 >= length || !isAlphaNumeric(input.uCharCodeAt(tempIndex + 2))) {
                    return true;
                }
            }

            // We found a non-whitespace, non-comment character that is not "if"
            return false;
        }

        return false;
    }

    /**
     * Checks if a line ends with a control flow keyword (if, for, while, etc.).
     *
     * @param line The line to check
     * @param pos The position to use for validating what follows the potential keyword
     * @return True if the line ends with a control keyword, false otherwise
     */
    function endsWithControlKeyword(line:String, pos:Int):Bool {
        // Get the trimmed line to work with
        final trimmed = line.rtrim();
        if (trimmed.length == 0)
            return false;

        // Check for each control keyword
        for (keyword in CONTROL_KEYWORDS) {
            // Check if the line ends with this keyword
            if (trimmed.endsWith(keyword)) {
                final trimmedSize = line.uLength() - trimmed.uLength();

                final keywordPos = trimmed.uLength() - keyword.length;

                // Verify there's a delimiter or beginning of line before the keyword
                final hasValidPrefix = keywordPos == 0 || !isAlphaNumeric(trimmed.uCharCodeAt(keywordPos - 1));

                // Verify what follows isn't an alphanumeric character or underscore
                final nextPos = pos; // Position to check after the current line
                final hasValidSuffix = nextPos < length && (trimmedSize > 0 || !isAlphaNumeric(input.uCharCodeAt(nextPos)));

                if (hasValidPrefix && hasValidSuffix) {
                    if (keyword != "else" || !followsWithIf(pos)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * Checks if a character is a whitespace character.
     *
     * @param c The character code to check
     * @return True if the character is whitespace, false otherwise
     */
    function isWhiteSpace(c:Int):Bool {
        return (c == " ".code || c == "\n".code || c == "\t".code || c == "\r".code);
    }

    /**
     * Checks if a character is alphanumeric or underscore.
     *
     * @param c The character code to check
     * @return True if the character is alphanumeric or underscore, false otherwise
     */
    function isAlphaNumeric(c:Int):Bool {
        return (c >= "a".code && c <= "z".code)
            || (c >= "A".code && c <= "Z".code)
            || (c >= "0".code && c <= "9".code)
            || c == "_".code;
    }

    /**
     * Adds a character to the output, handling special cases such as:
     * - String literals
     * - Control structures
     * - Indentation changes
     * - Adding missing semicolons and braces
     *
     * @param c The character code to add
     */
    function add(c:Int) {
        if (inString) {
            // When inside a string, we treat it as "the same line"
            lineOutput.addChar(" ".code);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        } else if (c == "\n".code) {
            if (inControlWithoutParens) {
                inControlWithoutParens = false;
                parens--;
                currentPosOffset++;
                lineOutput.addChar(")".code);
                output.addChar(")".code);
                posOffsets.push(currentPosOffset);
            }

            inControl = false;

            final line = lineOutput.toString();
            lineOutput = new Utf8Buf();

            if (parens == 0 && brackets == 0) {
                final semicolon = endsOrFollowsWithChar(line, ";".code, index);
                final indent = nextLineIndentOffset(line, index);

                if (line.trim().length == 0) {
                    // Nothing special to do
                } else if (indent > 0 && !endsOrFollowsWithChar(line, "{".code, index)) {
                    indentLevel += indent;
                    indentStack.push(indentLevel);

                    currentPosOffset += 2;
                    output.addChar(" ".code);
                    posOffsets.push(currentPosOffset);
                    output.addChar("{".code);
                    posOffsets.push(currentPosOffset);
                } else if (indent < 0 && !endsOrFollowsWithChar(line, "}".code, index)) {
                    if (!endsOrFollowsWithChar(line, ";".code, index)) {
                        currentPosOffset++;
                        output.addChar(";".code);
                        posOffsets.push(currentPosOffset);
                    }

                    indentLevel += indent;
                    var first = true;
                    while (indentStack[indentStack.length - 1] > indentLevel) {
                        indentStack.pop();
                        if (first) {
                            first = false;
                            currentPosOffset++;
                            output.addChar(" ".code);
                            posOffsets.push(currentPosOffset);
                        }

                        currentPosOffset++;
                        output.addChar("}".code);
                        posOffsets.push(currentPosOffset);
                    }
                } else if (!endsOrFollowsWithChar(line, ";".code, index)) {
                    currentPosOffset++;
                    output.addChar(";".code);
                    posOffsets.push(currentPosOffset);
                }
            }

            if (c == "(".code) {
                parens++;
            } else if (c == ")".code) {
                parens--;
            } else if (c == "[".code) {
                brackets++;
            } else if (c == "]".code) {
                brackets--;
            }

            output.addChar(c);
            posOffsets.push(currentPosOffset);
        } else if (!inControl && !isWhiteSpace(c) && endsWithControlKeyword(lineOutput.toString(), index - 1)) {
            inControl = true;
            if (!followsWithChar("(".code, index)) {
                inControlWithoutParens = true;
                parens++;
                currentPosOffset++;
                lineOutput.addChar(c);
                output.addChar("(".code);
                posOffsets.push(currentPosOffset);
            }
            lineOutput.addChar(c);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        } else {
            lineOutput.addChar(c);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        }
    }
}