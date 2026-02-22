package loreline;

using StringTools;
using loreline.Utf8;

enum abstract CodeToHscriptStackType(Int) {

    var ObjectBrace = 0;

    var ArrayBracket = 1;

    var Brace = 2;

    var Indent = 3;

    var CaseIndent = 4;

    var Bracket = 5;

    var Paren = 6;

    public function toString() {

        return switch abstract {
            case ObjectBrace: 'ObjectBrace';
            case ArrayBracket: 'ArrayBracket';
            case Brace: 'Brace';
            case Indent: 'Indent';
            case CaseIndent: 'CaseIndent';
            case Bracket: 'Bracket';
            case Paren: 'Paren';
        }

    }

}

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
    public var input(default, null):String = null;

    /**
     * Buffer for the processed output
     */
    public var output(default, null):Utf8Buf = null;

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
     * A stack to keep track of whether we are inside an object or array literal or not
     */
    var stack:Array<CodeToHscriptStackType>;

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

        input = input.rtrim() + "\n//<END>"; // Small hack to make sure last dedent is processed

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
        this.inControl = false;
        this.inControlWithoutParens = false;
        this.indentStack = [];
        this.indentLevel = 0;
        this.stack = [];

        processInput();

        return this.output.toString().rtrim() + "\n";

    }

    public function toLorelinePos(funcPos:Position, pmin:Int, pmax:Int):Position {

        final min = inputPosFromProcessedPos(pmin);
        final max = inputPosFromProcessedPos(pmax);
        final len = max + 1 - min;
        return funcPos.withOffset(input, min, len, funcPos.offset);

    }

    public function inputPosFromProcessedPos(pos:Int):Int {
        if (pos < 0) return 0;
        if (pos >= posOffsets.length) return input.uLength() - 1 - posOffsets[input.uLength() - 1];
        return pos - posOffsets[pos];
    }

    public function processedPosFromInputPos(pos:Int):Int {
        if (pos < 0) return 0;
        if (pos >= input.uLength()) return output.length - 1;

        // We need to find the position in the processed output that corresponds to our input position
        var count = 0;
        for (i in 0...posOffsets.length) {
            if (i - posOffsets[i] > pos) {
                // We've gone past our target position
                return i - 1;
            }
            else if (i - posOffsets[i] == pos) {
                // Found exact match
                return i;
            }
            count = i;
        }

        // If we reach here, use the last known position
        return count;
    }

    /**
     * Main input processing loop that handles each character in the input.
     */
    function processInput(until:Int = -1) {

        var braceLevel:Int = 0;
        var bracketLevel:Int = 0;
        var parenLevel:Int = 0;

        while (index < length) {
            final c = input.uCharCodeAt(index);

            if (c == "\"".code) {
                processString();
            }
            else if (c == "'".code) {
                error("Unexpected single quote");
            }
            else if (c == "/".code) {
                final cc = input.uCharCodeAt(index + 1);
                if (cc == "/".code || cc == "*".code) {
                    processComment();
                } else {
                    add(c);
                }
            }
            else if (c == "\r".code) {
                add(c);
            }
            else if (c == "\n".code) {
                add(c);
            }
            else if (c == "{".code) {
                braceLevel++;
                add(c);
            }
            else if (c == "}".code) {
                braceLevel--;
                if (c == until && braceLevel < 0) {
                    return;
                }
                else {
                    add(c);
                }
            }
            else if (c == "[".code) {
                bracketLevel++;
                add(c);
            }
            else if (c == "]".code) {
                bracketLevel--;
                if (c == until && bracketLevel < 0) {
                    return;
                }
                else {
                    add(c);
                }
            }
            else if (c == "(".code) {
                parenLevel++;
                add(c);
            }
            else if (c == ")".code) {
                parenLevel--;
                if (c == until && parenLevel < 0) {
                    return;
                }
                else {
                    add(c);
                }
            }
            else {
                if (isAlphaNumeric(c) && index > 0 && !isAlphaNumeric(input.uCharCodeAt(index - 1))) {
                    if (c == "a".code) {
                        // Convert and
                        if (input.uCharCodeAt(index + 1) == "n".code && input.uCharCodeAt(index + 2) == "d".code && !isAlphaNumeric(input.uCharCodeAt(index + 3))) {
                            add("&".code);
                            add("&".code);
                            add(" ".code);
                        }
                        else {
                            add(c);
                        }
                    }
                    else if (c == "o".code) {
                        // Convert or
                        if (input.uCharCodeAt(index + 1) == "r".code && !isAlphaNumeric(input.uCharCodeAt(index + 2))) {
                            add("|".code);
                            add("|".code);
                            add(" ".code);
                        }
                        else {
                            add(c);
                        }
                    }
                    else {
                        add(c);
                    }
                }
                else {
                    add(c);
                }
            }
        }

        // Close any remaining open indent blocks at the top level.
        // This handles cases where the function body contains only comments
        // (which are replaced with spaces and don't trigger dedent).
        if (until == -1) {
            while (stack.length > 0 && (stack[stack.length - 1] == Indent || stack[stack.length - 1] == CaseIndent)) {
                var popped = stackPop();
                indentStack.pop();
                if (popped == Indent) {
                    currentPosOffset++;
                    output.addChar(" ".code);
                    posOffsets.push(currentPosOffset);
                    currentPosOffset++;
                    output.addChar("}".code);
                    posOffsets.push(currentPosOffset);
                }
            }
        }

    }

    /**
     * Processes a string literal, preserving its content and escape sequences.
     */
    function processString() {
        inString = true;
        add('"'.code);

        var escaped = false;

        while (index < length) {
            var c = input.uCharCodeAt(index);

            if (escaped) {
                add(c);
                escaped = false;
            }
            else if (c == "\\".code) {
                escaped = true;
                add("\\".code);
            }
            else if (c == '"'.code) {
                // End of string
                add(c);
                inString = false;
                return;
            }
            else if (c == "$".code && !escaped) {
                index++;
                c = input.uCharCodeAt(index);

                if (c == "{".code) {
                    currentPosOffset--;
                    addExtra('"'.code);
                    addExtra('+'.code);

                    add('('.code); // Counts {

                    inString = false;
                    processComplexInterpolation();
                    inString = true;

                    add(')'.code); // Counts }

                    currentPosOffset--;
                    addExtra('+'.code);
                    addExtra('"'.code);
                    currentPosOffset++;
                }
                else if (isIdentifierStart(c)) {
                    currentPosOffset--;
                    addExtra('"'.code);
                    addExtra('+'.code);
                    processFieldAccessInterpolation();
                    currentPosOffset--;
                    addExtra('+'.code);
                    addExtra('"'.code);
                    currentPosOffset++;
                }
                else if (c == "$".code) {
                    // $$ → literal dollar sign
                    add("$".code);
                }
                else {
                    error("Expected identifier or { after $");
                }
            }
            else {
                add(c);
            }
        }

        error("Unterminated string");
    }

    function processComplexInterpolation() {
        processInput("}".code);
    }

    function processFieldAccessInterpolation() {
        // Read initial identifier
        if (!isIdentifierStart(input.uCharCodeAt(index))) {
            error("Expected identifier in field access");
        }
        processIdentifier();

        // Keep reading field access, array access, function calls, and their combinations
        while (index < length) {
            switch (input.uCharCodeAt(index)) {
                case "[".code:
                    add("[".code);
                    processInput("]".code);

                case "(".code:
                    add("(".code);
                    processInput(")".code);
                    add(")".code);

                case ".".code if (index + 1 < length && isIdentifierStart(input.uCharCodeAt(index + 1))):
                    add(".".code);
                    processIdentifier();

                case _:
                    break;
            }
        }
    }

    function processIdentifier() {

        while (index < length) {
            final c = input.uCharCodeAt(index);
            if (!isIdentifierPart(c)) break;
            add(c);
        }

    }

    /**
     * Checks if a character is a digit (0-9).
     * @param c Character code to check
     * @* @return Whether the character is a digit
     */
    inline function isDigit(c:Int):Bool {
        return c >= "0".code && c <= "9".code;
    }

    /**
     * Checks if a character is valid as the start of an identifier.
     * Valid identifier starts are letters and underscore.
     * @param c Character code to check
     * @return Whether the character can start an identifier
     */
    inline function isIdentifierStart(c:Int):Bool {
        return (c >= "a".code && c <= "z".code) ||
               (c >= "A".code && c <= "Z".code) ||
                c == "_".code;
    }

    /**
     * Checks if a character is valid as part of an identifier.
     * Valid identifier parts are letters, numbers, and underscore.
     * @param c Character code to check
     * @return Whether the character can be part of an identifier
     */
    inline function isIdentifierPart(c:Int):Bool {
        return isIdentifierStart(c) || isDigit(c);
    }

    /*
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
    */

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
            // Skip the //
            add(" ".code);
            add(" ".code);

            // Replace each character with space until we hit a line break or EOF
            while (index < length) {
                final cc = input.uCharCodeAt(index);
                if (cc == "\r".code || cc == "\n".code) {
                    break; // Keep the line break intact, but don't process it here
                }
                add(" ".code); // Replace with space
            }
        } else if (c == "*".code) {
            // Multi-line comment (/* ... */)
            // Skip the /*
            add(" ".code);
            add(" ".code);

            while (index < length) {
                final cc = input.uCharCodeAt(index);

                if (cc == "*".code && index + 1 < length && input.uCharCodeAt(index + 1) == "/".code) {
                    // End of comment found
                    add(" ".code); // Replace "*" with space
                    add(" ".code); // Replace "/" with space
                    break;
                } else if (cc == "\r".code || cc == "\n".code) {
                    // Preserve line breaks
                    add(cc);
                } else {
                    // Replace with space
                    add(" ".code);
                }
            }
        }

        inComment = false;
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
        var result = (len > 0 && trimmed.uCharCodeAt(len - 1) == c);
        return result;
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
        var result = false;

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
                    while (tempIndex < length && input.uCharCodeAt(tempIndex) != "\r".code && input.uCharCodeAt(tempIndex) != "\n".code) {
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
            result = (cc == c);
            break;
        }

        return result;
    }

    /**
     * Checks if a line ends with a specific character or if the character follows in the input.
     *
     * @param line The line to check
     * @param c The character code to look for
     * @param pos The position to start looking from if the character is not at the end of the line
     * @return True if the character is found at the end of the line or as the next meaningful character
     */
    function endsOrFollowsWithChar(line:String, c:Int, pos:Int, ?hxpos:haxe.PosInfos):Bool {
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

        // Track the first skipped comment's indentation to handle function bodies
        // that contain only comments (no actual code statements).
        var firstSkippedCommentIndent = -1;

        while (pos < length) {
            // TODO could be improved to avoid allocations
            var endLine = input.uIndexOf("\n", pos);
            if (endLine == -1) {
                endLine = length;
            }
            var nextLine = input.uSubstring(pos, endLine);
            var trimmed = nextLine.ltrim();
            if (trimmed.length > 0 && (!trimmed.startsWith('//') || trimmed.startsWith('//<END>')) && !trimmed.startsWith('/*')) {
                var nextIndent = nextLine.uLength() - trimmed.uLength();
                // When reaching //<END> from the function declaration line (indent 0),
                // if we only found comment lines at a higher indent, use that indent
                // to properly generate the function body braces.
                if (trimmed.startsWith('//<END>') && currentIndent == 0 && firstSkippedCommentIndent > 0) {
                    return firstSkippedCommentIndent - currentIndent;
                }
                return nextIndent - currentIndent;
            }
            // Remember the indentation of the first skipped comment line
            if (trimmed.length > 0 && firstSkippedCommentIndent == -1) {
                firstSkippedCommentIndent = nextLine.uLength() - trimmed.uLength();
            }
            pos = endLine + 1;
        }

        // If we ran off the end without finding //<END>, check comments too
        if (currentIndent == 0 && firstSkippedCommentIndent > 0) {
            return firstSkippedCommentIndent - currentIndent;
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
                    while (tempIndex < length && input.uCharCodeAt(tempIndex) != "\r".code && input.uCharCodeAt(tempIndex) != "\n".code) {
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

    function endsWithArrayIndexable(line:String):Bool {

        var length = line.uLength();
        if (length == 0) return false;

        // Get first non whitespace char code starting from end of line
        var lastNonWhitespacePos = length - 1;
        while (lastNonWhitespacePos >= 0) {
            var c = line.uCharCodeAt(lastNonWhitespacePos);
            if (!isWhitespace(c)) break;
            lastNonWhitespacePos--;
        }

        // Return false if the whole line is white spaces
        if (lastNonWhitespacePos < 0) return false;

        var lastChar = line.uCharCodeAt(lastNonWhitespacePos);

        // Return true if the non whitespace char code is anything among those: identifier character/closing parenthesis/closing brace/closing bracket
        return lastChar == ")".code ||
               lastChar == "}".code ||
               lastChar == "]".code ||
               isAlphaNumeric(lastChar);
    }

    /**
     * Checks if a character is a whitespace character.
     *
     * @param c The character code to check
     * @return True if the character is whitespace, false otherwise
     */
    function isWhitespace(c:Int):Bool {
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
     * Adds a character to the output, and increment index
     */
    extern inline overload function addExtra(c:Int) {
        _add(c, false);
    }

    /**
     * Adds a character to the output without incrementing index
     */
    extern inline overload function add(c:Int) {
        _add(c, true);
    }

    function inStatementsBlock():Bool {

        var i = stack.length - 1;
        if (i >= 0) {
            return (stack[i] == Brace || stack[i] == Indent || stack[i] == CaseIndent);
        }

        return true;

    }

    function inObjectBlock():Bool {

        var i = stack.length - 1;
        while (i >= 0) {
            if (stack[i] != Indent && stack[i] != CaseIndent) {
                var res = (stack[i] == ObjectBrace);
                return res;
            }
            i--;
        }

        return false;

    }

    function inArrayBlock():Bool {

        var i = stack.length - 1;
        while (i >= 0) {
            if (stack[i] != Indent && stack[i] != CaseIndent) {
                var res = (stack[i] == ArrayBracket);
                return res;
            }
            i--;
        }

        return false;

    }

    /**
     * Returns whether the input at the given position begins with a label pattern (identifier:).
     * @param pos Position to check from
     * @return True if a label starts at the position, false otherwise
     */
    function isLabelStart(pos:Int):Bool {

        // Skip any whitespace and comments before looking for label
        pos = skipWhitespaceAndComments(pos);

        // Check if we have a valid identifier
        if (!isIdentifierStart(input.uCharCodeAt(pos))) {
            return false;
        }

        // Track the initial position
        var startPos = pos;

        // Read through identifier characters
        pos++;
        while (pos < length && isIdentifierPart(input.uCharCodeAt(pos))) {
            pos++;
        }

        // Skip whitespace between identifier and colon
        while (pos < length && isWhitespace(input.uCharCodeAt(pos))) {
            pos++;
        }

        // Must end with a colon
        if (pos >= length || input.uCharCodeAt(pos) != ":".code) {
            return false;
        }

        // Verify that what we read is an identifier is not a keyword
        final word = input.uSubstr(startPos, pos - startPos);
        if (word == 'case') {
            return false;
        }

        return true;
    }

    function skipWhitespaceAndComments(pos:Int):Int {
        final startPos = pos;
        var foundContent = false;
        while (pos < this.length) {
            // Skip whitespace
            while (pos < this.length && (input.uCharCodeAt(pos) == " ".code || input.uCharCodeAt(pos) == "\t".code || input.uCharCodeAt(pos) == "\n".code || input.uCharCodeAt(pos) == "\r".code)) {
                pos++;
                foundContent = true;
            }

            // Check for comments
            if (pos < this.length - 1) {
                if (input.uCharCodeAt(pos) == "/".code) {
                    if (input.uCharCodeAt(pos + 1) == "/".code) {
                        // Single line comment - invalid in single line
                        pos = startPos;
                        return pos;
                    }
                    else if (input.uCharCodeAt(pos + 1) == "*".code) {
                        // Multi-line comment
                        pos += 2;
                        foundContent = true;
                        var commentClosed = false;
                        while (pos < this.length - 1) {
                            if (input.uCharCodeAt(pos) == "*".code && input.uCharCodeAt(pos + 1) == "/".code) {
                                pos += 2;
                                commentClosed = true;
                                break;
                            }
                            pos++;
                        }
                        if (!commentClosed) {
                            pos = startPos;
                            return pos;
                        }
                        continue;
                    }
                }
            }
            break;
        }
        return foundContent ? pos : startPos;
    }

    inline function stackPush(item:CodeToHscriptStackType) {
        #if loreline_debug_function_token_stack
        trace('PUSH $item i=$index output=${output.toString()}');
        #end
        stack.push(item);
    }

    inline function stackPop() {
        #if loreline_debug_function_token_stack
        final s = stack.pop();
        trace('POP $s i=$index output=${output.toString()}');
        return s;
        #else
        return stack.pop();
        #end
    }

    function _add(c:Int, incrementIndex:Bool) {
        if (incrementIndex) {
            index++;
        }
        else {
            currentPosOffset++;
        }

        if (inString) {
            // When inside a string, we treat it as "the same line"
            lineOutput.addChar(c == '"'.code ? c : " ".code);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        }
        else if (c == "\r".code || c == "\n".code) {
            if (inControlWithoutParens) {
                inControlWithoutParens = false;
                if (stackPop() != Paren) {
                    error("Unexpected end of line");
                }
                currentPosOffset++;
                lineOutput.addChar(")".code);
                output.addChar(")".code);
                posOffsets.push(currentPosOffset);
            }

            inControl = false;

            final line = lineOutput.toString();
            lineOutput = new Utf8Buf();

            if (inStatementsBlock() || inObjectBlock() || inArrayBlock()) {
                final indent = nextLineIndentOffset(line, index);

                if (line.trim().length == 0) {
                    // Nothing special to do
                }
                else if (indent > 0 && !endsOrFollowsWithChar(line, "{".code, index) && !endsOrFollowsWithChar(line, "[".code, index)) {
                    final trimmedLine = line.ltrim();
                    final isCaseLabel = (trimmedLine.startsWith("case ") || trimmedLine.startsWith("case\t"))
                        || (trimmedLine == "default" || trimmedLine.startsWith("default ") || trimmedLine.startsWith("default\t"));

                    if (isCaseLabel) {
                        stackPush(CaseIndent);

                        indentLevel += indent;
                        indentStack.push(indentLevel);
                        currentPosOffset++;
                        output.addChar(":".code);
                        posOffsets.push(currentPosOffset);
                    }
                    else {
                        stackPush(Indent);

                        indentLevel += indent;
                        indentStack.push(indentLevel);
                        currentPosOffset++;
                        output.addChar(" ".code);
                        posOffsets.push(currentPosOffset);
                        currentPosOffset++;
                        output.addChar("{".code);
                        posOffsets.push(currentPosOffset);
                    }
                }
                else if (indent < 0 && /*!endsOrFollowsWithChar(line, "}".code, index)*/ stack.length > 0 && (stack[stack.length-1] == Indent || stack[stack.length-1] == CaseIndent) /*&& !endsOrFollowsWithChar(line, "]".code, index)*/) {

                    if (!inObjectBlock() && !endsOrFollowsWithChar(line, ";".code, index)) {
                        currentPosOffset++;
                        output.addChar(";".code);
                        posOffsets.push(currentPosOffset);
                    }

                    indentLevel += indent;
                    var first = true;
                    while (indentStack.length > 0 && indentStack[indentStack.length - 1] > indentLevel && stack.length > 0 && (stack[stack.length-1] == Indent || stack[stack.length-1] == CaseIndent)) {
                        var popped = stackPop();
                        indentStack.pop();
                        if (popped == Indent) {
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
                    }
                }
                else if (indent == 0 && !endsOrFollowsWithChar(line, ";".code, index) && !endsOrFollowsWithChar(line, ",".code, index)) {
                    if (inObjectBlock()) {
                        currentPosOffset++;
                        output.addChar(",".code);
                        posOffsets.push(currentPosOffset);
                    }
                    else if (inArrayBlock()) {
                        currentPosOffset++;
                        output.addChar(",".code);
                        posOffsets.push(currentPosOffset);
                    }
                    else {
                        currentPosOffset++;
                        output.addChar(";".code);
                        posOffsets.push(currentPosOffset);
                    }
                }
            }

            output.addChar(c);
            posOffsets.push(currentPosOffset);
        }
        else if (!inControl && !isWhitespace(c) && endsWithControlKeyword(lineOutput.toString(), index - 1)) {
            inControl = true;
            if (!followsWithChar("(".code, index - 1)) {
                inControlWithoutParens = true;
                stackPush(Paren);
                currentPosOffset++;
                lineOutput.addChar(c);
                output.addChar("(".code);
                posOffsets.push(currentPosOffset);
            }
            else if (c == "(".code) {
                stackPush(Paren);
            }
            lineOutput.addChar(c);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        }
        else {
            if (c == "(".code) {
                stackPush(Paren);
            }
            else if (c == ")".code) {
                if (stackPop() != Paren) {
                    error("Unexpected: )");
                }
            }
            else if (c == "[".code) {
                if (!endsWithArrayIndexable(lineOutput.toString())) {
                    stackPush(ArrayBracket);
                }
                else {
                    stackPush(Bracket);
                }
            }
            else if (c == "]".code) {
                var popped = stackPop();
                if (popped != Bracket && popped != ArrayBracket) {
                    error("Unexpected: ]");
                }
            }
            else if (c == "{".code) {
                if (isLabelStart(index)) {
                    stackPush(ObjectBrace);
                }
                else {
                    stackPush(Brace);
                }
            }
            else if (c == "}".code) {
                var popped = stackPop();
                if (popped != Brace && popped != ObjectBrace) {
                    error("Unexpected: }");
                }
            }

            lineOutput.addChar(c);
            output.addChar(c);
            posOffsets.push(currentPosOffset);
        }
    }

    function error(message:String) {
        throw new Error(message, Position.fromContentAndIndex(input, index));
    }

}