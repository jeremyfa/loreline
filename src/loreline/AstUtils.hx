package loreline;

import loreline.Node;
import loreline.Printer;

using loreline.Utf8;

/**
 * Static utility functions for programmatic AST formatting transformations.
 * Usable as static extensions on AstNode via `using loreline.AstUtils`.
 */
#if js
@:expose
#end
class AstUtils {

    /** Add double quotes to all unquoted string literals in the AST. */
    public static function addQuotes(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NStringLiteral)) {
                final str:NStringLiteral = cast child;
                if (str.quotes == Unquoted) {
                    str.quotes = DoubleQuotes;
                    // Transform raw parts: remove unquoted-only escapes, add quoted-only escapes
                    for (i in 0...str.parts.length) {
                        switch (str.parts[i].partType) {
                            case Raw(text):
                                str.parts[i].partType = Raw(unquotedRawToQuotedRaw(text));
                            case _:
                        }
                    }
                }
            }
        });
    }

    /** Remove double quotes from string literals that don't strictly need them. */
    public static function removeQuotes(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NStringLiteral)) {
                final str:NStringLiteral = cast child;
                if (str.quotes == DoubleQuotes) {
                    // Concatenate all raw text to check safety
                    var fullText = "";
                    for (part in str.parts) {
                        switch (part.partType) {
                            case Raw(text): fullText += text;
                            case _:
                        }
                    }
                    if (canSafelyRemoveQuotes(fullText)) {
                        str.quotes = Unquoted;
                        for (i in 0...str.parts.length) {
                            switch (str.parts[i].partType) {
                                case Raw(text):
                                    str.parts[i].partType = Raw(quotedRawToUnquotedRaw(text));
                                case _:
                            }
                        }
                    }
                }
            }
        });
    }

    /** Convert all blocks to brace style. */
    public static function toBraceStyle(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NStateDecl)) (cast(child, NStateDecl)).style = Braces;
            else if (Std.isOfType(child, NCharacterDecl)) (cast(child, NCharacterDecl)).style = Braces;
            else if (Std.isOfType(child, NBeatDecl)) (cast(child, NBeatDecl)).style = Braces;
            else if (Std.isOfType(child, NChoiceStatement)) (cast(child, NChoiceStatement)).style = Braces;
            else if (Std.isOfType(child, NChoiceOption)) (cast(child, NChoiceOption)).style = Braces;
            else if (Std.isOfType(child, NBlock)) (cast(child, NBlock)).style = Braces;
            else if (Std.isOfType(child, NLiteral)) {
                final lit:NLiteral = cast child;
                switch (lit.literalType) {
                    case Object(_): lit.literalType = Object(Braces);
                    case _:
                }
            }
        });
    }

    /** Convert all blocks to plain/indent style. */
    public static function toPlainStyle(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NStateDecl)) (cast(child, NStateDecl)).style = Plain;
            else if (Std.isOfType(child, NCharacterDecl)) (cast(child, NCharacterDecl)).style = Plain;
            else if (Std.isOfType(child, NBeatDecl)) (cast(child, NBeatDecl)).style = Plain;
            else if (Std.isOfType(child, NChoiceStatement)) (cast(child, NChoiceStatement)).style = Plain;
            else if (Std.isOfType(child, NChoiceOption)) (cast(child, NChoiceOption)).style = Plain;
            else if (Std.isOfType(child, NBlock)) (cast(child, NBlock)).style = Plain;
            else if (Std.isOfType(child, NLiteral)) {
                final lit:NLiteral = cast child;
                switch (lit.literalType) {
                    case Object(_): lit.literalType = Object(Plain);
                    case _:
                }
            }
        });
    }

    /** Convert &&/|| operators to and/or word form. */
    public static function useWordOperators(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NBinary)) {
                final bin:NBinary = cast child;
                switch (bin.op) {
                    case OpAnd(_): bin.op = OpAnd(true);
                    case OpOr(_): bin.op = OpOr(true);
                    case _:
                }
            }
        });
    }

    /** Convert and/or operators to &&/|| symbol form. */
    public static function useSymbolOperators(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NBinary)) {
                final bin:NBinary = cast child;
                switch (bin.op) {
                    case OpAnd(_): bin.op = OpAnd(false);
                    case OpOr(_): bin.op = OpOr(false);
                    case _:
                }
            }
        });
    }

    /** Convert all if conditions to use parentheses. */
    public static function useParenConditions(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NIfStatement)) (cast(child, NIfStatement)).conditionStyle = Parens;
            else if (Std.isOfType(child, NChoiceOption)) (cast(child, NChoiceOption)).conditionStyle = Parens;
        });
    }

    /** Convert all if conditions to plain style (no parentheses). */
    public static function usePlainConditions(node:AstNode):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NIfStatement)) (cast(child, NIfStatement)).conditionStyle = Plain;
            else if (Std.isOfType(child, NChoiceOption)) (cast(child, NChoiceOption)).conditionStyle = Plain;
        });
    }

    /** Re-indent function body raw code strings. */
    public static function reindentFunctions(node:AstNode, oldIndent:String, newIndent:String):Void {
        node.each((child, _) -> {
            if (Std.isOfType(child, NFunctionDecl)) {
                final func:NFunctionDecl = cast child;
                if (func.code != null && func.code.length > 0 && !func.external) {
                    func.code = reindentCode(func.code, oldIndent, newIndent);
                }
            }
        });
    }

    // ── Localization ─────────────────────────────────────────────────

    /**
     * Insert localization key hash comments directly into source text.
     * Returns the modified source content. Does NOT use the Printer,
     * so all existing content (comments, formatting, test blocks) is preserved.
     */
    public static function insertLocalizationKeys(content:String, node:AstNode):String {
        final rng = new Random();
        final sourceLines = content.split("\n");

        // Collect all existing hash IDs from the entire AST
        // (hash comments may land on sibling nodes rather than the text node itself)
        final existingIds = new Map<String, Bool>();
        node.each((child, _) -> {
            if (Std.isOfType(child, AstNode)) {
                final astChild:AstNode = cast child;
                if (astChild.trailingComments != null)
                    for (c in astChild.trailingComments) if (c.isHash) existingIds.set(StringTools.trim(c.content), true);
                if (astChild.leadingComments != null)
                    for (c in astChild.leadingComments) if (c.isHash) existingIds.set(StringTools.trim(c.content), true);
            }
        });

        // Collect insertions using byte offsets (right after each NStringLiteral)
        final insertions:Array<{offset:Int, text:String}> = [];
        node.each((child, _) -> {
            var str:NStringLiteral = null;
            if (Std.isOfType(child, NTextStatement)) str = (cast(child, NTextStatement)).content;
            else if (Std.isOfType(child, NDialogueStatement)) str = (cast(child, NDialogueStatement)).content;
            else if (Std.isOfType(child, NChoiceOption)) str = (cast(child, NChoiceOption)).text;

            if (str != null) {
                // Check the source line for an existing hash comment
                final endLine = getStringEndLine(str);
                final lineIdx = endLine - 1;
                if (lineIdx >= 0 && lineIdx < sourceLines.length && lineHasHashComment(sourceLines[lineIdx])) return;

                var id:String;
                var iterations:Int = 0;
                do {
                    id = randomId(rng, 4 + Std.int(iterations * 0.01));
                    iterations++;
                }
                while (existingIds.exists(id));
                existingIds.set(id, true);

                // Insert right after the string literal position
                insertions.push({offset: str.pos.offset + str.pos.length, text: ' #$id'});
            }
        });

        if (insertions.length == 0) return content;

        // Sort by offset descending and apply (avoids index shifting)
        insertions.sort((a, b) -> b.offset - a.offset);
        var result = content;
        for (ins in insertions) {
            result = result.uSubstr(0, ins.offset) + ins.text + result.uSubstr(ins.offset);
        }
        return result;
    }

    /** Remove all #hash localization keys from source content, using AST positions. */
    public static function removeLocalizationKeys(content:String, node:AstNode):String {
        final removals:Array<{start:Int, end:Int}> = [];

        node.each((child, _) -> {
            if (Std.isOfType(child, AstNode)) {
                final astChild:AstNode = cast child;
                inline function collectHash(comments:Array<Comment>) {
                    if (comments != null) {
                        for (c in comments) {
                            if (c.isHash) {
                                var start = c.pos.offset;
                                var end = c.pos.offset + c.pos.length;
                                // Also remove preceding whitespace (spaces/tabs before #)
                                while (start > 0) {
                                    final ch = content.uCharCodeAt(start - 1);
                                    if (ch == ' '.code || ch == '\t'.code)
                                        start--;
                                    else
                                        break;
                                }
                                removals.push({start: start, end: end});
                            }
                        }
                    }
                }
                collectHash(astChild.trailingComments);
                collectHash(astChild.leadingComments);
            }
        });

        if (removals.length == 0) return content;

        // Sort by offset descending and apply
        removals.sort((a, b) -> b.start - a.start);
        var result = content;
        for (r in removals) {
            result = result.uSubstr(0, r.start) + result.uSubstr(r.end);
        }
        return result;
    }

    /** Check if a source line contains a hash comment (# followed by word chars, not preceded by \). */
    static function lineHasHashComment(line:String):Bool {
        var i = 0;
        while (i < line.length) {
            if (line.charCodeAt(i) == '#'.code) {
                // Skip escaped hashes (##)
                if (i + 1 < line.length && line.charCodeAt(i + 1) == '#'.code) {
                    i += 2;
                    continue;
                }
                // Check if preceded by backslash (escaped)
                if (i > 0 && line.charCodeAt(i - 1) == '\\'.code) {
                    i++;
                    continue;
                }
                // Check if followed by at least one word character (a-z, A-Z, 0-9, _, -)
                var j = i + 1;
                while (j < line.length) {
                    final c = line.charCodeAt(j);
                    if ((c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) ||
                        (c >= '0'.code && c <= '9'.code) || c == '_'.code || c == '-'.code)
                        j++;
                    else
                        break;
                }
                if (j > i + 1) return true; // found # followed by word chars
            }
            i++;
        }
        return false;
    }

    /**
     * Extract translations from a parsed translation file.
     * Returns a map of localization key → NStringLiteral.
     * Looks for hash comments (#key) on text/dialogue nodes.
     */
    public static function extractTranslations(node:AstNode):Map<String, NStringLiteral> {
        final result = new Map<String, NStringLiteral>();
        node.each((child, _) -> {
            var str:NStringLiteral = null;
            var astNode:AstNode = null;
            if (Std.isOfType(child, NTextStatement)) { astNode = cast child; str = (cast(child, NTextStatement)).content; }
            else if (Std.isOfType(child, NDialogueStatement)) { astNode = cast child; str = (cast(child, NDialogueStatement)).content; }

            if (str != null && astNode != null) {
                final hashId = findHashComment(astNode, str);
                if (hashId != null) {
                    result.set(hashId, str);
                }
            }
        });
        return result;
    }

    /**
     * Collects all translatable entries with #id from a source script, in source order.
     * Returns pairs of {id, str} for NTextStatement, NDialogueStatement, and NChoiceOption.
     */
    public static function extractTranslatableEntries(node:AstNode):Array<{id:String, str:NStringLiteral}> {
        final result:Array<{id:String, str:NStringLiteral}> = [];
        node.each((child, _) -> {
            var astNode:AstNode = null;
            var str:NStringLiteral = null;
            if (Std.isOfType(child, NTextStatement)) {
                astNode = cast child; str = (cast(child, NTextStatement)).content;
            } else if (Std.isOfType(child, NDialogueStatement)) {
                astNode = cast child; str = (cast(child, NDialogueStatement)).content;
            } else if (Std.isOfType(child, NChoiceOption)) {
                final opt:NChoiceOption = cast child;
                if (opt.text != null) { astNode = cast child; str = opt.text; }
            }
            if (str != null && astNode != null) {
                final hashId = findHashComment(astNode, str);
                if (hashId != null) result.push({id: hashId, str: str});
            }
        });
        return result;
    }

    /**
     * Generates a translation file from a source script.
     * Each entry has: #id // original-text-as-in-source (with quotes preserved),
     * followed by translated text or original as placeholder.
     */
    public static function generateTranslationFile(
        sourceScript:AstNode,
        existingTranslations:Null<Map<String, NStringLiteral>>,
        printer:Printer
    ):String {
        final entries = extractTranslatableEntries(sourceScript);
        final buf = new Utf8Buf();
        var first = true;
        buf.add("\n");

        for (entry in entries) {
            if (!first) buf.add("\n");
            first = false;

            final refText = printer.printStringLiteralAsReference(entry.str);
            final plainText = printer.printStringLiteralAsText(entry.str);

            buf.add("#");
            buf.add(entry.id);
            buf.add(" // ");
            buf.add(refText);
            buf.add("\n");

            if (existingTranslations != null && existingTranslations.exists(entry.id)) {
                buf.add(printer.printStringLiteralAsText(existingTranslations.get(entry.id)));
            } else {
                buf.add(plainText);
            }
            buf.add("\n");
        }

        return buf.toString();
    }

    // ── Private helpers ─────────────────────────────────────────────

    /**
     * Transform a Raw text part from unquoted to quoted context.
     * - Remove unquoted-only escapes: \= → =, \{ → {, \X → X (for X not in {n,t,r,\,<})
     * - Add quoted-only escapes: " → \"
     * - Keep shared escapes: \n, \t, \r, \\, \<, $$
     */
    static function unquotedRawToQuotedRaw(text:String):String {
        var result = new StringBuf();
        var i = 0;
        while (i < text.length) {
            final c = text.charCodeAt(i);
            if (c == '\\'.code && i + 1 < text.length) {
                final next = text.charCodeAt(i + 1);
                // Shared escapes — keep as-is
                if (next == 'n'.code || next == 't'.code || next == 'r'.code || next == '\\'.code || next == '<'.code) {
                    result.addChar(c);
                    result.addChar(next);
                    i += 2;
                } else {
                    // Unquoted-only escape (\=, \{, etc.) — remove the backslash
                    result.addChar(next);
                    i += 2;
                }
            } else if (c == '"'.code) {
                // Add quoted-only escape
                result.add('\\"');
                i++;
            } else {
                result.addChar(c);
                i++;
            }
        }
        return result.toString();
    }

    /**
     * Transform a Raw text part from quoted to unquoted context.
     * - Remove quoted-only escapes: \" → "
     * - Keep shared escapes: \n, \t, \r, \\, \<, $$
     */
    static function quotedRawToUnquotedRaw(text:String):String {
        var result = new StringBuf();
        var i = 0;
        while (i < text.length) {
            final c = text.charCodeAt(i);
            if (c == '\\'.code && i + 1 < text.length) {
                final next = text.charCodeAt(i + 1);
                if (next == '"'.code) {
                    // Quoted-only escape — remove backslash
                    result.addChar(next);
                    i += 2;
                } else {
                    // All other escapes — keep as-is
                    result.addChar(c);
                    result.addChar(next);
                    i += 2;
                }
            } else {
                result.addChar(c);
                i++;
            }
        }
        return result.toString();
    }

    /**
     * Checks if removing quotes from this text would be safe (re-parseable as unquoted).
     * Conservative: rejects if any condition makes the text ambiguous as unquoted.
     */
    static function canSafelyRemoveQuotes(text:String):Bool {
        if (text.length == 0) return false;

        // Check for real newlines (multiline quoted strings can't be unquoted safely)
        if (text.indexOf("\n") != -1) return false;

        // Check if contains { which would end unquoted string early
        if (text.indexOf("{") != -1) return false;

        final firstChar = text.charCodeAt(0);

        // Starts with problematic characters
        if (firstChar == '('.code || firstChar == '['.code || firstChar == '{'.code ||
            firstChar == '}'.code || firstChar == ']'.code || firstChar == ':'.code ||
            firstChar == '='.code) return false;

        // Starts with comment
        if (text.length >= 2 && firstChar == '/'.code) {
            final second = text.charCodeAt(1);
            if (second == '/'.code || second == '*'.code) return false;
        }

        // Starts with transition
        if (text.length >= 2 && firstChar == '-'.code && text.charCodeAt(1) == '>'.code) return false;

        // Starts with + followed by space+identifier (insertion)
        if (firstChar == '+'.code && text.length >= 3 && text.charCodeAt(1) == ' '.code) return false;

        // Check for keywords at start
        final keywords = ["beat ", "state ", "character ", "choice ", "import ", "new ", "function ", "if ", "else "];
        for (kw in keywords) {
            if (StringTools.startsWith(text, kw)) return false;
        }

        // Check for Identifier: pattern (dialogue)
        var colonIdx = text.indexOf(":");
        if (colonIdx > 0) {
            var allIdentChars = true;
            for (j in 0...colonIdx) {
                final ch = text.charCodeAt(j);
                if (!((ch >= 'a'.code && ch <= 'z'.code) || (ch >= 'A'.code && ch <= 'Z'.code) ||
                      (ch >= '0'.code && ch <= '9'.code) || ch == '_'.code)) {
                    allIdentChars = false;
                    break;
                }
            }
            if (allIdentChars) return false;
        }

        // Check for number literal, null, true, false
        if (text == "null" || text == "true" || text == "false") return false;
        if (isNumberLiteral(text)) return false;

        // Check for assignment operators
        if (text.length >= 2) {
            final second = text.charCodeAt(1);
            if (second == '='.code &&
                (firstChar == '+'.code || firstChar == '-'.code || firstChar == '*'.code || firstChar == '/'.code))
                return false;
        }

        return true;
    }

    static function isNumberLiteral(text:String):Bool {
        if (text.length == 0) return false;
        var i = 0;
        if (text.charCodeAt(0) == '-'.code) i++;
        if (i >= text.length) return false;
        var hasDigit = false;
        var hasDot = false;
        while (i < text.length) {
            final c = text.charCodeAt(i);
            if (c >= '0'.code && c <= '9'.code) { hasDigit = true; }
            else if (c == '.'.code && !hasDot) { hasDot = true; }
            else return false;
            i++;
        }
        return hasDigit;
    }

    /**
     * Re-indent code by replacing leading old-indent units with new-indent units.
     */
    static function reindentCode(code:String, oldIndent:String, newIndent:String):String {
        if (oldIndent == newIndent) return code;
        final lines = code.split("\n");
        var result = new StringBuf();
        for (i in 0...lines.length) {
            if (i > 0) result.add("\n");
            var line = lines[i];
            // Count how many old-indent units are at the start
            var level = 0;
            var pos = 0;
            while (StringTools.startsWith(line.substr(pos), oldIndent)) {
                level++;
                pos += oldIndent.length;
            }
            // Rebuild with new indent
            for (_ in 0...level) result.add(newIndent);
            result.add(line.substr(pos));
        }
        return result.toString();
    }

    /** Find the last line (1-based) occupied by a string literal, accounting for multiline raw parts. */
    static function getStringEndLine(str:NStringLiteral):Int {
        var endLine = str.pos.line;
        for (part in str.parts) {
            if (part.pos != null) {
                var partEndLine = part.pos.line;
                switch (part.partType) {
                    case Raw(text):
                        var i = 0;
                        while (i < text.length) {
                            if (text.charCodeAt(i) == '\n'.code) partEndLine++;
                            i++;
                        }
                    default:
                }
                if (partEndLine > endLine) endLine = partEndLine;
            }
        }
        return endLine;
    }

    /**
     * Helper: find the first hash comment on a node and return its content (the localization key).
     * Returns null if no hash comment is found.
     */
    public static function findHashComment(node:AstNode, ?str:NStringLiteral):Null<String> {
        if (node.trailingComments != null)
            for (c in node.trailingComments) if (c.isHash) return StringTools.trim(c.content);
        if (node.leadingComments != null)
            for (c in node.leadingComments) if (c.isHash) return StringTools.trim(c.content);
        if (str != null) {
            if (str.trailingComments != null)
                for (c in str.trailingComments) if (c.isHash) return StringTools.trim(c.content);
            if (str.leadingComments != null)
                for (c in str.leadingComments) if (c.isHash) return StringTools.trim(c.content);
        }
        return null;
    }

    /** Generate a random base36 ID of the given length, guaranteed to not be a valid hex string. */
    static function randomId(rng:Random, length:Int):String {
        static final chars = "0123456789abcdefghijklmnopqrstuvwxyz";
        static final nonHexChars = "ghijklmnopqrstuvwxyz";
        final buf = new Utf8Buf();
        for (_ in 0...length) {
            buf.addChar(chars.charCodeAt(rng.between(0, 36)));
        }
        var result = buf.toString();
        // Ensure result is not a valid hex string (prevent VSCode color code detection)
        var allHex = true;
        for (i in 0...result.length) {
            final c = result.charCodeAt(i);
            if (!((c >= '0'.code && c <= '9'.code) || (c >= 'a'.code && c <= 'f'.code))) {
                allHex = false;
                break;
            }
        }
        if (allHex) {
            // Replace one random position with a non-hex character
            final pos = rng.between(0, length);
            final replacement = nonHexChars.charCodeAt(rng.between(0, nonHexChars.length));
            result = result.substr(0, pos) + String.fromCharCode(replacement) + result.substr(pos + 1);
        }
        return result;
    }
}
