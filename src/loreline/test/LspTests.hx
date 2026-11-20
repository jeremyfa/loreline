package loreline.test;

// The language server reads files with the sys API, which the GDScript runtime
// does not have: these tests run on the other Haxe targets of the CLI
#if !gdscript

import loreline.lsp.Protocol;
import loreline.lsp.Server;

using StringTools;

/**
 * Tests of the protocol of the language server, with files served from memory
 * instead of the disk: requests without a document, URIs spelled differently by
 * the client, unsaved changes of imported files. What a request answers on a
 * script is tested by the files of test-lsp/ (see LspFileTests).
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class LspTests {

    /**
     * A project whose root imports sub/b, which imports c: c is resolved from
     * the folder of b. The folder name has characters that clients such as
     * VS Code percent-encode but encodeURIComponent keeps as they are.
     */
    static final ROOT = "/story (1)";

    static final FILES:Map<String, String> = [
        '$ROOT/main.lor' => [
            'import "sub/b"',
            '',
            'beat Start',
            '  -> Local',
            '  -> Middle',
            '  -> Deep',
            '',
            'beat Local',
            '  Here.'
        ].join('\n'),
        '$ROOT/sub/b.lor' => [
            'import "c"',
            '',
            'beat Middle',
            '  Middle.'
        ].join('\n'),
        '$ROOT/sub/c.lor' => [
            '// A file longer than the one importing it,',
            '// so that its beat is further down than the',
            '// last line of main.lor.',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            'beat Deep',
            '  Deep.'
        ].join('\n')
    ];

    /** The URI of main.lor as VS Code sends it */
    static final MAIN_URI = "file:///story%20%281%29/main.lor";

    /**
     * The URI of sub/c.lor with a spelling the server never builds itself (an
     * encoded letter), as another client could send it
     */
    static final DEEP_URI = "file:///story%20%281%29/sub/%63.lor";

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'a request without a document', fn: () -> testShutdown()},
            {name: 'the server declares UTF-16 positions', fn: () -> testPositionEncoding()},
            {name: 'an open file keeps the URI sent by the client', fn: () -> testOpenFileUri()},
            {name: 'unsaved changes of an imported file are used', fn: () -> testUnsavedImport()},
            {name: 'a translation tag is named in the language of the tools', fn: () -> testTranslationTagKind()},
            {name: 'a failure of the client is not thrown back', fn: () -> testFailingClient()},
            {name: 'an error after an asynchronous read is answered', fn: () -> testAsyncRequestError()},
            {name: 'a Windows path is read from its URI on any platform', fn: () -> testWindowsUri()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('lsp: ' + test.name);
            }
            catch (e:Any) {
                fail('lsp: ' + test.name, Std.string(e));
            }
        }

    }

    /**
     * `shutdown` has no document: the server must answer it, so that `exit`
     * ends the process with code 0.
     */
    static function testShutdown() {
        final server = createServer();
        final request:RequestMessage = { jsonrpc: "2.0", id: 3, method: "shutdown" };
        final response = server.handleMessageSync(request);
        if (response == null) throw 'no response';
        if (response.error != null) throw 'error: ' + response.error.message;
    }

    /**
     * Columns of `loreline.Position` count the units of the target, UTF-16 ones
     * where the server runs, so it says so instead of leaving the default implied.
     */
    static function testPositionEncoding() {
        final server = new Server();
        final initialize:RequestMessage = { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } };
        final response:Dynamic = server.handleMessageSync(initialize);
        final encoding:Null<String> = response?.result?.capabilities?.positionEncoding;
        if (encoding != "utf-16") throw 'expected positionEncoding "utf-16", got ' + Std.string(encoding);
    }

    /** The editors name a `#tag` with the words of the writer, in English and in French */
    static function testTranslationTagKind() {
        loreline.lsp.LspFr.register();
        final previous = loreline.i18n.I18n.locale;
        final names = [for (locale in ['en', 'fr']) {
            loreline.i18n.I18n.locale = locale;
            Server.kindText('translation tag');
        }];
        loreline.i18n.I18n.locale = previous;
        if (names[0] != 'translation tag') throw 'expected "translation tag", got "${names[0]}"';
        if (names[1] != 'tag de traduction') throw 'expected "tag de traduction", got "${names[1]}"';
    }

    static function testOpenFileUri() {
        final server = createServer();
        open(server, MAIN_URI);
        open(server, DEEP_URI);
        final link = definition(server, MAIN_URI, 5, 6);
        equals(DEEP_URI, link.targetUri, 'target uri');
    }

    /**
     * Files opened by the client with their own URI spelling: the default file
     * handler of the server must find their text, and the documents importing
     * them must follow their changes.
     */
    static function testUnsavedImport() {
        final server = createServer(false);
        final middleUri = "file:///story%20%281%29/sub/%62.lor";
        open(server, DEEP_URI);
        open(server, middleUri);
        open(server, MAIN_URI);
        equals(2, definition(server, MAIN_URI, 4, 6).targetSelectionRange.start.line, 'target line before the change');
        final didChange:NotificationMessage = {
            jsonrpc: "2.0",
            method: "textDocument/didChange",
            params: {
                textDocument: { uri: middleUri, version: 2 },
                contentChanges: [{ text: '// Two lines\n// added\n' + FILES.get('$ROOT/sub/b.lor') }]
            }
        };
        server.handleMessageSync(didChange);
        equals(4, definition(server, MAIN_URI, 4, 6).targetSelectionRange.start.line, 'target line after the change');
    }

    /** What the client does with an answer may throw: the server answers once, and throws nothing */
    static function testFailingClient() {
        final server = new Server();
        server.onLog = (message, ?pos) -> {};
        var answers = 0;
        final initialize:RequestMessage = { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } };
        server.handleMessage(initialize, response -> {
            answers++;
            throw 'failure of the client';
        });
        equals(1, answers, 'answers');
    }

    /**
     * A document is updated before a request when a file it imports changed. When
     * files are read asynchronously, the request goes on after the read, out of
     * the catch of handleMessage: its error must still be answered, not thrown.
     */
    static function testAsyncRequestError() {
        final server = createServer();
        open(server, MAIN_URI);
        server.handleMessageSync(({
            jsonrpc: "2.0",
            method: "textDocument/didChange",
            params: {
                textDocument: { uri: "file:///story%20%281%29/sub/b.lor", version: 2 },
                contentChanges: [{ text: FILES.get('$ROOT/sub/b.lor') + '\n' }]
            }
        }:NotificationMessage));

        final reads:Array<()->Void> = [];
        server.handleFile = (path, callback) -> reads.push(() -> callback(FILES.get(path)));
        var response:ResponseMessage = null;
        final request:RequestMessage = {
            jsonrpc: "2.0",
            id: 4,
            method: "loreline/unknownMethod",
            params: { textDocument: { uri: MAIN_URI } }
        };
        server.handleMessage(request, r -> response = r);
        if (reads.length == 0) throw 'expected an asynchronous read';
        if (response != null) throw 'answered before the read';
        while (reads.length > 0) reads.shift()();
        if (response == null) throw 'no answer after the read';
        if (response.error == null) throw 'expected an error';
        equals(ErrorCodes.MethodNotFound, response.error.code, 'error code');
    }

    /**
     * Monaco and VS Code write a Windows file as file:///c%3A/path. The server
     * can't always tell it runs on Windows (in the web worker of the writer, it
     * can't), so the drive letter is recognized on any platform: the file read
     * for an import is c:/story/b.lor, never /c:/story/b.lor.
     */
    static function testWindowsUri() {
        final files = [
            'c:/story/main.lor' => 'import "b"\n\nbeat Start\n  -> Other\n',
            'c:/story/b.lor' => 'beat Other\n  Hi.\n'
        ];
        final server = new Server();
        final asked:Array<String> = [];
        server.handleFile = (path, callback) -> {
            asked.push(path);
            callback(files.get(path));
        };
        var diagnostics:Array<Dynamic> = null;
        server.onNotification = notification -> {
            if (notification.method == "textDocument/publishDiagnostics") {
                final params:Dynamic = notification.params;
                diagnostics = params.diagnostics;
            }
        };
        server.handleMessageSync(({ jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } }:RequestMessage));
        server.handleMessageSync(({ jsonrpc: "2.0", method: "initialized", params: {} }:NotificationMessage));
        server.handleMessageSync(({
            jsonrpc: "2.0",
            method: "textDocument/didOpen",
            params: {
                textDocument: { uri: "file:///c%3A/story/main.lor", languageId: "loreline", version: 1, text: files.get('c:/story/main.lor') }
            }
        }:NotificationMessage));
        if (asked.indexOf('c:/story/b.lor') == -1) throw 'expected c:/story/b.lor to be read, got: ' + asked.join(', ');
        if (diagnostics == null) throw 'no diagnostics';
        if (diagnostics.length > 0) throw 'unexpected diagnostics: ' + [for (d in diagnostics) d.message].join(', ');
    }

    static function createServer(inMemory:Bool = true):Server {
        final server = new Server();
        if (inMemory) {
            server.handleFile = (path, callback) -> callback(FILES.get(path));
        }
        final initialize:RequestMessage = {
            jsonrpc: "2.0",
            id: 1,
            method: "initialize",
            params: { capabilities: {} }
        };
        server.handleMessageSync(initialize);
        final initialized:NotificationMessage = {
            jsonrpc: "2.0",
            method: "initialized",
            params: {}
        };
        server.handleMessageSync(initialized);
        return server;
    }

    static function open(server:Server, uri:String) {
        final path = StringTools.urlDecode(uri.substr('file://'.length));
        final didOpen:NotificationMessage = {
            jsonrpc: "2.0",
            method: "textDocument/didOpen",
            params: {
                textDocument: { uri: uri, languageId: "loreline", version: 1, text: FILES.get(path) }
            }
        };
        server.handleMessageSync(didOpen);
    }

    static function definition(server:Server, uri:String, line:Int, character:Int):LocationLink {
        final request:RequestMessage = {
            jsonrpc: "2.0",
            id: 2,
            method: "textDocument/definition",
            params: {
                textDocument: { uri: uri },
                position: { line: line, character: character }
            }
        };
        final response = server.handleMessageSync(request);
        if (response == null) throw 'no response';
        if (response.error != null) throw 'error: ' + response.error.message;
        final links:Array<LocationLink> = response.result;
        if (links == null || links.length != 1) throw 'expected one location, got ' + Std.string(links);
        return links[0];
    }


    static function equals(expected:Any, actual:Any, what:String) {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ${Std.string(expected)}, got ${Std.string(actual)}';
        }
    }

}

#end
