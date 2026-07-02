package loreline;

using StringTools;

/**
 * Minimal self-contained YAML subset parser.
 *
 * Covers what the CLI test protocol needs (spec.yml files and `<test>` blocks):
 * maps and lists nested by indentation, `- ` list entries (inline or block),
 * inline arrays `[a, b, 1]`, literal block scalars (`|`), quoted and bare
 * scalars, `#` comments and blank lines.
 * This simplified version is also properly compatible with the most quirky targets of Haxe (C#).
 */
class MiniYaml {

    public static function parse(input:String):Dynamic {

        final lines = input.replace("\r\n", "\n").split("\n");
        final pos = {index: 0};
        skipBlank(lines, pos);
        if (pos.index >= lines.length) return null;

        final line = lines[pos.index];
        final trimmed = line.trim();
        if (trimmed.startsWith('- ') || trimmed == '-') {
            return parseList(lines, pos, indentOf(line));
        }
        return parseMap(lines, pos, indentOf(line));

    }

    static function indentOf(line:String):Int {
        var i = 0;
        while (i < line.length && line.charCodeAt(i) == ' '.code) i++;
        return i;
    }

    static function isBlankOrComment(line:String):Bool {
        final t = line.trim();
        return t.length == 0 || t.startsWith('#');
    }

    static function skipBlank(lines:Array<String>, pos:{index:Int}):Void {
        while (pos.index < lines.length && isBlankOrComment(lines[pos.index])) pos.index++;
    }

    /** Parses consecutive `- ...` entries at the given indentation. */
    static function parseList(lines:Array<String>, pos:{index:Int}, indent:Int):Array<Dynamic> {

        final result:Array<Dynamic> = [];

        while (true) {
            skipBlank(lines, pos);
            if (pos.index >= lines.length) break;

            final line = lines[pos.index];
            final lineIndent = indentOf(line);
            final trimmed = line.trim();
            if (lineIndent != indent || !(trimmed.startsWith('- ') || trimmed == '-')) break;

            pos.index++;

            if (trimmed == '-') {
                // Entry content on following lines
                skipBlank(lines, pos);
                if (pos.index < lines.length && indentOf(lines[pos.index]) > indent) {
                    result.push(parseNested(lines, pos, indentOf(lines[pos.index])));
                }
                else {
                    result.push(null);
                }
            }
            else {
                // Inline content after `- `; treat it as the first line of a nested
                // node whose keys continue at a deeper indentation.
                final rest = trimmed.substr(2);
                final restIndent = lineIndent + 2;
                if (isMapEntry(rest)) {
                    result.push(parseMapEntryThenSiblings(lines, pos, rest, restIndent));
                }
                else {
                    result.push(parseScalar(rest));
                }
            }
        }

        return result;

    }

    /** Whether a trimmed line looks like a `key: ...` map entry. */
    static function isMapEntry(trimmed:String):Bool {
        final colon = findKeyColon(trimmed);
        return colon != -1;
    }

    /**
     * Finds the colon ending an unquoted key (a colon at end of line or
     * followed by a space), ignoring colons inside quotes.
     */
    static function findKeyColon(trimmed:String):Int {
        var inSingle = false;
        var inDouble = false;
        for (i in 0...trimmed.length) {
            final c = trimmed.charCodeAt(i);
            if (inSingle) {
                if (c == "'".code) inSingle = false;
            }
            else if (inDouble) {
                if (c == '"'.code) inDouble = false;
            }
            else if (c == "'".code) inSingle = true;
            else if (c == '"'.code) inDouble = true;
            else if (c == ':'.code) {
                if (i == trimmed.length - 1) return i;
                final next = trimmed.charCodeAt(i + 1);
                if (next == ' '.code) return i;
            }
        }
        return -1;
    }

    /**
     * Parses one `key: ...` entry (already read, `pos` past its line), then any
     * sibling keys at `indent`, returning the completed map.
     */
    static function parseMapEntryThenSiblings(lines:Array<String>, pos:{index:Int}, firstEntry:String, indent:Int):Dynamic {

        final result:Dynamic = {};
        applyMapEntry(result, firstEntry, lines, pos, indent);

        while (true) {
            skipBlank(lines, pos);
            if (pos.index >= lines.length) break;

            final line = lines[pos.index];
            if (indentOf(line) != indent) break;
            final trimmed = line.trim();
            if (trimmed.startsWith('- ')) break;
            if (!isMapEntry(trimmed)) break;

            pos.index++;
            applyMapEntry(result, trimmed, lines, pos, indent);
        }

        return result;

    }

    /** Parses consecutive `key: ...` entries at the given indentation. */
    static function parseMap(lines:Array<String>, pos:{index:Int}, indent:Int):Dynamic {

        final result:Dynamic = {};

        while (true) {
            skipBlank(lines, pos);
            if (pos.index >= lines.length) break;

            final line = lines[pos.index];
            if (indentOf(line) != indent) break;
            final trimmed = line.trim();
            if (!isMapEntry(trimmed)) break;

            pos.index++;
            applyMapEntry(result, trimmed, lines, pos, indent);
        }

        return result;

    }

    /** Parses whatever node starts at the current line. */
    static function parseNested(lines:Array<String>, pos:{index:Int}, indent:Int):Dynamic {
        final trimmed = lines[pos.index].trim();
        if (trimmed.startsWith('- ') || trimmed == '-') {
            return parseList(lines, pos, indent);
        }
        return parseMap(lines, pos, indent);
    }

