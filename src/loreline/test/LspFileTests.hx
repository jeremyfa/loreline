package loreline.test;

// The language server reads files with the sys API, which the GDScript runtime
// does not have
#if !gdscript

import loreline.MiniYaml;
import loreline.lsp.Protocol;
import loreline.lsp.Server;

using StringTools;
using loreline.Utf8;

/**
 * Language server tests written as `.lor` files: a script followed by a `<test>`
 * block listing requests and what they must answer, like the interpreter tests.
 * Each file runs with LF and CRLF line endings. Target agnostic: files are read
 * through `readFile`, so they can come from the disk or be embedded at compile
 * time.
 *
 * A request places the cursor with `at`: a piece of the file, where `|` marks the
 * cursor (at the start of the piece without it), and `occurrence` (from 1) when
 * the piece appears more than once. Then, depending on the request:
 * - `definition`: `target` (the text the target range covers, such as
 *   `beat Deep`), `file` when it is in another file (relative to the test file),
 *   or `none: true`
 * - `hover`: `contains`, or `none: true`
 * - `completion`: `includes` and `excludes`, lists of labels; `trigger` for a
 *   completion triggered by a character instead of invoked
 * - `symbols`: `includes`, names at any depth
 * - `diagnostics` (no `at`): a list of message extracts, or of `message`,
 *   `line` and `severity`; `none: true` for no diagnostic
 * - `format` (no `at`): `expected`, the formatted script
 */
class LspFileTests {

    /**
     * Root of the paths the server sees: the tests run the same way whether their
     * files come from the disk or from memory.
     */
    static final ROOT = "/lsp";

    /** Reads a file of the test folder (path relative to it), null if missing. */
    final readFile:(path:String)->Null<String>;

    public var passCount(default, null):Int = 0;

    public var failCount(default, null):Int = 0;

    public function new(readFile:(path:String)->Null<String>) {
        this.readFile = readFile;
    }

    /**
     * Runs the requests of a test file, with LF then CRLF line endings.
     * @param path Path of the test file, relative to the test folder
     */
    public function runFile(path:String, pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {
        final source = readFile(path);
        if (source == null) {
            failCount++;
            fail(path, 'file not found');
            return;
        }
        final items = testItems(source);
        if (items == null || items.length == 0) {
            failCount++;
            fail(path, 'no <test> block with requests');
            return;
        }
        for (crlf in [false, true]) {
            final server = try {
                openServer(path, crlf);
            }
            catch (e:Any) {
                failCount++;
                fail('$path ~ ${crlf ? 'CRLF' : 'LF'}', 'could not open the file in the server: ' + Std.string(e));
                continue;
            }
            for (item in items) {
                final name = '$path ~ ${crlf ? 'CRLF' : 'LF'} ~ ' + describe(item);
                try {
                    runRequest(server, path, crlf, item);
                    passCount++;
                    pass(name);
                }
                catch (e:Any) {
                    failCount++;
                    fail(name, Std.string(e));
                }
            }
        }
    }

    /** The requests of the `<test>` block of a file. */
    static function testItems(source:String):Array<Dynamic> {
        final start = source.uIndexOf('<test>');
        if (start == -1) return null;
        final end = source.uIndexOf('</test>', start + 6);
        if (end == -1) return null;
        final parsed:Dynamic = MiniYaml.parse(source.uSubstring(start + 6, end).trim());
        return parsed is Array ? parsed : null;
    }

    static function describe(item:Dynamic):String {
        return item.at != null ? '${item.request} at "${item.at}"' : Std.string(item.request);
    }

    static function normalize(content:String, crlf:Bool):String {
        final lf = content.replace('\r\n', '\n');
        return crlf ? lf.replace('\n', '\r\n') : lf;
    }

    static function uriOf(path:String):String {
        return 'file://' + [for (part in (ROOT + '/' + path).split('/')) StringTools.urlEncode(part)].join('/');
    }

    /** Path relative to the test folder of a URI the server gave back. */
    static function pathOf(uri:String):String {
        final path = StringTools.urlDecode(uri.substr('file://'.length));
        return path.startsWith(ROOT + '/') ? path.substr(ROOT.length + 1) : path;
    }

    /** Diagnostics published for each document, filled as the server sends them. */
    var diagnostics:Map<String, Array<Dynamic>>;

    function openServer(path:String, crlf:Bool):Server {
        final server = new Server();
        diagnostics = new Map();
        server.handleFile = (filePath, callback) -> {
            final content = filePath.startsWith(ROOT + '/') ? readFile(filePath.substr(ROOT.length + 1)) : null;
            callback(content != null ? normalize(content, crlf) : null);
        };
        server.onNotification = notification -> {
            if (notification.method == 'textDocument/publishDiagnostics') {
                final params:Dynamic = notification.params;
                diagnostics.set(params.uri, params.diagnostics);
            }
        };
        send(server, { jsonrpc: '2.0', id: 1, method: 'initialize', params: { capabilities: {} } });
        send(server, { jsonrpc: '2.0', method: 'initialized', params: {} });
        send(server, { jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
            textDocument: { uri: uriOf(path), languageId: 'loreline', version: 1, text: normalize(readFile(path), crlf) }
        }});
        return server;
    }

