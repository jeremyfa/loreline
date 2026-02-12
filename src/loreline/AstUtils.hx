package loreline;

import loreline.Node;

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

    /** Add localization key tags to all translatable text in the AST. */
    public static function addLocalizationKeys(node:AstNode):Void {
        node.each((child, _) -> {
            var str:NStringLiteral = null;
            if (Std.isOfType(child, NTextStatement)) str = (cast(child, NTextStatement)).content;
            else if (Std.isOfType(child, NDialogueStatement)) str = (cast(child, NDialogueStatement)).content;
            else if (Std.isOfType(child, NChoiceOption)) str = (cast(child, NChoiceOption)).text;

            if (str != null) {
                // Skip if already has a # tag
                var hasHashTag = false;
                for (part in str.parts) {
                    switch (part.partType) {
                        case Tag(false, tagContent):
                            if (tagContent.parts.length > 0) {
                                switch (tagContent.parts[0].partType) {
                                    case Raw(text):
                                        if (StringTools.startsWith(text, "#")) {
                                            hasHashTag = true;
                                            break;
                                        }
                                    case _:
                                }
                            }
                        case _:
                    }
                }
                if (hasHashTag) return;

                // Compute canonical form for hashing
                var canonical = new StringBuf();
                for (part in str.parts) {
                    switch (part.partType) {
                        case Raw(text): canonical.add(text);
                        case Expr(_): canonical.add("${}");
                        case Tag(_, _): // skip tags
                    }
                }

                final hash = haxe.crypto.Md5.encode(canonical.toString()).substr(0, 8);
                final tagText = "#" + hash;

                // Create tag NStringLiteral with the hash
                final tagLiteral = new NStringLiteral(
                    NodeId.UNDEFINED, null, Unquoted,
                    [new NStringPart(NodeId.UNDEFINED, null, Raw(tagText))]
                );
                str.parts.push(new NStringPart(NodeId.UNDEFINED, null, Tag(false, tagLiteral)));
            }
        });
    }

    /**
     * Extract translations from a parsed translation file.
     * Returns a map of localization key → NStringLiteral (with # tag removed).
     */
    public static function extractTranslations(node:AstNode):Map<String, NStringLiteral> {
        final result = new Map<String, NStringLiteral>();
        node.each((child, _) -> {
            if (Std.isOfType(child, NTextStatement)) {
                final str:NStringLiteral = (cast(child, NTextStatement)).content;
                extractTranslationFromString(str, result);
            } else if (Std.isOfType(child, NDialogueStatement)) {
                final str:NStringLiteral = (cast(child, NDialogueStatement)).content;
                extractTranslationFromString(str, result);
            }
        });
        return result;
    }

    /**
     * Generate a translation template from a source script.
     * Outputs lines with original text as comments followed by #id and original text.
     */
    public static function generateTranslationTemplate(node:AstNode):String {
        final buf = new StringBuf();
        var first = true;
        node.each((child, _) -> {
            var str:NStringLiteral = null;
            if (Std.isOfType(child, NTextStatement)) str = (cast(child, NTextStatement)).content;
            else if (Std.isOfType(child, NDialogueStatement)) str = (cast(child, NDialogueStatement)).content;
            else if (Std.isOfType(child, NChoiceOption)) str = (cast(child, NChoiceOption)).text;

            if (str != null) {
                // Find # tag and raw text
                var tagId:String = null;
                var rawText = new StringBuf();
                for (part in str.parts) {
                    switch (part.partType) {
                        case Raw(text): rawText.add(text);
                        case Tag(false, tagContent):
                            if (tagContent.parts.length > 0) {
                                switch (tagContent.parts[0].partType) {
                                    case Raw(text):
                                        if (StringTools.startsWith(text, "#")) {
                                            tagId = text;
                                        }
                                    case _:
                                }
                            }
                        case _:
                    }
                }

                if (tagId != null) {
                    final text = StringTools.trim(rawText.toString());
                    if (!first) buf.add("\n");
                    buf.add("// ");
                    buf.add(text);
                    buf.add("\n");
                    buf.add(tagId);
                    buf.add(" ");
                    buf.add(text);
                    buf.add("\n");
                    first = false;
                }
            }
        });
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

    /**
     * Helper: extract a translation entry from a string literal with a # tag.
     * Adds the id → NStringLiteral (with # tag removed) to the result map.
     */
    static function extractTranslationFromString(str:NStringLiteral, result:Map<String, NStringLiteral>):Void {
        // Find a # tag in the parts
        var tagIndex = -1;
        var tagId:String = null;
        for (i in 0...str.parts.length) {
            switch (str.parts[i].partType) {
                case Tag(false, tagContent):
                    if (tagContent.parts.length > 0) {
                        switch (tagContent.parts[0].partType) {
                            case Raw(text):
                                if (StringTools.startsWith(text, "#")) {
                                    tagIndex = i;
                                    tagId = text.substr(1);
                                    break;
                                }
                            case _:
                        }
                    }
                case _:
            }
        }

        if (tagId != null) {
            // Create a copy of the string literal without the # tag
            final newParts = new Array<NStringPart>();
            for (i in 0...str.parts.length) {
                if (i != tagIndex) {
                    newParts.push(str.parts[i]);
                }
            }
            final translated = new NStringLiteral(
                str.nodeId, str.pos, str.quotes, newParts,
                str.leadingComments, str.trailingComments
            );
            result.set(tagId, translated);
        }
    }
}
