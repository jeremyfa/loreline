package loreline;

using StringTools;

/**
 * The IFID of a story: the identifier the Treaty of Babel gives a work of
 * interactive fiction, so that archives and players can tell it apart from
 * any other (https://babel.ifarchive.org). It's written in the `metadata`
 * block of the story, as `ifid: 448E73DF-2D2F-47E7-A494-A46B40D4CFB3`.
 */
class Ifid {

    /** What the treaty allows: 8 to 63 digits, capital letters and hyphens */
    static final IFID_PATTERN = ~/^[0-9A-Z-]{8,63}$/;

    /** A field of a block, its indentation, name, value and what follows the value */
    static final FIELD_PATTERN = ~/^([ \t]+)([^ \t:]+)([ \t]*:[ \t]*)(.*)$/;

    /**
     * Whether a text is a valid IFID: 8 to 63 digits, capital letters and
     * hyphens, as the treaty asks.
     */
    public static function isValid(ifid:Null<String>):Bool {
        return ifid != null && IFID_PATTERN.match(ifid);
    }

    /**
     * A new IFID: a random UUID (version 4), in capitals, as the treaty asks,
     * like `448E73DF-2D2F-47E7-A494-A46B40D4CFB3`.
     */
    public static function generate():String {
        final bytes = randomBytes();
        // The version (4) and the variant of a random UUID
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        final hex = new StringBuf();
        for (i in 0...16) {
            if (i == 4 || i == 6 || i == 8 || i == 10) hex.add('-');
            hex.add(StringTools.hex(bytes[i], 2));
        }
        return hex.toString().toUpperCase();
    }

    /**
     * 16 random bytes, from the system's source of randomness when there is
     * one (the crypto API on JavaScript, /dev/urandom on the targets that can
     * read files), so that two stories made at the same moment don't get the
     * same IFID.
     */
    static function randomBytes():Array<Int> {
        #if js
        final bytes:Null<Array<Int>> = js.Syntax.code("(typeof crypto !== 'undefined' && crypto.getRandomValues) ? Array.from(crypto.getRandomValues(new Uint8Array(16))) : null");
        if (bytes != null) return bytes;
        #elseif (sys && !loreline_gdscript_api)
        try {
            if (sys.FileSystem.exists('/dev/urandom')) {
                final input = sys.io.File.read('/dev/urandom', true);
                final read = input.read(16);
                input.close();
                return [for (i in 0...16) read.get(i)];
            }
        }
        catch (e:Dynamic) {}
        #end
        return [for (_ in 0...16) Std.random(256)];
    }

    /**
     * The source of a story with its IFID set: the value of the `ifid` field
     * replaced, or the field added to the `metadata` block, or the block
     * created at the top of the file (after the comments that open it) when
     * there is none. Only those lines change: the rest stays as written.
     * @param source The source of the story
     * @param ifid The IFID to write
     * @return The source with the IFID set
     */
    public static function write(source:String, ifid:String):String {
        final crlf = source.indexOf('\r\n') != -1;
        final cr = crlf ? '\r' : '';
        // Each line keeps its \r, if any
        final lines = source.split('\n');

        final start = metadataLine(source);
        if (start == -1) {
            final at = blockLine(lines);
            final block = ['metadata' + cr, '  ifid: ' + ifid + cr];
            // A blank line apart from what follows, unless the file was empty
            if (at < lines.length && !(at == lines.length - 1 && lines[at] == '')) block.push(cr);
            for (i in 0...block.length) lines.insert(at + i, block[i]);
            return lines.join('\n');
        }

        // The fields of the block: the lines after it, more indented, or up
        // to its closing brace
        final braces = withoutComment(lines[start]).endsWith('{');
        var fieldIndent:Null<String> = null;
        var lastField = start;
        var i = start + 1;
        while (i < lines.length) {
            final line = lines[i].replace('\r', '');
            if (line.trim() == '') {
                i++;
                continue;
            }
            if (braces ? line.trim().startsWith('}') : !(line.startsWith(' ') || line.startsWith('\t'))) break;
            if (FIELD_PATTERN.match(line)) {
                final indent = FIELD_PATTERN.matched(1);
                if (fieldIndent == null) fieldIndent = indent;
                // A field of the block itself, not of an object inside it
                if (indent == fieldIndent && FIELD_PATTERN.matched(2) == 'ifid') {
                    final rest = FIELD_PATTERN.matched(4);
                    final valueEnd = valueLength(rest);
                    lines[i] = indent + 'ifid' + FIELD_PATTERN.matched(3) + ifid + rest.substr(valueEnd) + (lines[i].endsWith('\r') ? '\r' : '');
                    return lines.join('\n');
                }
            }
            lastField = i;
            i++;
        }

        lines.insert(lastField + 1, (fieldIndent ?? '  ') + 'ifid: ' + ifid + cr);
        return lines.join('\n');
    }

    /** The index of the line opening the metadata block, or -1 when there is none */
    static function metadataLine(source:String):Int {
        final tokens = try new Lexer(source).tokenize() catch (e:Dynamic) null;
        if (tokens == null) return -1;
        for (token in tokens) {
            if (token.type == KwMetadata) return token.pos.line - 1;
        }
        return -1;
    }

    /**
     * Where a new block goes: before the first line of code, and before the
     * comments touching it, which document it. The comments at the top of the
     * file, set apart by a blank line, stay above the block.
     */
    static function blockLine(lines:Array<String>):Int {
        var inBlockComment = false;
        var firstCode = lines.length;
        final comment:Array<Bool> = [];
        for (i in 0...lines.length) {
            final line = lines[i].trim();
            var isComment = inBlockComment;
            if (inBlockComment) {
                if (line.indexOf('*/') != -1) inBlockComment = false;
            }
            else if (line.startsWith('//')) {
                isComment = true;
            }
            else if (line.startsWith('/*')) {
                isComment = true;
                inBlockComment = line.indexOf('*/') == -1;
            }
            comment.push(isComment);
            if (!isComment && line != '') {
                firstCode = i;
                break;
            }
        }
        var at = firstCode;
        while (at > 0 && comment[at - 1]) at--;
        return at;
    }

    /** A line without its `//` comment, trimmed */
    static function withoutComment(line:String):String {
        final index = line.indexOf('//');
        return (index == -1 ? line : line.substr(0, index)).trim();
    }

    /** How long the value at the start of a text is: up to a comment, or its closing quote */
    static function valueLength(rest:String):Int {
        if (rest.startsWith('"')) {
            var i = 1;
            while (i < rest.length) {
                final c = rest.charAt(i);
                if (c == '\\') i += 2;
                else if (c == '"') return i + 1;
                else i++;
            }
            return rest.length;
        }
        final comment = rest.indexOf('//');
        var end = comment == -1 ? rest.length : comment;
        // The spaces before the comment stay with it
        while (end > 0 && (rest.charAt(end - 1) == ' ' || rest.charAt(end - 1) == '\t')) end--;
        return end;
    }

}
