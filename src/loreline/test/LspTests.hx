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
            {name: 'an open file keeps the URI sent by the client', fn: () -> testOpenFileUri()},
            {name: 'unsaved changes of an imported file are used', fn: () -> testUnsavedImport()}
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