    static function send(server:Server, message:Dynamic):Dynamic {
        final response = server.handleMessageSync(message);
        if (response != null && response.error != null) throw 'error: ' + response.error.message;
        return response?.result;
    }

    /**
     * The position of the cursor given by `at`: where the piece is found, plus the
     * place of its `|`.
     */
    static function cursor(content:String, item:Dynamic):Position {
        final at:String = Std.string(item.at);
        final bar = at.uIndexOf('|');
        final piece = bar == -1 ? at : at.uSubstr(0, bar) + at.uSubstr(bar + 1);
        final occurrence:Int = item.occurrence != null ? Std.int(item.occurrence) : 1;
        // Searched in the script only, not in the <test> block that names it
        final testBlock = content.uIndexOf('<test>');
        final script = testBlock == -1 ? content : content.uSubstr(0, content.uLastIndexOf('/*', testBlock));
        var index = -1;
        for (_ in 0...occurrence) {
            index = script.uIndexOf(piece, index + 1);
            if (index == -1) throw 'text not found in the file: "$piece"' + (occurrence > 1 ? ' (occurrence $occurrence)' : '');
        }
        return positionOf(content, index + (bar == -1 ? 0 : bar));
    }

    static function positionOf(content:String, offset:Int):Position {
        var line = 0;
        var lineStart = 0;
        for (i in 0...offset) {
            if (content.uCharCodeAt(i) == '\n'.code) {
                line++;
                lineStart = i + 1;
            }
        }
        return { line: line, character: offset - lineStart };
    }

    /** The text of a range of a file, line endings aside. */
    static function textOf(content:String, range:Range):String {
        final lines = content.replace('\r\n', '\n').split('\n');
        if (range.start.line >= lines.length) return null;
        final result = new StringBuf();
        for (l in range.start.line...Std.int(Math.min(range.end.line, lines.length - 1)) + 1) {
            final text = lines[l];
            final from = l == range.start.line ? range.start.character : 0;
            final to = l == range.end.line ? range.end.character : text.uLength();
            if (l > range.start.line) result.add('\n');
            result.add(text.uSubstr(from, to - from));
        }
        return result.toString();
    }

    static function strings(value:Dynamic):Array<String> {
        if (value == null) return [];
        if (value is Array) return [for (v in (value:Array<Dynamic>)) Std.string(v)];
        return [Std.string(value)];
    }