    /** Applies one `key: value` entry (value inline, block scalar, or nested). */
    static function applyMapEntry(result:Dynamic, trimmed:String, lines:Array<String>, pos:{index:Int}, indent:Int):Void {

        final colon = findKeyColon(trimmed);
        var key = trimmed.substr(0, colon).trim();
        key = unquote(key);
        final rawValue = trimmed.substr(colon + 1).trim();

        if (rawValue == '|' || rawValue == '|-' || rawValue == '|+') {
            Reflect.setField(result, key, parseBlockScalar(lines, pos, indent, rawValue));
        }
        else if (rawValue.length == 0 || rawValue.startsWith('#')) {
            // Value on following lines (nested map/list), or null
            skipBlank(lines, pos);
            if (pos.index < lines.length && indentOf(lines[pos.index]) > indent) {
                Reflect.setField(result, key, parseNested(lines, pos, indentOf(lines[pos.index])));
            }
            else {
                Reflect.setField(result, key, null);
            }
        }
        else {
            Reflect.setField(result, key, parseScalar(stripComment(rawValue)));
        }

    }

    /** Reads a `|` literal block: lines more indented than the key line. */
    static function parseBlockScalar(lines:Array<String>, pos:{index:Int}, keyIndent:Int, marker:String):String {

        // Find the block's indentation from its first non-empty line
        var blockIndent = -1;
        var scan = pos.index;
        while (scan < lines.length) {
            final line = lines[scan];
            if (line.trim().length > 0) {
                if (indentOf(line) <= keyIndent) break;
                blockIndent = indentOf(line);
                break;
            }
            scan++;
        }

        final content:Array<String> = [];
        if (blockIndent != -1) {
            while (pos.index < lines.length) {
                final line = lines[pos.index];
                if (line.trim().length == 0) {
                    content.push('');
                    pos.index++;
                    continue;
                }
                if (indentOf(line) < blockIndent) break;
                content.push(line.substr(blockIndent));
                pos.index++;
            }
            // Drop trailing blank lines (they belong to whatever follows)
            while (content.length > 0 && content[content.length - 1] == '') {
                content.pop();
            }
        }

        var text = content.join('\n');
        if (marker != '|-') text += '\n';
        return text;

    }

    static function stripComment(value:String):String {
        var inSingle = false;
        var inDouble = false;
        for (i in 0...value.length) {
            final c = value.charCodeAt(i);
            if (inSingle) {
                if (c == "'".code) inSingle = false;
            }
            else if (inDouble) {
                if (c == '"'.code) inDouble = false;
            }
            else if (c == "'".code) inSingle = true;
            else if (c == '"'.code) inDouble = true;
            else if (c == '#'.code && i > 0 && value.charCodeAt(i - 1) == ' '.code) {
                return value.substr(0, i).trim();
            }
        }
        return value;
    }

    /** Parses an inline scalar or `[a, b, c]` array. */
    static function parseScalar(value:String):Dynamic {

        if (value.startsWith('[') && value.endsWith(']')) {
            final inner = value.substr(1, value.length - 2).trim();
            if (inner.length == 0) return ([]:Array<Dynamic>);
            final items:Array<Dynamic> = [];
            for (part in splitTopLevel(inner)) {
                items.push(parseScalar(part.trim()));
            }
            return items;
        }

        if (value == 'null' || value == '~') return null;
        if (value == 'true') return true;
        if (value == 'false') return false;

        if (value.startsWith('"') || value.startsWith("'")) {
            return unquote(value);
        }

        // Number?
        final asInt = Std.parseInt(value);
        if (asInt != null && Std.string(asInt) == value) return asInt;
        final asFloat = Std.parseFloat(value);
        if (!Math.isNaN(asFloat) && Std.string(asFloat) == value) return asFloat;

        return value;

    }

    /** Splits `a, b, "c, d"` on top-level commas. */
    static function splitTopLevel(input:String):Array<String> {
        final parts:Array<String> = [];
        var start = 0;
        var inSingle = false;
        var inDouble = false;
        var depth = 0;
        for (i in 0...input.length) {
            final c = input.charCodeAt(i);
            if (inSingle) {
                if (c == "'".code) inSingle = false;
            }
            else if (inDouble) {
                if (c == '"'.code) inDouble = false;
            }
            else if (c == "'".code) inSingle = true;
            else if (c == '"'.code) inDouble = true;
            else if (c == '['.code || c == '{'.code) depth++;
            else if (c == ']'.code || c == '}'.code) depth--;
            else if (c == ','.code && depth == 0) {
                parts.push(input.substring(start, i));
                start = i + 1;
            }
        }
        parts.push(input.substring(start));
        return parts;
    }

    static function unquote(value:String):String {
        if (value.length >= 2) {
            final first = value.charCodeAt(0);
            final last = value.charCodeAt(value.length - 1);
            if (first == '"'.code && last == '"'.code) {
                var inner = value.substr(1, value.length - 2);
                inner = inner.replace('\\"', '"').replace('\\\\', '\\').replace('\\n', '\n').replace('\\t', '\t');
                return inner;
            }
            if (first == "'".code && last == "'".code) {
                return value.substr(1, value.length - 2).replace("''", "'");
            }
        }
        return value;
    }

}