    function runRequest(server:Server, path:String, crlf:Bool, item:Dynamic):Void {
        final uri = uriOf(path);
        final content = normalize(readFile(path), crlf);
        final textDocument = { uri: uri };
        final none = item.none == true;

        switch Std.string(item.request) {

            case 'definition':
                final links:Array<Dynamic> = send(server, { jsonrpc: '2.0', id: 2, method: 'textDocument/definition', params: {
                    textDocument: textDocument, position: cursor(content, item)
                }});
                if (none) {
                    if (links != null && links.length > 0) throw 'expected no definition, got ' + pathOf(links[0].targetUri);
                    return;
                }
                if (links == null || links.length == 0) throw 'no definition found';
                final link = links[0];
                final expectedFile = item.file != null ? directory(path) + Std.string(item.file) : path;
                final actualFile = pathOf(link.targetUri);
                if (actualFile != expectedFile) throw 'definition in $actualFile, expected $expectedFile';
                if (item.target != null) {
                    final targetContent = readFile(actualFile);
                    final text = targetContent != null ? textOf(normalize(targetContent, crlf), link.targetSelectionRange) : null;
                    if (text == null || text.trim() != Std.string(item.target)) {
                        throw 'definition covers "${text?.trim()}", expected "${item.target}"';
                    }
                }

            case 'hover':
                final hover:Dynamic = send(server, { jsonrpc: '2.0', id: 2, method: 'textDocument/hover', params: {
                    textDocument: textDocument, position: cursor(content, item)
                }});
                if (none) {
                    if (hover != null) throw 'expected no hover, got: ' + hover.contents.value;
                    return;
                }
                if (hover == null) throw 'no hover';
                final value:String = hover.contents?.value ?? Std.string(hover.contents);
                for (expected in strings(item.contains)) {
                    if (value.indexOf(expected) == -1) throw 'hover does not contain "$expected":\n$value';
                }

            case 'completion':
                final context:Dynamic = item.trigger != null
                    ? { triggerKind: 2, triggerCharacter: Std.string(item.trigger) }
                    : { triggerKind: 1 };
                final result:Dynamic = send(server, { jsonrpc: '2.0', id: 2, method: 'textDocument/completion', params: {
                    textDocument: textDocument, position: cursor(content, item), context: context
                }});
                final list:Array<Dynamic> = result == null ? [] : result is Array ? result : result.items;
                final labels = [for (entry in list) Std.string(entry.label)];
                for (expected in strings(item.includes)) {
                    if (!labels.contains(expected)) throw 'completion lacks "$expected", got: ' + labels.join(', ');
                }
                for (unexpected in strings(item.excludes)) {
                    if (labels.contains(unexpected)) throw 'completion has "$unexpected": ' + labels.join(', ');
                }

            case 'symbols':
                final symbols:Array<Dynamic> = send(server, { jsonrpc: '2.0', id: 2, method: 'textDocument/documentSymbol', params: {
                    textDocument: textDocument
                }});
                final names:Array<String> = [];
                function collect(list:Array<Dynamic>) {
                    if (list == null) return;
                    for (symbol in list) {
                        names.push(Std.string(symbol.name));
                        collect(symbol.children);
                    }
                }
                collect(symbols);
                for (expected in strings(item.includes)) {
                    if (!names.contains(expected)) throw 'symbols lack "$expected", got: ' + names.join(', ');
                }

            case 'diagnostics':
                final published = diagnostics.get(uri) ?? [];
                if (none) {
                    if (published.length > 0) throw 'expected no diagnostic, got: ' + [for (d in published) d.message].join(' / ');
                    return;
                }
                final expectations:Array<Dynamic> = item.expected is Array ? item.expected : [item.expected];
                for (expected in expectations) {
                    final message = expected is String ? expected : Std.string(expected.message);
                    final found = published.filter(d ->
                        Std.string(d.message).indexOf(message) != -1
                        && (expected is String || expected.line == null || d.range.start.line + 1 == Std.int(expected.line))
                        && (expected is String || expected.severity == null || d.severity == Std.int(expected.severity))
                    );
                    if (found.length == 0) {
                        throw 'no diagnostic matching "$message", got: ' + [for (d in published) '${d.range.start.line + 1}: ${d.message}'].join(' / ');
                    }
                }

            case 'format':
                final edits:Array<Dynamic> = send(server, { jsonrpc: '2.0', id: 2, method: 'textDocument/formatting', params: {
                    textDocument: textDocument, options: { tabSize: 2, insertSpaces: true }
                }});
                if (edits == null || edits.length != 1) throw 'expected one edit replacing the document, got ' + Std.string(edits);
                final formatted = Std.string(edits[0].newText).replace('\r\n', '\n').trim();
                final expected = Std.string(item.expected).replace('\r\n', '\n').trim();
                if (formatted != expected) throw 'formatted as:\n$formatted\nexpected:\n$expected';

            case other:
                throw 'unknown request: $other';
        }
    }

    static function directory(path:String):String {
        final index = path.lastIndexOf('/');
        return index == -1 ? '' : path.substr(0, index + 1);
    }

}

#end
