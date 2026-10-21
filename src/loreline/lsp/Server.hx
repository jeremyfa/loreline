package loreline.lsp;

import Type as HxType;
import haxe.Json;
import haxe.io.Path;
import loreline.Error;
import loreline.Identifiers;
import loreline.Imports;
import loreline.Lexer;
import loreline.Node;
import loreline.Parser;
import loreline.i18n.I18n;
import loreline.lsp.Protocol;

using StringTools;
using loreline.TextUnits;

/**
 * Main LSP server implementation for Loreline
 */
class Server {

    final RE_ARROW_BEFORE = ~/(->)((?:\s*|\/\*(?:[^*]|\*[^\/])*\*\/)*)$/;

    final RE_ARRAY_ACCESS_BEFORE = ~/(\])((?:\s*|\/\*(?:[^*]|\*[^\/])*\*\/)*)$/;

    /** The start of a line where the name of a field goes: its indentation, then the name being typed */
    final RE_FIELD_NAME_START = ~/^[ \t]+[A-Za-z_][A-Za-z0-9_]*$|^[ \t]+$/;

    /** A field of a block: its name, then a colon */
    final RE_FIELD_LINE = ~/^[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:/;

    /** The line opening the metadata block */
    final RE_METADATA_LINE = ~/^metadata[ \t]*(\{[ \t]*)?(\/\/.*)?$/;

    /**
     * Maps document URIs to their parsed ASTs.
     */
    final documents:Map<String, Script> = new Map();

    /**
     * Maps document URIs to the URIs they are dependent from (importing them).
     */
    final documentImports:Map<String, Array<String>> = new Map();

    /**
     * Maps document URIs to their text content.
     */
    final documentContents:Map<String, String> = new Map();

    /**
     * URIs of the documents opened by the client, as the client sent them.
     */
    final openDocuments:Map<String, Bool> = new Map();

    /**
     * Maps file paths to the text read while resolving imports, so that positions
     * in an imported file can be converted with the text of that file.
     */
    final fileContents:Map<String, String> = new Map();

    /**
     * Maps document URIs to their diagnostics.
     */
    final documentDiagnostics:Map<String, Array<Diagnostic>> = new Map();

    /**
     * Maps document URIs that need to be reloaded because some dependencies (imports)
     * have been modified.
     */
    final dirtyDocuments:Map<String, Bool> = new Map();

    /**
     * Client capabilities received from initialize request.
     */
    var clientCapabilities:ClientCapabilities;

    // Track server state
    var initialized:Bool = false;
    var shutdown:Bool = false;

    public dynamic function onLog(message:Any, ?pos:haxe.PosInfos) {
        #if (js && hxnodejs)
        js.Node.console.log(message);
        #end
    }

    public dynamic function onNotification(message:NotificationMessage) {
        // Needs to be replaced by proper handler
    }

    public dynamic function handleFile(path:String, callback:(content:String)->Void):Void {

        // The text of a file opened by the client, whatever the spelling of its URI
        final uri = uriForPath(path);
        if (documentContents.exists(uri)) {
            callback(documentContents.get(uri));
            return;
        }

        #if (sys || (js && hxnodejs))
        var content:String = null;
        try {
            if (sys.FileSystem.exists(path)) {
                content = sys.io.File.getContent(path);
            }
            setDocumentContent(uri, content);
        }
        catch (e:Any) {
            onLog("Failed to load content at path: " + path + ", " + e);
        }
        callback(content);
        #else
        onLog("Content loading not supported, cannot load content at path: " + path);
        callback(null);
        #end

    }

    final isWindows:Bool;

    public function new() {
        #if windows
        isWindows = true;
        #elseif (js && hxnodejs)
        isWindows = js.Syntax.code('process.platform === "win32"');
        #elseif sys
        isWindows = Sys.systemName() == "Windows";
        #else
        isWindows = false;
        #end
    }

    /**
     * Handle incoming JSON-RPC message
     */
    /**
     * Synchronous wrapper for handleMessage. Only safe when handleFile is synchronous.
     * Used by the VS Code extension (Node.js) where file access is sync.
     */
    public function handleMessageSync(msg:Message):Null<ResponseMessage> {
        var result:Null<ResponseMessage> = null;
        handleMessage(msg, (response) -> { result = response; });
        return result;
    }

    public function handleMessage(msg:Message, ?onResponse:(response:Null<ResponseMessage>)->Void):Void {
        try {
            // Check message type and dispatch accordingly
            if (Reflect.hasField(msg, "method")) {
                if (Reflect.hasField(msg, "id")) {
                    // Request message (may be async)
                    handleRequest(cast msg, onResponse);
                } else {
                    // Notification message (no response)
                    handleNotification(cast msg);
                    if (onResponse != null) onResponse(null);
                }
                return;
            }

            if (onResponse != null) onResponse(createErrorResponse(null, ErrorCodes.InvalidRequest, "Invalid message"));

        } catch (e:Dynamic) {
            if (onResponse != null) onResponse(createErrorResponse(null, ErrorCodes.ParseError, Std.string(e)));
        }
    }

    /**
     * Create error response
     */
    function createErrorResponse(id:RequestId, code:ErrorCodes, message:String, ?data:Any):ResponseMessage {
        final response:ResponseMessage = {
            jsonrpc: "2.0",
            id: id,
            error: {
                code: code,
                message: message,
                data: data
            }
        };
        return response;
    }

    /**
     * Create success response
     */
    function createResponse(id:RequestId, result:Any):ResponseMessage {
        final response:ResponseMessage = {
            jsonrpc: "2.0",
            id: id,
            result: result
        };
        return response;
    }

    /**
     * Handle a request message
     */
    function handleRequest(request:RequestMessage, ?onResponse:(response:ResponseMessage)->Void):Void {
        try {
            if (!initialized && request.method != "initialize") {
                throw { code: ErrorCodes.ServerNotInitialized, message: "Server not initialized" };
            }

            resolveRequest(request, (result) -> {
                if (onResponse != null) onResponse(createResponse(request.id, result));
            });

        } catch (e:Any) {
            if (onResponse != null) {
                if (Reflect.hasField(e, 'code') && Reflect.hasField(e, 'message')) {
                    final err:ResponseError = e;
                    onResponse(createErrorResponse(request.id, err.code, err.message));
                }
                else {
                    onResponse(createErrorResponse(request.id, ErrorCodes.InternalError, Std.string(e)));
                }
            }
        }
    }

    function resolveRequest(request:RequestMessage, callback:(result:Any)->Void):Void {

        // Determine which URI needs to be up-to-date before handling
        final uri = getRequestDocumentUri(request);

        // Ensure the document is up-to-date (async-safe), then dispatch
        updateDocumentIfNeeded(uri, () -> {
            try {
                final result:Any = switch (request.method) {
                    case "initialize":
                        handleInitialize(cast request.params);

                    case "shutdown":
                        handleShutdown();

                    case "textDocument/completion":
                        handleCompletion(cast request.params);

                    case "textDocument/definition":
                        handleDefinition(cast request.params);

                    case "textDocument/hover":
                        handleHover(cast request.params);

                    case "textDocument/documentSymbol":
                        handleDocumentSymbol(cast request.params);

                    case "textDocument/references":
                        null; // TODO

                    case "textDocument/formatting":
                        handleDocumentFormatting(cast request.params);

                    case _:
                        throw { code: ErrorCodes.MethodNotFound, message: 'Method not found: ${request.method}'};
                }
                callback(result);
            } catch (e:Any) {
                if (Reflect.hasField(e, 'code') && Reflect.hasField(e, 'message')) {
                    throw e;
                } else {
                    throw { code: ErrorCodes.InternalError, message: Std.string(e) };
                }
            }
        });

    }

    /** Extracts the textDocument.uri from a request's params, or null if not applicable. */
    function getRequestDocumentUri(request:RequestMessage):Null<String> {
        try {
            final params:Dynamic = request.params;
            if (params != null && params.textDocument != null && params.textDocument.uri != null) {
                return params.textDocument.uri;
            }
        } catch (_:Dynamic) {}
        return null;
    }

    /**
     * Handle a notification message
     */
    function handleNotification(notification:NotificationMessage) {
        try {
            if (!initialized && notification.method != "initialized") return;

            switch (notification.method) {
                case "initialized":
                    initialized = true;

                case "textDocument/didOpen":
                    handleDidOpenTextDocument(cast notification.params);

                case "textDocument/didChange":
                    handleDidChangeTextDocument(cast notification.params);

                case "textDocument/didSave":
                    handleDidSaveTextDocument(cast notification.params);

                case "textDocument/didClose":
                    handleDidCloseTextDocument(cast notification.params);

                case "exit":
                    handleExit();

                case "loreline/locale":
                    // The host changed its language: texts and diagnostics follow
                    final params:Dynamic = notification.params;
                    I18n.locale = I18n.fromTag(params != null ? params.locale : null);
                    for (uri in openDocuments.keys()) {
                        final content = documentContents.get(uri);
                        if (content != null) updateDocument(uri, content, true);
                    }

                case _:
                    // Ignore unknown notifications
            }
        } catch (e:Dynamic) {
            // Log error but don't respond to notifications
        }
    }

    /**
     * Handle initialize request
     */
    function handleInitialize(params:InitializeParams):{ capabilities: ServerCapabilities } {
        if (initialized) {
            throw { code: ErrorCodes.InvalidRequest, message: "Server already initialized" };
        }

        clientCapabilities = params.capabilities;

        // The language of the texts: the editor's, or the one its host asks for
        loreline.i18n.Fr.register();
        LspFr.register();
        final options:Dynamic = params.initializationOptions;
        I18n.locale = I18n.fromTag(params.locale ?? (options != null ? options.locale : null));

        return {
            capabilities: {
                // Full document sync means we'll get the entire document content on changes
                textDocumentSync: {
                    openClose: true,
                    change: TextDocumentSyncKind.Full,
                    save: { // Save notification support
                        includeText: true
                    }
                },
                // Enable completion with specific trigger characters
                completionProvider: {
                    resolveProvider: false,  // We don't provide additional resolution
                    triggerCharacters: [
                        ".",  // For field access (character.name)
                        "$",  // For interpolation ($variable)
                        "<",  // For tags (<happy>)
                        " ",  // For transitions (-> )
                        "\""  // For quoted strings
                    ]
                },
                definitionProvider: true,    // For go-to-definition
                hoverProvider: true,         // For hover tooltips
                documentSymbolProvider: true, // For document outline
                documentFormattingProvider: true,  // For code formatting
                // Columns and offsets of `loreline.Position` are units of the target;
                // the server runs on JS and C++, where they are UTF-16 units, the LSP default
                positionEncoding: PositionEncodingKind.UTF16
            }
        };
    }

    /**
     * Handle shutdown request
     */
    function handleShutdown():Null<Any> {
        if (shutdown) {
            throw { code: ErrorCodes.InvalidRequest, message: "Server already shut down" };
        }
        shutdown = true;
        return null;
    }

    /**
     * Handle exit notification
     */
    function handleExit() {
        #if (sys || hxnodejs)
        Sys.exit(shutdown ? 0 : 1);
        #end
    }

    /**
     * Handle document open
     */
    function handleDidOpenTextDocument(params:{textDocument:TextDocumentItem}) {
        final doc = params.textDocument;
        openDocuments.set(doc.uri, true);
        updateDocument(doc.uri, doc.text, true);
    }

    function handleDidSaveTextDocument(params:{
        textDocument:TextDocumentIdentifier,
        text:String
    }) {
        // Update document and run diagnostics
        if (params.text != null) {
            updateDocument(params.textDocument.uri, params.text, true);
        } else {
            // If text not included, get it from our cache
            final content = documentContents.get(params.textDocument.uri);
            if (content != null) {
                updateDocument(params.textDocument.uri, content, true);
            }
        }
    }

    /**
     * Handle document change
     */
    function handleDidChangeTextDocument(params:{
        textDocument:VersionedTextDocumentIdentifier,
        contentChanges:Array<TextDocumentContentChangeEvent>
    }) {
        if (params.contentChanges.length > 0) {
            final change = params.contentChanges[params.contentChanges.length - 1];
            updateDocument(params.textDocument.uri, change.text, false);
        }
    }

    /**
     * Handle document close
     */
    function handleDidCloseTextDocument(params:{textDocument:TextDocumentIdentifier}) {
        openDocuments.remove(params.textDocument.uri);
        documents.remove(params.textDocument.uri);
        documentContents.remove(params.textDocument.uri);
        documentDiagnostics.remove(params.textDocument.uri);
    }

    function setDocument(uri:String, ast:Script) {
        documents.set(uri, ast);
        dirtyDocuments.remove(uri);
    }

    function setDocumentContent(uri:String, content:String) {
        final previous = documentContents.get(uri);
        if (previous != content) {
            documentContents.set(uri, content);
            markDependentDocumentsDirty(uri);
        }
    }

    function markDependentDocumentsDirty(uri:String) {

        // Compared by path: the client may spell the URI of a file differently
        final path = pathFromUri(uri);

        for (key => imports in documentImports) {
            for (i in 0...imports.length) {
                final imp = imports[i];
                if (imp == uri || (path != null && pathFromUri(imp) == path)) {
                    dirtyDocuments.set(key, true);
                    break;
                }
            }
        }

    }

    /**
     * Update document content and parse
     */
    function updateDocument(uri:String, content:String, runDiagnostics:Bool = true) {
        setDocumentContent(uri, content);

        if (runDiagnostics) {
            documentDiagnostics.set(uri, []);

            final errors:Array<Any> = [];

            fetchAst(uri, content, (lexer, parser, ast) -> {
                if (ast != null) {
                    setDocument(uri, ast);

                    // Create lens
                    final lens = new Lens(ast);

                    // Keep track of document imports
                    documentImports.set(uri, [for (path in lens.getImportedPaths(pathFromUri(uri))) uriFromPath(path)]);

                    // Check for parser errors, and the lexer errors of imported files
                    final parseErrors = parser.getErrors();
                    if (parseErrors != null && parseErrors.length > 0) {
                        for (error in parseErrors) {
                            if (error.filePath != null) {
                                addImportedFileError(uri, ast, error);
                            }
                            else {
                                addDiagnostic(uri, error.pos, I18n.errorText(error), DiagnosticSeverity.Error);
                            }
                        }
                    }
                    for (e in errors) {
                        if (e is Error && (cast e:Error).filePath != null) {
                            addImportedFileError(uri, ast, cast e);
                        }
                    }

                    // Check for errors in functions
                    for (func in lens.getNodesOfType(NFunctionDecl, false)) {
                        if (!func.external) {
                            final funcLorscript = lens.getFuncLorscript(func);
                            if (funcLorscript.error != null) {
                                addDiagnostic(uri, funcLorscript.error.pos, I18n.errorText(funcLorscript.error), DiagnosticSeverity.Error);
                            }
                        }
                    }

                    // Look for transitions to unknown beats
                    // (dynamic targets are resolved at runtime, skip them)
                    for (transition in lens.getNodesOfType(NTransition, false)) {
                        if (transition.targetExpr == null && transition.target != '.') {
                            if (lens.findBeatByNameFromNode(transition.target, transition) == null) {
                                addDiagnostic(uri, transition.targetPos, I18n.t('Unknown beat: {name}', {name: transition.target}), DiagnosticSeverity.Error, 'unknown-beat');
                            }
                        }
                    }

                    // Look for insertions of unknown beats
                    // (dynamic targets are resolved at runtime, skip them)
                    for (insertion in lens.getNodesOfType(NInsertion, false)) {
                        if (insertion.targetExpr == null && insertion.target != '.') {
                            if (lens.findBeatByNameFromNode(insertion.target, insertion) == null) {
                                addDiagnostic(uri, insertion.targetPos, I18n.t('Unknown beat: {name}', {name: insertion.target}), DiagnosticSeverity.Error, 'unknown-beat');
                            }
                        }
                    }

                    // Check for references to unknown characters in dialogue statements
                    for (dialogue in lens.getNodesOfType(NDialogueStatement, false)) {
                        final parentBeat = lens.getFirstParentOfType(dialogue, NBeatDecl);
                        if (parentBeat != null && parentBeat.name != "_") {
                            final characterDecl = lens.findCharacterFromDialogue(dialogue);
                            if (characterDecl == null) {
                                // A speaker matching an enclosing beat param may hold a
                                // character passed as argument, resolved at runtime
                                var isBeatParam = false;
                                var enclosingBeat = parentBeat;
                                while (enclosingBeat != null && !isBeatParam) {
                                    if (enclosingBeat.params != null) {
                                        for (param in enclosingBeat.params) {
                                            if (param.name == dialogue.character) {
                                                isBeatParam = true;
                                                break;
                                            }
                                        }
                                    }
                                    enclosingBeat = lens.getFirstParentOfType(enclosingBeat, NBeatDecl);
                                }
                                if (isBeatParam) continue;
                                addDiagnostic(
                                    uri,
                                    dialogue.characterPos,
                                    I18n.t('Unknown character: {name}', {name: dialogue.character}),
                                    DiagnosticSeverity.Warning,
                                    'unknown-character'
                                );
                            }
                        }
                    }

                    // Names that are likely mistakes
                    for (warning in lens.getNameWarnings()) {
                        addDiagnostic(uri, warning.pos, warning.message, DiagnosticSeverity.Warning);
                    }

                    // Things worth pointing out in when blocks
                    for (when in lens.getNodesOfType(NWhenStatement, false)) {
                        for (warning in lens.getWhenWarnings(when)) {
                            addDiagnostic(uri, warning.pos, warning.message, warning.isWarning ? DiagnosticSeverity.Warning : DiagnosticSeverity.Information, warning.kind);
                        }
                    }

                    // TODO check references to beat calls and function calls

                    // Add semantic validation
                    validateDocument(uri, ast);
                }
                else {
                    for (e in errors) {
                        if (e is Error) {
                            // Handle lexer/parser errors
                            final err:Error = cast e;
                            if (err.filePath != null) {
                                addImportedFileError(uri, null, err);
                            }
                            else {
                                addDiagnostic(uri, err.pos, I18n.errorText(err), DiagnosticSeverity.Error);
                            }
                        }
                        else {
                            // Handle unexpected errors
                            addDiagnostic(uri, null, Std.string(e), DiagnosticSeverity.Error);
                        }
                    }
                }

                // Notify that document parsing is complete
                onNotification({
                    jsonrpc: "2.0",
                    method: "loreline/documentReady",
                    params: { uri: uri }
                });
            }, e -> errors.push(e));

            // Publish diagnostics
            publishDiagnostics(uri);
        } else {
            fetchAst(uri, content, (lexer, parser, ast) -> {
                if (ast != null) {
                    setDocument(uri, ast);
                }

                // Notify that document parsing is complete
                onNotification({
                    jsonrpc: "2.0",
                    method: "loreline/documentReady",
                    params: { uri: uri }
                });
            });
        }
    }

    /**
     * Shows an error found in an imported file on the line of the root's import
     * that leads to that file, with the file and its line in the message.
     */
    function addImportedFileError(uri:String, ast:Null<Script>, error:Error) {
        final rootPath = pathFromUri(uri);
        final rootDir = Path.directory(rootPath);
        var shownPath = error.filePath;
        if (rootDir != '' && shownPath.startsWith(rootDir + '/')) {
            shownPath = shownPath.substr(rootDir.length + 1);
        }
        final line = error.pos != null ? ':' + error.pos.line : '';
        addDiagnostic(
            uri,
            importPosLeadingTo(ast, rootPath, error.filePath),
            I18n.t('Error in {file}{line}: {message}', {file: shownPath, line: line, message: I18n.errorText(error)}),
            DiagnosticSeverity.Error,
            'import-error'
        );
    }

    /**
     * The position of the root's import that leads to a file, directly or through
     * the files it imports, or null when there is none.
     */
    function importPosLeadingTo(ast:Null<Script>, rootPath:String, filePath:String):Null<loreline.Position> {
        if (ast == null) return null;
        final ext = Imports.lorExtension(rootPath);
        for (node in ast.body) {
            if (node is NImportStatement) {
                final imp:NImportStatement = cast node;
                final path = Imports.resolveImportPath(Path.directory(rootPath), rawImportPath(imp), ext);
                if (path == filePath || (imp.script != null && importsLeadTo(imp.script, path, filePath, ext))) {
                    return imp.pos;
                }
            }
        }
        return null;
    }

    function importsLeadTo(script:Script, scriptPath:String, filePath:String, ext:String):Bool {
        for (node in script.body) {
            if (node is NImportStatement) {
                final imp:NImportStatement = cast node;
                final path = Imports.resolveImportPath(Path.directory(scriptPath), rawImportPath(imp), ext);
                if (path == filePath || (imp.script != null && importsLeadTo(imp.script, path, filePath, ext))) {
                    return true;
                }
            }
        }
        return false;
    }

    static function rawImportPath(imp:NImportStatement):String {
        return switch imp.path.parts[0].partType {
            case Raw(text): text;
            case _: '';
        }
    }

    function pathFromUri(uri:String):String {
        // Remove the protocol part
        var path = uri;

        // Handle file:// protocol
        if (uri.startsWith("file://")) {
            path = uri.uSubstr(7);

            // Handle Windows paths that start with drive letter
            if (isWindows) {
                // Windows file URIs look like file:///C:/path/to/file
                // The first / after file:// should be removed
                if (path.uCharCodeAt(1) == ":".code && path.uCharCodeAt(0) == "/".code) {
                    path = path.uSubstr(1);
                }
            }
        }
        else {
            return null;
        }

        // Decode URL encoding
        path = StringTools.urlDecode(path);

        // Normalize path
        path = Path.normalize(path);

        return path;
    }

    function uriFromPath(path:String):String {
        // Normalize the path first (handles backslash conversion)
        var normalizedPath = Path.normalize(path);

        // For Windows, handle drive letters
        if (isWindows && normalizedPath.charAt(1) == ":") {
            // Add the extra slash for drive letters (file:///C:/path instead of file://C:/path)
            return "file:///" + encodePathComponents(normalizedPath);
        }

        return "file://" + encodePathComponents(normalizedPath);
    }

    function encodePathComponents(path:String):String {
        // Split by slashes, encode each component separately, then rejoin
        var components = path.split("/");
        for (i in 0...components.length) {
            // Don't encode drive letters with colon on Windows
            if (!(isWindows && i == 0 && components[i].length == 2 && components[i].charAt(1) == ":")) {
                components[i] = StringTools.urlEncode(components[i]);
            }
        }
        return components.join("/");
    }

    function updateDocumentIfNeeded(uri:String, ?callback:()->Void) {

        // Requests without a document (shutdown...): some targets throw on a null map key
        if (uri != null && dirtyDocuments.exists(uri)) {
            handleFile(pathFromUri(uri), content -> {
                if (content != null) {
                    updateDocument(uri, content, true);
                }
                if (callback != null) callback();
            });
        } else {
            if (callback != null) callback();
        }

    }

    function fetchAst(uri:String, content:String, callback:(lexer:Lexer, parser:Parser, ast:Script)->Void, ?handleError:(err:Any)->Void):Null<Script> {

        final lexer = new Lexer(content);
        lexer.keepOrphanExpressions = true;
        final tokens = lexer.tokenize();

        final lexerErrors = lexer.getErrors();
        if (lexerErrors != null && lexerErrors.length > 0) {
            if (handleError != null) {
                handleError(lexerErrors[0]);
            }
        }

        if (uri == null || !uri.startsWith('file://')) {
            callback(null, null, null);
            return null;
        }
        final filePath = pathFromUri(uri);

        var result:Script = null;

        if (filePath != null && handleFile != null) {
            // File path and file handler provided, which mean we can support
            // imports, either synchronous or asynchronous

            fileContents.set(filePath, content);
            final recordingHandleFile = (path:String, callback:(content:String)->Void) -> {
                handleFile(path, fileContent -> {
                    fileContents.set(Path.normalize(path), fileContent);
                    callback(fileContent);
                });
            };

            var imports = new Imports();
            imports.resolve(filePath, tokens, recordingHandleFile, handleError, (hasErrors, resolvedImports) -> {

                final parser = new Parser(tokens, {
                    rootPath: filePath,
                    path: filePath,
                    imports: resolvedImports,
                    // A file that imports the root back finds it already parsed
                    imported: [Imports.rootImportPath(filePath) => true]
                });

                result = parser.parse();
                result.indentSize = lexer.detectedIndentSize;
                final parseErrors = parser.getErrors();

                if (parseErrors != null && parseErrors.length > 0) {
                    if (handleError != null) {
                        handleError(parseErrors[0]);
                    }
                }

                if (callback != null) {
                    callback(lexer, parser, result);
                }

            });
            return result;
        }

        // No imports handling, simply parse the input
        final parser = new Parser(tokens);

        result = parser.parse();
        result.indentSize = lexer.detectedIndentSize;
        final parseErrors = parser.getErrors();

        if (parseErrors != null && parseErrors.length > 0) {
            if (handleError != null) {
                handleError(parseErrors[0]);
            }
        }

        if (callback != null) {
            callback(lexer, parser, result);
        }

        return result;

    }

    function rangesEqual(a:Range, b:Range):Bool {

        if (a.start.line != b.start.line) return false;
        if (a.start.character != b.start.character) return false;
        if (a.end.line != b.end.line) return false;
        if (a.end.character != b.end.character) return false;
        return true;

    }

    /**
     * Add a diagnostic
     */
    /**
     * Adds a diagnostic to a document.
     * @param kind What the diagnostic is about, in `data.kind`, for code that
     *             needs to know it without reading the message, which may be
     *             translated
     */
    function addDiagnostic(uri:String, pos:Null<loreline.Position>, message:String, severity:DiagnosticSeverity, ?kind:String) {
        final diagnostics = documentDiagnostics.get(uri);
        if (diagnostics == null) return;

        final content = documentContents.get(uri);
        final range = if (pos != null && content != null) {
            // A span of zero units still shows as one, so that the mark is visible
            rangeFromLorelinePosition(pos.length > 0 ? pos : pos.withOffset(content, 0, 1), content);
        } else if (pos != null) {
            {
                start: {line: pos.line - 1, character: pos.column - 1},
                end: {line: pos.line - 1, character: pos.column - 1 + (pos.length > 0 ? pos.length : 1)}
            }
        } else {
            {
                start: {line: 0, character: 0},
                end: {line: 0, character: 0}
            }
        };

        // Prevent duplicates
        for (diag in diagnostics) {
            if (diag.message == message && diag.severity == severity && rangesEqual(diag.range, range)) return;
        }

        final diagnostic:Diagnostic = {
            range: range,
            severity: severity,
            source: "loreline",
            message: message
        };
        if (kind != null) diagnostic.data = {kind: kind};
        diagnostics.push(diagnostic);
    }

    /**
     * Publish diagnostics
     */
    function publishDiagnostics(uri:String) {
        final diagnostics = documentDiagnostics.get(uri);
        if (diagnostics == null) return;

        final params = {
            uri: uri,
            diagnostics: diagnostics
        };

        // Send notification
        final notification:NotificationMessage = {
            jsonrpc: "2.0",
            method: "textDocument/publishDiagnostics",
            params: params
        };

        onNotification(notification);
    }

    /**
     * Validate document semantics
     */
    function validateDocument(uri:String, ast:Script) {
        // TODO: Add semantic validation:
        // - Check for undefined beats in transitions
        // - Check for undefined characters in dialogues
        // - Check for undefined variables in interpolations
        // - Check for undefined tags
    }

    /**
     * Handle completion request
     */
    function handleCompletion(params:{
        textDocument:TextDocumentIdentifier,
        position:Position,
        ?context:CompletionContext
    }):Array<CompletionItem> {

        final uri = params.textDocument.uri;

        final content = documentContents.get(uri);
        if (content == null) return [];

        final lorelinePos = toLorelinePosition(params.position, content);

        // A key of the metadata block, where its name is written, read from
        // the text: the script doesn't parse while a key is being typed
        if (params.context?.triggerCharacter == null) {
            final metadataKeys = metadataKeyCompletions(content, lorelinePos);
            if (metadataKeys != null) {
                return metadataKeys;
            }
        }

        final ast = documents.get(uri);
        if (ast == null) return [];

        // A new name is being written: no existing name is what it should be
        if (isDeclaringName(linePrefix(content, lorelinePos.offset))) {
            return [];
        }

        final lens = new Lens(ast);

        var node = lens.getNodeAtPosition(lorelinePos);
        final beforeNode = lens.getClosestNodeAtOrBeforePosition(lorelinePos);

        if (node == null) {
            node = beforeNode;
        }
        else {
            switch HxType.getClass(node) {
                case NStringPart | NStringLiteral | NCharacterDecl | NStateDecl | NLiteral | NObjectField | NAccess | NArrayAccess:
                case _:
                    node = beforeNode;
            }
        }

        if (node == null) {
            return [];
        }

        final inString = switch HxType.getClass(node) {
            case NStringPart | NStringLiteral: true;
            case _: false;
        }

        // Check if triggered by a special character
        var triggerCharacter = params.context?.triggerCharacter;
        if (triggerCharacter == null && params.context?.triggerKind == CompletionTriggerKind.Invoked && lorelinePos.offset > 0) {
            final charBefore = content.uCharAt(lorelinePos.offset - 1);
            switch charBefore {
                case "." | "<" | '"':
                    triggerCharacter = charBefore;
                case _:
            }
        }

        // Compute the replacement range once per call, used by every completion
        // item's textEdit. If a trigger character fired this completion, the
        // trigger is already committed at the cursor and new text should be
        // inserted (zero-width range). Otherwise (Ctrl+Space) the user may have
        // typed a partial identifier we want to replace on accept.
        final cursorLspPos = fromLorelinePosition(lorelinePos);
        var replacementRange:Range = { start: cursorLspPos, end: cursorLspPos };
        if (triggerCharacter == null) {
            final prevText = content.uSubstr(0, lorelinePos.offset);
            final before = nameBefore(prevText);
            if (before != null && before.gapLength == 0) {
                final identLen = before.nameLength;
                final startPos = fromLorelinePosition(lorelinePos.withOffset(content, -identLen));
                replacementRange = { start: startPos, end: cursorLspPos };
            }
        }

        if (params.context != null && triggerCharacter != null) {
            switch triggerCharacter {
                case ".": // Field access completion
                    var prevText = content.uSubstr(0, lorelinePos.offset);
                    var dotIdx = prevText.lastIndexOf(".");
                    if (dotIdx < 0) return [];
                    prevText = prevText.uSubstr(0, dotIdx);
                    var resolved:Node = null;
                    final before = nameBefore(prevText);
                    if (before != null) {
                        final beforePos = lorelinePos.withOffset(content, -before.totalLength - 1);
                        final beforeNode = lens.getNodeAtPosition(beforePos);
                        if (beforeNode == null) {
                            return [];
                        }
                        else if (beforeNode is NAccess) {
                            final access:NAccess = cast beforeNode;
                            resolved = lens.resolveAccess(access);
                        }
                        else if (beforeNode is NFunctionDecl) {
                            final func:NFunctionDecl = cast beforeNode;
                            final lorscriptCompletion = lens.getLorscriptCompletion(func, lorelinePos);
                            if (lorscriptCompletion?.completion != null) {
                                switch lorscriptCompletion.completion.expr.e {
                                    case EField(e, f):
                                        switch lorscriptCompletion.completion.t {
                                            case TAnon(fields):
                                                final items:Array<CompletionItem> = [];
                                                for (field in fields) {
                                                    items.push({
                                                        label: field.name,
                                                        kind: CompletionItemKind.Field,
                                                        detail: I18n.t('Object field'),
                                                        insertText: field.name,
                                                        insertTextMode: AsIs,
                                                        insertTextFormat: PlainText,
                                                        documentation: '',
                                                        textEdit: makeTextEdit(replacementRange, field.name)
                                                    });
                                                }
                                                return items;
                                            case _:
                                        }
                                    case _:
                                }
                            }
                            resolved = lens.resolveAccessInFunction(func, beforePos);
                        }
                        else {
                            return [];
                        }
                    }
                    else if (RE_ARRAY_ACCESS_BEFORE.match(prevText)) {
                        final beforePos = lorelinePos.withOffset(content, -RE_ARRAY_ACCESS_BEFORE.matched(0).uLength() - 1);
                        final beforeNode = lens.getNodeAtPosition(beforePos);
                        if (beforeNode == null) {
                            return [];
                        }
                        else if (beforeNode is NArrayAccess) {
                            final access:NArrayAccess = cast beforeNode;
                            resolved = lens.resolveArrayAccess(access);
                        }
                        else {
                            return [];
                        }
                    }

                    if (resolved == null) {
                        return [];
                    }

                    if (resolved is NObjectField) {
                        resolved = (cast resolved:NObjectField).value;
                    }

                    switch HxType.getClass(resolved) {
                        case NCharacterDecl:
                            final character:NCharacterDecl = cast resolved;
                            final items:Array<CompletionItem> = [];
                            for (field in character.fields) {
                                items.push({
                                    label: field.name,
                                    kind: CompletionItemKind.Property,
                                    detail: I18n.t('Character property'),
                                    insertText: field.name,
                                    insertTextMode: AsIs,
                                    insertTextFormat: PlainText,
                                    documentation: documentationForNode(field),
                                    textEdit: makeTextEdit(replacementRange, field.name)
                                });
                            }
                            return items;

                        case NMetadataDecl:
                            final metadata:NMetadataDecl = cast resolved;
                            final items:Array<CompletionItem> = [];
                            for (field in metadata.fields) {
                                items.push({
                                    label: field.name,
                                    kind: CompletionItemKind.Property,
                                    detail: I18n.t('Metadata'),
                                    insertText: field.name,
                                    insertTextMode: AsIs,
                                    insertTextFormat: PlainText,
                                    documentation: documentationForNode(field),
                                    textEdit: makeTextEdit(replacementRange, field.name)
                                });
                            }
                            return items;

                        case NLiteral:
                            final literal:NLiteral = cast resolved;
                            switch literal.literalType {
                                case Number:
                                case Boolean:
                                case Null:
                                case Array:
                                case Object(_):
                                    final fields:Array<NObjectField> = cast literal.value;
                                    final items:Array<CompletionItem> = [];
                                    for (field in fields) {
                                        items.push({
                                            label: field.name,
                                            kind: CompletionItemKind.Field,
                                            detail: I18n.t('Object field'),
                                            insertText: field.name,
                                            insertTextMode: AsIs,
                                            insertTextFormat: PlainText,
                                            documentation: documentationForNode(field),
                                            textEdit: makeTextEdit(replacementRange, field.name)
                                        });
                                    }
                                    return items;
                            }
                    }

                    return [];

                case "$": // Variable interpolation completion
                    return getVariableCompletions(lens, node, lorelinePos, replacementRange);

                case "<": // Tag completion
                    if (node is NFunctionDecl) {
                        return [];
                    }
                    return getTagCompletions(lens, replacementRange);

                case "\"": // String completion - no special handling needed
                    return [];

                case " ": // Transition or when strategy?
                    final prevText = content.uSubstr(0, lorelinePos.offset);
                    if (isWhenStrategyBefore(prevText)) {
                        return getWhenStrategyCompletions(lens, replacementRange);
                    }
                    final isTransition = RE_ARROW_BEFORE.match(prevText);
                    if (isTransition) {
                        final matchedLen = RE_ARROW_BEFORE.matched(0).uLength();
                        final trimmedLen = RE_ARROW_BEFORE.matched(0).rtrim().uLength();
                        final spaces = matchedLen != trimmedLen ? RE_ARROW_BEFORE.matched(0).uSubstr(trimmedLen, matchedLen - trimmedLen) : '';
                        return getBeatCompletions(lens, node, spaces.uLength() > 0 ? '' : ' ', replacementRange);
                    }
                    return [];

                case _:
                    return [];
            }
        }

        // Check for CTRL + Space completion
        if (params.context != null && params.context.triggerKind == CompletionTriggerKind.Invoked) {

            // Get more info of the position
            final prevText = content.uSubstr(0, lorelinePos.offset);
            final isTransition = RE_ARROW_BEFORE.match(prevText);
            if (isTransition) {
                final matchedLen = RE_ARROW_BEFORE.matched(0).uLength();
                final trimmedLen = RE_ARROW_BEFORE.matched(0).rtrim().uLength();
                final spaces = matchedLen != trimmedLen ? RE_ARROW_BEFORE.matched(0).uSubstr(trimmedLen, matchedLen - trimmedLen) : '';
                return getBeatCompletions(lens, node, spaces.uLength() > 0 ? '' : ' ', replacementRange);
            }

            // After `when`, only strategies make sense
            if (isWhenStrategyBefore(prevText)) {
                return getWhenStrategyCompletions(lens, replacementRange);
            }

            // Return all available completions for CTRL + Space
            final items:Array<CompletionItem> = [];

            // Add locals completion (if inside a function)
            if (node is NFunctionDecl) {
                final func:NFunctionDecl = cast node;
                final lorscriptCompletion = lens.getLorscriptCompletion(func, lorelinePos);
                if (lorscriptCompletion?.locals != null) {
                    for (name => local in lorscriptCompletion.locals) {
                        items.push({
                            label: name,
                            kind: CompletionItemKind.Field,
                            detail: I18n.t('Local variable'),
                            data: {kind: 'local'},
                            insertText: name,
                            insertTextMode: AsIs,
                            insertTextFormat: PlainText,
                            documentation: '',
                            textEdit: makeTextEdit(replacementRange, name)
                        });
                    }
                }
            }

            // Add state field completions
            for (field in lens.getVisibleStateFields(node)) {
                items.push({
                    label: field.name,
                    kind: CompletionItemKind.Variable,
                    detail: I18n.t('State field'),
                    data: {kind: 'stateField'},
                    insertText: field.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(field),
                    textEdit: makeTextEdit(replacementRange, field.name)
                });
            }

            // Add character completions
            for (character in lens.getVisibleCharacters()) {
                items.push({
                    label: character.name,
                    kind: CompletionItemKind.Struct,
                    detail: I18n.t('Character'),
                    data: {kind: 'character'},
                    insertText: character.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(character),
                    textEdit: makeTextEdit(replacementRange, character.name)
                });
            }

            // Add function completions
            for (func in lens.getVisibleFunctions()) {
                if (func.name != null) {
                    items.push({
                        label: func.name,
                        kind: CompletionItemKind.Function,
                        detail: I18n.t('Function'),
                        data: {kind: 'function'},
                        insertText: func.name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: documentationForNode(func),
                        textEdit: makeTextEdit(replacementRange, func.name)
                    });
                }
            }

            if (!(node is NFunctionDecl)) {
                addMetadataCompletion(lens, items, replacementRange);
            }

            // Add word operators inside expressions and conditions (not in text)
            if ((node is NExpr && !(node is NStringLiteral) && !(node is NStringPart)) || node is NIfStatement) {
                for (op in WORD_OPERATORS) {
                    items.push({
                        label: op.word,
                        kind: CompletionItemKind.Keyword,
                        detail: I18n.t('Operator, like {symbol}', {symbol: op.symbol}),
                        insertText: op.word,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: operatorDoc(op.word),
                        textEdit: makeTextEdit(replacementRange, op.word)
                    });
                }
            }

            // Add beat completions
            if (!(node is NFunctionDecl)) {
                for (beat in lens.getVisibleBeats(node)) {
                    items.push({
                        label: beat.name,
                        kind: CompletionItemKind.Class,
                        detail: I18n.t('Beat'),
                        insertText: beat.name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: documentationForNode(beat),
                        textEdit: makeTextEdit(replacementRange, beat.name)
                    });
                }
            }

            return items;
        }

        return [];
    }

    /**
     * The known keys of the metadata block not written yet, when the cursor
     * is where the name of a field of the block goes, or null elsewhere.
     */
    function metadataKeyCompletions(content:String, lorelinePos:loreline.Position):Null<Array<CompletionItem>> {

        final offset = lorelinePos.offset;
        final prefix = linePrefix(content, offset);
        if (!RE_FIELD_NAME_START.match(prefix)) return null;

        // The part of the name already typed is replaced
        final typed = prefix.ltrim().uLength();
        final replacementRange:Range = {
            start: fromLorelinePosition(lorelinePos.withOffset(content, -typed)),
            end: fromLorelinePosition(lorelinePos)
        };

        // The lines above, inside the block, up to the line opening it
        final lines = content.uSubstr(0, offset - prefix.uLength()).replace('\r', '').split('\n');
        final written:Map<String, Bool> = new Map();
        var i = lines.length - 1;
        while (i >= 0) {
            final line = lines[i];
            if (line.trim() == '' || line.startsWith(' ') || line.startsWith('\t')) {
                if (RE_FIELD_LINE.match(line)) written.set(RE_FIELD_LINE.matched(1), true);
                i--;
                continue;
            }
            if (!RE_METADATA_LINE.match(line)) return null;
            break;
        }
        if (i < 0) return null;

        final items:Array<CompletionItem> = [];
        for (known in MetadataKeys.KEYS) {
            if (written.exists(known.key)) continue;
            items.push({
                label: known.key,
                kind: CompletionItemKind.Property,
                detail: I18n.t('Metadata'),
                insertText: known.key + ': ',
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: {kind: MarkupKind.Markdown, value: known.meaning()},
                textEdit: makeTextEdit(replacementRange, known.key + ': ')
            });
        }
        return items;

    }

    /** The text of a line before the given offset */
    static function linePrefix(content:String, offset:Int):String {
        var start = offset;
        while (start > 0 && content.uCharCodeAt(start - 1) != "\n".code) start--;
        return content.uSubstr(start, offset - start);
    }

    /**
     * Whether the text before the cursor, on its line, ends on the name of
     * something being declared: a beat, a character or a function, or one of
     * the parameters of a beat or a function (not their default values).
     */
    static function isDeclaringName(prefix:String):Bool {
        var text = prefix.ltrim();
        if (text.startsWith("public ")) text = text.uSubstr(7).ltrim();
        var keyword:Null<String> = null;
        for (candidate in ["beat", "character", "function"]) {
            if (text.startsWith(candidate + " ") || text.startsWith(candidate + "\t")) keyword = candidate;
        }
        if (keyword == null) return false;
        text = text.uSubstr(keyword.length).ltrim();
        final nameEnd = Identifiers.nameEnd(text, 0);
        if (nameEnd == text.uLength()) return true;
        if (keyword == "character" || text.uCharCodeAt(nameEnd) != "(".code) return false;
        final params = text.uSubstr(nameEnd + 1);
        if (params.indexOf(")") != -1) return false;
        final last = params.uSubstr(params.uLastIndexOf(",") + 1).ltrim();
        return Identifiers.nameEnd(last, 0) == last.uLength();
    }

    function getVariableCompletions(lens:Lens, node:Node, lorelinePos:loreline.Position, replacementRange:Range):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];

        // Add locals completion (if inside a function)
        if (node is NFunctionDecl) {
            final func:NFunctionDecl = cast node;
            final lorscriptCompletion = lens.getLorscriptCompletion(func, lorelinePos);
            if (lorscriptCompletion?.locals != null) {
                for (name => local in lorscriptCompletion.locals) {
                    items.push({
                        label: name,
                        kind: CompletionItemKind.Field,
                        detail: I18n.t('Local variable'),
                        data: {kind: 'local'},
                        insertText: name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: '',
                        textEdit: makeTextEdit(replacementRange, name)
                    });
                }
            }
        }

        // Add state fields
        for (field in lens.getVisibleStateFields(node)) {
            items.push({
                label: field.name,
                kind: CompletionItemKind.Variable,
                detail: I18n.t('State field'),
                data: {kind: 'stateField'},
                insertText: field.name,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: documentationForNode(field),
                textEdit: makeTextEdit(replacementRange, field.name)
            });
        }

        // Add characters (can be used in interpolation)
        for (character in lens.getVisibleCharacters()) {
            items.push({
                label: character.name,
                kind: CompletionItemKind.Class,
                detail: I18n.t('Character'),
                data: {kind: 'character'},
                insertText: character.name,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: documentationForNode(character),
                textEdit: makeTextEdit(replacementRange, character.name)
            });
        }

        // Add function completions
        for (func in lens.getVisibleFunctions()) {
            if (func.name != null) {
                items.push({
                    label: func.name,
                    kind: CompletionItemKind.Function,
                    detail: I18n.t('Function'),
                    data: {kind: 'function'},
                    insertText: func.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(func),
                    textEdit: makeTextEdit(replacementRange, func.name)
                });
            }
        }

        addMetadataCompletion(lens, items, replacementRange);

        return items;
    }

    /** The metadata of the story, to read in the script, when it has a block */
    function addMetadataCompletion(lens:Lens, items:Array<CompletionItem>, replacementRange:Range):Void {

        final metadata = lens.getMetadata();
        if (metadata == null) return;
        items.push({
            label: 'metadata',
            kind: CompletionItemKind.Module,
            detail: I18n.t('Metadata'),
            insertText: 'metadata',
            insertTextMode: AsIs,
            insertTextFormat: PlainText,
            documentation: documentationForNode(metadata),
            textEdit: makeTextEdit(replacementRange, 'metadata')
        });

    }

    /**
     * Get completion items for beats in scope
     */
    function getBeatCompletions(lens:Lens, node:Node, insert:String, replacementRange:Range):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];

        // Add state fields
        for (beat in lens.getVisibleBeats(node)) {
            final newText = (insert ?? '') + beat.name;
            items.push({
                label: beat.name,
                kind: CompletionItemKind.Class,
                detail: I18n.t('Beat'),
                insertText: newText,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: documentationForNode(beat),
                textEdit: makeTextEdit(replacementRange, newText)
            });
        }

        return items;
    }

    /**
     * Get completion items for tags based on existing tags in the script
     */
    function getTagCompletions(lens:Lens, replacementRange:Range):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];
        final counts = lens.countTags();

        for (tag in lens.getAllTags()) {
            final uses = counts.get(tag);
            items.push({
                label: tag,
                kind: CompletionItemKind.Enum,
                detail: I18n.t('Tag'),
                insertText: tag,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: I18n.count(uses, 'Used {n} time', 'Used {n} times'),
                textEdit: makeTextEdit(replacementRange, tag)
            });
        }

        return items;
    }

    /**
     * Handle definition request
     */
    function handleDefinition(params:{
        textDocument:TextDocumentIdentifier,
        position:Position
    }):Array<LocationLink> {
        final result:Array<LocationLink> = [];

        final uri = params.textDocument.uri;

        final ast = documents.get(uri);
        if (ast == null) return result;

        final content = documentContents.get(uri);
        final lorelinePos = toLorelinePosition(params.position, content);

        final lens = new Lens(ast);
        var node = lens.getNodeAtPosition(lorelinePos);

        if (node is NLiteral) {
            // The access holding this literal, if any. A plain loop: the C# target
            // generates invalid code for a break inside a switch inside a do/while.
            var parent = lens.getParentNode(node);
            while (parent != null) {
                final parentClass = HxType.getClass(parent);
                if (parentClass == NAccess || parentClass == NArrayAccess) {
                    node = parent;
                    break;
                }
                parent = lens.getParentNode(parent);
            }
        }

        if (node != null) {
            switch HxType.getClass(node) {

                case NAccess:
                    final access:NAccess = cast node;

                    // Beat parameter usage: jump to the parameter name
                    final beatParam = lens.findBeatParamFromAccess(access);
                    if (beatParam != null) {
                        final target = resolveNodeTarget(uri, beatParam.beat, lens);
                        result.push({
                            targetUri: target.uri,
                            targetRange: rangeFromLorelinePosition(beatParam.param.namePos, target.content),
                            targetSelectionRange: rangeFromLorelinePosition(beatParam.param.namePos, target.content),
                            originSelectionRange: rangeFromLorelinePosition(access.pos, content)
                        });
                        return result;
                    }

                    final resolved = lens.resolveAccess(access);
                    if (resolved != null) {
                        final peekNode:Node = switch HxType.getClass(resolved) {
                            case NObjectField: cast (lens.getFirstParentOfType(resolved, NCharacterDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NStateDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NMetadataDecl):Node) ?? resolved;
                            case _: resolved;
                        }
                        final target = resolveNodeTarget(uri, resolved, lens);
                        result.push({
                            targetUri: target.uri,
                            targetRange: rangeFromLorelinePosition(peekNode.pos, target.content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(resolved.pos, target.content), target.content),
                            originSelectionRange: rangeFromLorelinePosition(access.pos, content)
                        });
                    }

                case NArrayAccess:
                    final access:NArrayAccess = cast node;
                    final resolved = lens.resolveArrayAccess(access);
                    if (resolved != null) {
                        final peekNode:Node = switch HxType.getClass(resolved) {
                            case NObjectField: cast (lens.getFirstParentOfType(resolved, NCharacterDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NStateDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NMetadataDecl):Node) ?? resolved;
                            case _: resolved;
                        }
                        final target = resolveNodeTarget(uri, resolved, lens);
                        result.push({
                            targetUri: target.uri,
                            targetRange: rangeFromLorelinePosition(peekNode.pos, target.content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(resolved.pos, target.content), target.content),
                            originSelectionRange: rangeFromLorelinePosition(access.pos, content)
                        });
                    }

                case NTransition:
                    final transition:NTransition = cast node;
                    final beatDecl = lens.findBeatFromTransition(transition);
                    if (beatDecl != null) {
                        // Create a location link with more detailed targeting
                        final target = resolveNodeTarget(uri, beatDecl, lens);
                        result.push({
                            // The document containing the target
                            targetUri: target.uri,
                            // Full range of the beat declaration
                            targetRange: rangeFromLorelinePosition(beatDecl.pos, target.content),
                            // More precise range for the beat name
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, target.content), target.content),
                            // Range of the transition reference in the source
                            originSelectionRange: rangeFromLorelinePosition(transition.targetPos, content)
                        });
                    }

                case NInsertion:
                    final insertion:NInsertion = cast node;
                    final beatDecl = lens.findBeatFromInsertion(insertion);
                    if (beatDecl != null) {
                        // Create a location link with more detailed targeting
                        final target = resolveNodeTarget(uri, beatDecl, lens);
                        result.push({
                            // The document containing the target
                            targetUri: target.uri,
                            // Full range of the beat declaration
                            targetRange: rangeFromLorelinePosition(beatDecl.pos, target.content),
                            // More precise range for the beat name
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, target.content), target.content),
                            // Range of the insertion reference in the source
                            originSelectionRange: rangeFromLorelinePosition(insertion.targetPos, content)
                        });
                    }

                case NDialogueStatement:
                    final dialogue:NDialogueStatement = cast node;
                    final characterDecl = lens.findCharacterFromDialogue(dialogue);
                    if (characterDecl != null) {
                        // Create a location link for the character definition
                        final target = resolveNodeTarget(uri, characterDecl, lens);
                        result.push({
                            targetUri: target.uri,
                            targetRange: rangeFromLorelinePosition(characterDecl.pos, target.content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(characterDecl.pos, target.content), target.content),
                            originSelectionRange: rangeFromLorelinePosition(dialogue.characterPos, content)
                        });
                    }

                case NImportStatement:
                    final importNode:NImportStatement = cast node;
                    result.push({
                        targetUri: resolveImportedUri(uri, importNode, lens),
                        targetRange: rangeFromLorelinePosition(new loreline.Position(1, 1, 0, 0), ''),
                        targetSelectionRange: rangeFromLorelinePosition(new loreline.Position(1, 1, 0, 0), '')
                    });
            }
        }

        return result;
    }

    /**
     * The document holding a node, and its text: the requested document, or the
     * file imported (possibly through other imports) that the node comes from.
     */
    function resolveNodeTarget(uri:String, node:Node, lens:Lens):{uri:String, content:String} {
        final rootPath = pathFromUri(uri);
        if (rootPath == null) {
            return { uri: uri, content: documentContents.get(uri) };
        }
        final path = lens.getNodeFilePath(node, rootPath);
        if (path == rootPath) {
            return { uri: uri, content: documentContents.get(uri) };
        }
        final targetUri = uriForPath(path);
        return {
            uri: targetUri,
            content: fileContents.get(path) ?? documentContents.get(targetUri) ?? ""
        };
    }

    /**
     * The document an import statement brings in, resolved from the folder of
     * the file holding that statement.
     */
    function resolveImportedUri(uri:String, importNode:NImportStatement, lens:Lens):String {
        final rootPath = pathFromUri(uri);
        if (rootPath == null) return uri;
        var importPath = switch importNode.path.parts[0].partType {
            case Raw(text): text;
            case _: "";
        }
        if (!Path.isAbsolute(importPath)) {
            importPath = Path.join([Path.directory(lens.getNodeFilePath(importNode, rootPath)), importPath]);
        }
        importPath = Path.normalize(importPath);
        if (!Imports.isLorFilePath(importPath)) {
            importPath += Imports.lorExtension(rootPath);
        }
        return uriForPath(importPath);
    }

    /**
     * The URI of a file for the client: the one it sent if it has opened that file,
     * so that it does not see another spelling of the same file (percent-encoding
     * differs between clients), otherwise one built from the path.
     */
    function uriForPath(path:String):String {
        for (openUri in openDocuments.keys()) {
            if (pathFromUri(openUri) == path) return openUri;
        }
        return uriFromPath(path);
    }

    function makeDoubleQuotedTextHover(literal:NStringLiteral, lens:Lens, uri:DocumentUri, description:Array<String>, content:String, part:NStringPart, ?pos:loreline.Position):Hover {

        var kind = I18n.t('Text');
        var name = null;
        var title:Null<String> = null;

        final parent = lens.getParentNode(literal);
        var onceOption:NChoiceOption = null;
        if (parent != null) {
            switch HxType.getClass(parent) {
                case NChoiceOption:
                    kind = I18n.t('Choice option');
                    final choiceOpt:NChoiceOption = cast parent;
                    title = optionTitle(choiceOpt, uri, lens);
                    if (choiceOpt.once) onceOption = choiceOpt;
                case NDialogueStatement:
                    kind = I18n.t('Dialogue');
                    final characterDecl = lens.findCharacterFromDialogue(cast parent);
                    if (characterDecl != null) {
                        name = characterLink(characterDecl, uri, lens);
                    }
                case _:
            }
        }

        var hoverPos = pos;
        if (onceOption != null) {
            final endPos = hoverPos ?? part.pos;
            hoverPos = new loreline.Position(onceOption.pos.line, onceOption.pos.column, onceOption.pos.offset,
                endPos.offset - onceOption.pos.offset + endPos.length);
        }
        return makeHover(title ?? hoverTitle(kind, name != null ? I18n.t('of {name}', {name: name}) : null), description, content, part, hoverPos);

    }

    function makeUnquotedTextHover(literal:NStringLiteral, lens:Lens, uri:DocumentUri, cursorLorelinePos:loreline.Position, description:Array<String>, content:String, part:NStringPart, ?pos:loreline.Position):Hover {

        var spaceOffset = 0;
        if (pos == null) {
            pos = part.pos;
        }
        else {
            spaceOffset = pos.offset - part.pos.offset;
        }

        var kind = I18n.t('Text');
        var name = null;
        var title:Null<String> = null;

        final parent = lens.getParentNode(literal);
        var onceOption:NChoiceOption = null;
        if (parent != null) {
            switch HxType.getClass(parent) {
                case NChoiceOption:
                    kind = I18n.t('Choice option');
                    final choiceOpt:NChoiceOption = cast parent;
                    title = optionTitle(choiceOpt, uri, lens);
                    if (choiceOpt.once) onceOption = choiceOpt;
                case NDialogueStatement:
                    kind = I18n.t('Dialogue');
                    final characterDecl = lens.findCharacterFromDialogue(cast parent);
                    if (characterDecl != null) {
                        name = characterLink(characterDecl, uri, lens);
                    }
                case _:
            }
        }

        inline function extendForOnce(hoverPos:loreline.Position):loreline.Position {
            if (onceOption != null) {
                return new loreline.Position(onceOption.pos.line, onceOption.pos.column, onceOption.pos.offset,
                    hoverPos.offset - onceOption.pos.offset + hoverPos.length);
            }
            return hoverPos;
        }

        switch part.partType {
            case Raw(text):
                final offset = cursorLorelinePos.offset - pos.offset;
                var first = true;
                for (sub in extractTextSectionsExcludingComments(text)) {
                    if (offset >= sub.offset && offset < sub.offset + sub.length - (first ? spaceOffset : 0)) {
                        return makeHover(title ?? hoverTitle(kind, name != null ? I18n.t('of {name}', {name: name}) : null), description, content, part, extendForOnce(pos.withOffset(content, sub.offset - (first ? 0 : spaceOffset), sub.length - (first ? spaceOffset : 0))));
                    }
                    first = false;
                }
                return null;
            case _:
                return makeHover(title ?? hoverTitle(kind, name != null ? I18n.t('of {name}', {name: name}) : null), description, content, part, extendForOnce(pos));
        }

    }

    function makeHover(header:Null<String>, description:Array<String>, content:String, node:Node, ?pos:loreline.Position):Hover {

        return makeSectionsHover(header, description != null && description.length > 0 ? [description.join("\n")] : [], content, node, pos);

    }

    /**
     * A hover made of its header (see hoverHeader), then sections set apart
     * from each other (the doc, facts, uses). Empty sections are left out.
     */
    function makeSectionsHover(header:Null<String>, sections:Array<String>, content:String, node:Node, ?pos:loreline.Position):Hover {

        final parts:Array<String> = [];

        if (header != null) {
            parts.push(header);
        }

        for (section in sections) {
            if (section != null && section.trim().length > 0) {
                parts.push(section);
            }
        }

        return {
            contents: {
                kind: MarkupKind.Markdown,
                value: parts.join("\n\n---\n\n")
            },
            range: rangeFromLorelinePosition(pos ?? node.pos, content)
        }

    }

    /**
     * Handle hover request
     */
    function handleHover(params:{
        textDocument:TextDocumentIdentifier,
        position:Position
    }):Null<Hover> {
        final uri = params.textDocument.uri;

        final ast = documents.get(uri);
        if (ast == null) return null;

        final content = documentContents.get(uri);
        final lorelinePos = toLorelinePosition(params.position, content);

        final lens = new Lens(ast);
        final node = lens.getNodeAtPosition(lorelinePos);

        if (node != null) {
            return makeNodeHover(lorelinePos, lens, uri, content, node);
        }

        return null;
    }

    function makeNodeHover(lorelinePos:loreline.Position, lens:Lens, uri:DocumentUri, content:String, node:Node):Null<Hover> {

        // Parameter hint when hovering an argument of a call,
        // beat call, transition or insertion
        final callArg = lens.findCallArgument(node);
        if (callArg != null) {
            final argHover = makeCallArgumentHover(callArg.owner, callArg.index, lens, uri, content, node);
            if (argHover != null) return argHover;
        }

        // Hovering a constant string target of a dynamic beat
        // call/transition/insertion shows the resolved beat
        final constTargetBeat = findConstantStringTargetBeat(node, lens);
        if (constTargetBeat != null) {
            return makeBeatDeclHover(constTargetBeat, uri, content, lens, node);
        }

        switch HxType.getClass(node) {
            case NBeatDecl:
                final beatDecl:NBeatDecl = cast node;
                // Parameter hover when pointing at a name in the declaration signature
                if (beatDecl.params != null) {
                    for (param in beatDecl.params) {
                        if (param.namePos != null && param.namePos.length > 0 &&
                            lorelinePos.offset >= param.namePos.offset &&
                            lorelinePos.offset <= param.namePos.offset + param.namePos.length) {
                            return makeBeatParamHover(param, beatDecl, uri, content, lens, beatDecl, param.namePos);
                        }
                    }
                }
                return makeBeatDeclHover(beatDecl, uri, content, lens);
            case NStateDecl:
                return makeStateDeclHover(cast node, uri, content, lens);
            case NMetadataDecl:
                return makeMetadataDeclHover(cast node, uri, content, lens);
            case NCharacterDecl:
                return makeCharacterDeclHover(cast node, uri, content, lens);
            case NChoiceStatement:
                return makeChoiceHover(cast node, content);
            case NWhenStatement:
                return makeWhenHover(cast node, content);
            case NWhenRule:
                return makeWhenRuleHover(cast node, content);
            case NImportStatement:
                return makeImportHover(cast node, content);
            case NFunctionDecl:
                return makeFunctionHover(cast node, uri, content, lens, lorelinePos);
            case NTransition:
                final transition:NTransition = cast node;
                if (transition.target == '.') {
                    return makeHover(hoverTitle(I18n.t('End')), hoverDescriptionForNode(cast node), content, node);
                }
                else if (transition.target == '_') {
                    return makeHover(hoverTitle(I18n.t('Root')), hoverDescriptionForNode(cast node), content, node);
                }
                else {
                    final beat = lens.findBeatFromTransition(transition);
                    if (beat != null) {
                        return makeBeatDeclHover(beat, uri, content, lens, node);
                    }
                    else {
                        return makeHover(hoverTitle(I18n.t('Transition')), hoverDescriptionForNode(cast node), content, node);
                    }
                }
            case NInsertion:
                final insertion:NInsertion = cast node;
                final beat = lens.findBeatFromInsertion(insertion);
                if (beat != null) {
                    return makeBeatDeclHover(beat, uri, content, lens, node);
                }
                else {
                    return makeHover(hoverTitle(I18n.t('Insertion')), hoverDescriptionForNode(cast node), content, node);
                }
            case NBeatCall:
                // Dynamic beat call: target is resolved at runtime
                return makeHover(hoverTitle(I18n.t('Beat call')), hoverDescriptionForNode(cast node), content, node);
            case NObjectField:
                return makeObjectFieldHover(cast node, uri, content, lens);
            case NAccess:
                var access:NAccess = cast node;
                var parent = lens.getParentNode(access);
                if (parent is NCall) {
                    final resolved = lens.resolveAccess(access);
                    if (resolved is NBeatDecl) {
                        return makeBeatDeclHover(cast resolved, uri, content, lens, access);
                    }
                }
                return makeAccessHover(access, uri, content, lens);
            case NArrayAccess:
                var access:NArrayAccess = cast node;
                var parent = lens.getParentNode(access);
                return makeArrayAccessHover(access, content, lens);

            case NLiteral:
                final literal:NLiteral = cast node;
                switch literal.literalType {
                    case Number:
                        return makeHover(hoverTitle(I18n.t('Number')), hoverDescriptionForNode(literal), content, literal);
                    case Boolean:
                        return makeHover(hoverTitle(I18n.t('Boolean')), hoverDescriptionForNode(literal), content, literal);
                    case Null:
                        return makeHover(hoverTitle(I18n.t('Null')), hoverDescriptionForNode(literal), content, literal);
                    case Array:
                        return makeHover(hoverTitle(I18n.t('Array')), hoverDescriptionForNode(literal), content, literal);
                    case Object(style):
                        return makeHover(hoverTitle(I18n.t('Object')), hoverDescriptionForNode(literal), content, literal);
                }
            case NUnary | NBinary:
                // Hovering a word operator (the operands have their own nodes)
                final op = wordOperatorOf(cast node);
                if (op != null) {
                    return makeHover(hoverName(op.word, I18n.t('operator')), [operatorDoc(op.word)], content, node);
                }
                return makeHover(hoverTitle(I18n.t('Expression')), hoverDescriptionForNode(cast node), content, node);
            case NExpr | NAssign:
                return makeHover(hoverTitle(I18n.t('Expression')), hoverDescriptionForNode(cast node), content, node);
            case NIfStatement:
                return makeHover(hoverTitle(I18n.t('Condition')), null, content, node);
            case NAlternative:
                final alt:NAlternative = cast node;
                return makeHover(hoverTitle(I18n.t('Alternative'), alt.mode.toString().toLowerCase()), null, content, node);
            case NDialogueStatement:
                final dialogue:NDialogueStatement = cast node;
                if (dialogue.conditionPos != null &&
                    lorelinePos.offset >= dialogue.conditionPos.offset &&
                    lorelinePos.offset <= dialogue.conditionPos.offset + dialogue.conditionPos.length) {
                    return makeHover(hoverTitle(I18n.t('Condition')), null, content, node, dialogue.conditionPos);
                }
                return makeDialogueStatementHover(dialogue, uri, content, lens);
            case NTextStatement:
                final text:NTextStatement = cast node;
                if (text.conditionPos != null &&
                    lorelinePos.offset >= text.conditionPos.offset &&
                    lorelinePos.offset <= text.conditionPos.offset + text.conditionPos.length) {
                    return makeHover(hoverTitle(I18n.t('Condition')), null, content, node, text.conditionPos);
                }
                return makeHover(hoverTitle(I18n.t('Text')), hoverDescriptionForNode(text), content, node);
            case NChoiceOption:
                final option:NChoiceOption = cast node;
                if (option.conditionPos != null &&
                    lorelinePos.offset >= option.conditionPos.offset &&
                    lorelinePos.offset <= option.conditionPos.offset + option.conditionPos.length) {
                    return makeHover(hoverTitle(I18n.t('Condition')), null, content, node, option.conditionPos);
                }
                return makeHover(optionTitle(option, uri, lens), hoverDescriptionForNode(option), content, node);
            case NStringLiteral:
                return makeHover(hoverTitle(I18n.t('Text')), hoverDescriptionForNode(cast node), content, node);
            case NStringPart:
                var parent = node;
                do {
                    parent = lens.getParentNode(parent);
                }
                while (parent != null);

                final stringPart:NStringPart = cast node;

                switch stringPart.partType {
                    case Raw(text):
                    case Expr(expr):
                        return makeNodeHover(lorelinePos, lens, uri, content, expr);
                    case Tag(closing, expr):
                        return makeHover(hoverTitle(I18n.t('Tag'), '&lt;' + (closing ? '/' : '') + printLoreline(expr) + '&gt;'), hoverDescriptionForNode(expr), content, stringPart);
                }

                final literal = lens.getFirstParentOfType(node, NStringLiteral);

                if (literal != null) {
                    final literalParent = lens.getParentNode(literal);
                    if (literalParent != null && literalParent is NStringPart) {
                        final parentStringPart:NStringPart = cast literalParent;
                        switch parentStringPart.partType {
                            case Raw(text):
                            case Expr(expr):
                                return makeNodeHover(lorelinePos, lens, uri, content, expr);
                            case Tag(closing, expr):
                                return makeHover(hoverTitle(I18n.t('Tag'), '&lt;' + (closing ? '/' : '') + printLoreline(expr) + '&gt;'), hoverDescriptionForNode(expr), content, parentStringPart);
                        }
                    }

                    final partIndex = literal.parts.indexOf(stringPart);
                    if (literal.quotes == Unquoted) {
                        if (partIndex > 0) {
                            // In unquoted strings, we ignore space between leading tags and actual text
                            var keepWhitespace = true;
                            for (i in 0...partIndex) {
                                switch literal.parts[i].partType {
                                    case Raw(text):
                                        if (text.trim().uLength() > 0) {
                                            keepWhitespace = false;
                                            break;
                                        }
                                    case Expr(expr):
                                        keepWhitespace = false;
                                        break;
                                    case Tag(closing, expr):
                                }
                            }
                            if (keepWhitespace) {
                                switch literal.parts[partIndex].partType {
                                    case Raw(text):
                                        final spaces = text.uLength() - text.ltrim().uLength();
                                        if (spaces > 0) {
                                            return makeUnquotedTextHover(literal, lens, uri, lorelinePos, hoverDescriptionForNode(literal.parts[partIndex]), content, stringPart, stringPart.pos.withOffset(content, spaces, stringPart.pos.length - spaces));
                                        }
                                    case _:
                                }
                            }
                        }
                    }
                    else if (literal.quotes == DoubleQuotes) {
                        if (literal.parts.length == 1) {
                            switch literal.parts[0].partType {
                                case Raw(text):
                                    return makeDoubleQuotedTextHover(literal, lens, uri, hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 2));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == 0) {
                            switch literal.parts[0].partType {
                                case Raw(text):
                                    return makeDoubleQuotedTextHover(literal, lens, uri, hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == literal.parts.length - 1) {
                            switch literal.parts[literal.parts.length - 1].partType {
                                case Raw(text):
                                    return makeDoubleQuotedTextHover(literal, lens, uri, hoverDescriptionForNode(literal.parts[literal.parts.length - 1]), content, stringPart, stringPart.pos.withOffset(content, 0, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                    }
                }

                switch stringPart.partType {
                    case Raw(text):
                        return makeUnquotedTextHover(literal, lens, uri, lorelinePos, hoverDescriptionForNode(stringPart), content, stringPart);
                    case Expr(expr):
                    case Tag(closing, expr):
                }
            case _:
        }
        return null;

    }

    /**
     * Word operators, for completion and hover.
     */
    static final WORD_OPERATORS:Array<{word:String, symbol:String}> = [
        {word: 'and', symbol: '&&'},
        {word: 'or', symbol: '||'},
        {word: 'is', symbol: '=='},
        {word: 'is not', symbol: '!='},
        {word: 'not', symbol: '!'}
    ];

    /** What a word operator does, in the language of the tools */
    static function operatorDoc(word:String):String {
        return switch word {
            case 'and': I18n.t('`a and b` is true when both `a` and `b` are true, like `a && b`.');
            case 'or': I18n.t('`a or b` is true when `a` or `b` is true, like `a || b`.');
            case 'is': I18n.t('`a is b` is true when `a` equals `b`, like `a == b`.');
            case 'is not': I18n.t('`a is not b` is true when `a` differs from `b`, like `a != b`. It is always a single operator: to compare with a negation, write `a is (not b)`.');
            case _: I18n.t('`not a` is true when `a` is false, like `!a`. It applies to what follows it directly: `not a is b` reads `(not a) is b`, so write `not (a is b)` to negate a comparison.');
        }
    }

    /**
     * The word operator of an expression, if it is written with one.
     */
    static function wordOperatorOf(node:NExpr):Null<{word:String, symbol:String}> {
        final op:Null<loreline.Lexer.TokenType> = if (node is NBinary) (cast node:NBinary).op else if (node is NUnary) (cast node:NUnary).op else null;
        final word = switch op {
            case OpAnd(true): 'and';
            case OpOr(true): 'or';
            case OpEquals(true): 'is';
            case OpNotEquals(true): 'is not';
            case OpNot(true): 'not';
            case _: null;
        }
        if (word == null) return null;
        for (item in WORD_OPERATORS) {
            if (item.word == word) return item;
        }
        return null;
    }

    /**
     * The title of a hover, for what isn't code: what it is in bold, then
     * the rest in plain text, like **Character field** of Bob.
     */
    static function hoverTitle(kind:String, ?rest:String):String {

        return '**' + kind + '**' + (rest != null && rest.length > 0 ? ' ' + rest : '');

    }

    /**
     * The title of a hover on a name: the name in bold, then what it is in
     * parentheses, like **jitters** (Player field).
     */
    static function hoverName(name:String, ?what:String):String {

        return '**' + name + '**' + (what != null && what.length > 0 ? ' (' + what + ')' : '');

    }

    /**
     * The title of a choice option: its text, as written but without quotes,
     * cut when it gets long, like **Leave Shop** (choice option). A character
     * it names, `$sarah`, shows by its name, with a link to it.
     */
    function optionTitle(option:NChoiceOption, uri:DocumentUri, lens:Lens):String {

        // What the text says, piece by piece: what it shows, and its Markdown
        final pieces:Array<{shown:String, markdown:String}> = [];
        for (part in option.text?.parts ?? []) {
            switch part.partType {
                case Raw(text):
                    pieces.push({shown: text, markdown: null});
                case Expr(expr):
                    final character = expr is NAccess && (cast expr:NAccess).target == null ? lens.resolveAccess(cast expr) : null;
                    if (character is NCharacterDecl) {
                        final name = shownCharacterName(cast character);
                        pieces.push({shown: name, markdown: makePositionLink(markdownText(name), uri, character, lens)});
                    }
                    else {
                        final written = expr is NAccess && (cast expr:NAccess).target == null ? '$' + (cast expr:NAccess).name : '$${' + printLoreline(expr) + '}';
                        pieces.push({shown: written, markdown: null});
                    }
                case Tag(_, _):
            }
        }

        // Up to about fifty characters shown, whole pieces of names
        final limit = 50;
        var shown = 0;
        var markdown = '';
        var cut = false;
        for (piece in pieces) {
            final length = piece.shown.uLength();
            if (shown + length > limit) {
                if (piece.markdown == null) markdown += markdownText(piece.shown.uSubstr(0, limit - shown).rtrim());
                cut = true;
                break;
            }
            markdown += piece.markdown ?? markdownText(piece.shown);
            shown += length;
        }
        markdown = markdown.trim() + (cut ? '…' : '');
        return markdown.length > 0 ? hoverName(markdown, I18n.t('choice option')) : hoverTitle(I18n.t('Choice option'));

    }

    /** Text shown as is in Markdown: its own marks are escaped */
    static function markdownText(text:String):String {

        return ~/([\\`*_\[\]<>#])/g.replace(text, '\\$1');

    }

    /**
     * What a name is, for its title: its type when known, then where it
     * lives, like `boolean, field of Sarah` or `number, in the state`.
     * @param kind `state field`, `field`, `parameter`, `local`
     * @param owner What it belongs to: a character, a beat, a function
     */
    static function hoverWhat(kind:String, ?owner:String, ?type:String):String {

        final hasOwner = owner != null && owner.length > 0;
        final place = switch kind {
            case 'state field': hasOwner ? I18n.t('in the state of {owner}', {owner: owner}) : I18n.t('in the state');
            case 'local': hasOwner ? I18n.t('local in {owner}', {owner: owner}) : I18n.t('local');
            case _: hasOwner ? I18n.t('{kind} of {owner}', {kind: kindText(kind), owner: owner}) : kindText(kind);
        }
        return (type != null && type.length > 0 ? type + ', ' : '') + place;
    }

    /** What a name is, as a hover says it: `public beat`, `field`, `text method`, in the language of the tools */
    public static function kindText(kind:String):String {
        return switch kind {
            case 'beat': I18n.t('beat');
            case 'public beat': I18n.t('public beat');
            case 'character': I18n.t('character');
            case 'function': I18n.t('function');
            case 'function provided by the app': I18n.t('function provided by the app');
            case 'built-in function': I18n.t('built-in function');
            case 'parameter': I18n.t('parameter');
            case 'field': I18n.t('field');
            case 'state field': I18n.t('state field');
            case 'local': I18n.t('local');
            case 'text method': I18n.t('text method');
            case 'list method': I18n.t('list method');
            case 'map method': I18n.t('map method');
            case 'beat method': I18n.t('beat method');
            case _: kind;
        }

    }

    /**
     * The top of a hover: its title, then lines kept close under it, like
     * `Returns a number` or `Defaults to 2`. Hovers show text, not code: the
     * code is in the editor.
     */
    static function hoverHeader(title:String, ?note:Array<String>):String {

        final lines = [for (line in note ?? []) if (line != null && line.length > 0) line];
        return lines.length > 0 ? title + "\n\n" + hoverLines(lines) : title;

    }

    /** A value written in the script, shown as code: `false` */
    static function hoverValue(text:String):String {

        // A value holding a backquote needs a longer fence
        return text.indexOf('`') != -1 ? '`` ' + text + ' ``' : '`' + text + '`';

    }

    /** A value written in the script, as text on one line */
    function valueText(value:Null<Node>):String {

        if (value == null) return 'null';
        return ~/\s*\n\s*/g.replace(printLoreline(value), ' ');

    }

    /**
     * A group of a hover: its title, then one line per item, or null when
     * there is none.
     * @param line Wraps each line, to style it
     */
    static function hoverGroup(title:String, lines:Array<String>, ?line:(text:String)->String):Null<String> {

        if (lines.length == 0) return null;
        return '**$title**  \n' + hoverLines(line != null ? [for (text in lines) line(text)] : lines);

    }

    /**
     * One line per parameter, with what to say of it in parentheses:
     * `price (number)`, `discount (defaults to 2)`.
     */
    static function parameterLines(params:Array<{name:String, details:Array<String>}>):Array<String> {

        return [for (param in params) {
            final details = [for (detail in param.details) if (detail != null && detail.length > 0) detail];
            param.name + (details.length > 0 ? ' (' + details.join(', ') + ')' : '');
        }];

    }

    /** The parameters of a beat, with their default values */
    function beatParameters(beatDecl:NBeatDecl, ?typeOf:(param:NBeatParam)->Null<String>):Array<String> {

        return parameterLines([for (param in beatDecl.params ?? []) {
            name: param.name,
            details: [typeOf != null ? typeOf(param) : null, param.defaultValue != null ? I18n.t('defaults to {value}', {value: hoverValue(valueText(param.defaultValue))}) : null]
        }]);

    }

    /** The parameters of a function, with their default values */
    static function functionParameters(func:NFunctionDecl, ?typeOf:(name:String)->Null<String>):Array<String> {

        return parameterLines([for (arg in func.args ?? []) {
            final eq = arg.indexOf('=');
            final name = (eq != -1 ? arg.substr(0, eq) : arg).trim();
            {name: name, details: [typeOf != null ? typeOf(name) : null, eq != -1 ? I18n.t('defaults to {value}', {value: hoverValue(arg.substr(eq + 1).trim())}) : null]};
        }]);

    }

    /**
     * One line per field of a character or a state: its name, linked to where
     * it's declared, its value, and its type when it's known, like
     * `present: false (bool)`. A field holding an object gives its own fields
     * on the lines below, indented.
     * @param typeOf The type of a field, or null when it isn't known
     */
    function fieldLines(fields:Array<NObjectField>, uri:DocumentUri, lens:Lens, ?typeOf:(field:NObjectField)->Null<String>, depth:Int = 0):Array<String> {

        final lines:Array<String> = [];
        final indent = [for (_ in 0...depth) '&emsp;'].join('');
        for (field in fields) {
            final name = makePositionLink(field.name, uri, field, lens);
            final inner = objectFields(field.value);
            if (inner != null) {
                lines.push(indent + I18n.t('{name} (object)', {name: name}));
                for (line in fieldLines(inner, uri, lens, typeOf, depth + 1)) lines.push(line);
            }
            else {
                final type = typeOf != null ? typeOf(field) : null;
                lines.push(indent + name + ': ' + hoverValue(valueText(field.value)) + (type != null ? ' ($type)' : ''));
            }
        }
        return lines;

    }

    /** The fields of a value written as an object, or null when it isn't one */
    static function objectFields(value:Null<Node>):Null<Array<NObjectField>> {

        if (!(value is NLiteral)) return null;
        final literal:NLiteral = cast value;
        return switch literal.literalType {
            case Object(_): literal.value;
            case _: null;
        }

    }

    /** The fields of a character a hover lists: its name goes without saying when it's shown */
    function listedCharacterFields(characterDecl:NCharacterDecl):Array<NObjectField> {

        final shown = shownCharacterName(characterDecl) != characterDecl.name;
        return [for (field in characterDecl.fields) if (!(shown && field.name == 'name')) field];

    }

    /** Links of a hover, all of them, so that the list says everything */
    static function hoverList(links:Array<String>):String {

        return links.join(", ");

    }

    /** Lines kept close together in one section of a hover */
    static function hoverLines(lines:Array<String>):String {

        return lines.join("  \n");

    }

    function documentationForNode(node:AstNode):MarkupContent {

        final description:Array<String> = [];

        // The comments right above it, not those set apart by a blank line
        for (comment in AstUtils.docComments(node)) {
            description.push(comment.content.trim());
        }

        if (node.trailingComments != null) {
            if (description.length > 0) {
                description.push('');
                description.push('---');
                description.push('');
            }
            for (comment in node.trailingComments) {
                description.push(comment.content.trim());
            }
        }

        return {
            kind: MarkupKind.Markdown,
            value: description.join('\n')
        };

    }

    function hoverDescriptionForNode(node:AstNode):Array<String> {

        final description:Array<String> = [];

        // The comments right above it, without translation keys and directives
        if (node.leadingComments != null) {
            for (comment in AstUtils.docComments(node)) {
                if (comment.isHash) continue;
                for (line in comment.content.replace('\r\n', '\n').split('\n')) {
                    final text = line.trim();
                    if (text.length > 0 && !text.startsWith('@')) description.push(text);
                }
            }
        }

        if (node.trailingComments != null) {
            if (description.length > 0) {
                description.push('');
                description.push('---');
                description.push('');
            }
            for (comment in node.trailingComments) {
                description.push(comment.content.trim());
            }
        }

        return description;

    }

    function makePositionLink(text:String, uri:DocumentUri, node:Node, lens:Lens, ?extra:String):String {
        final targetUri = resolveNodeTarget(uri, node, lens).uri;
        return '[${text}](${targetUri}#${node.pos.line},${node.pos.column})' + (extra != null ? ' ($extra)' : '');
    }

    function makeBeatDeclHover(beatDecl:NBeatDecl, uri:DocumentUri, content:String, lens:Lens, ?origin:Node):Hover {

        return makeSectionsHover(
            hoverName(beatDecl.name, beatDecl.isPublic ? I18n.t('public beat') : I18n.t('beat')),
            [hoverDescriptionForNode(beatDecl).join("\n"), hoverGroup(I18n.t('Parameters'), beatParameters(beatDecl)), beatLinks(beatDecl, uri, lens)],
            content,
            origin ?? beatDecl
        );
    }

    /**
     * What a beat is linked to, in groups under a short title, each left out
     * when empty:
     * - **Flow**: the beats leading to it, those it goes to and those it calls;
     * - **Characters**: one per line, in bold when they speak in it, with
     *   the fields it uses, in bold when it changes them;
     * - **State**: the fields it changes, in bold, then those it reads.
     * @param line Wraps each line under a title, to style it
     */
    function beatLinks(beatDecl:NBeatDecl, uri:DocumentUri, lens:Lens, ?line:(text:String)->String):String {

        final groups:Array<String> = [];
        function group(title:String, lines:Array<String>) {
            if (lines.length > 0) groups.push('**$title**  \n' + hoverLines(line != null ? [for (text in lines) line(text)] : lines));
        }

        // The beats leading to it, by transition, call or insertion. Several
        // references from the same beat list it once.
        final flow:Array<String> = [];
        final incoming:Array<String> = [];
        final seenIncoming = new Map<String, Bool>();
        for (ref in lens.findReferencesToBeat(beatDecl)) {
            final from = lens.getFirstParentOfType(ref.origin, NBeatDecl);
            if (from == null) continue;
            final key = Std.string(from.id);
            if (seenIncoming.exists(key)) continue;
            seenIncoming.set(key, true);
            incoming.push(from.name == "_" ? I18n.t('top level') : makePositionLink(from.name, uri, from, lens));
        }
        if (incoming.length > 0) flow.push(I18n.t('From {list}', {list: hoverList(incoming)}));

        // The beats it goes to and the beats it calls, each once per list
        final transitions:Array<String> = [];
        final calls:Array<String> = [];
        final seenTransitions = new Map<String, Bool>();
        final seenCalls = new Map<String, Bool>();
        for (ref in lens.findOutboundBeats(beatDecl)) {
            final key = Std.string(ref.target.id);
            final transition = ref.origin is NTransition;
            final seen = transition ? seenTransitions : seenCalls;
            if (seen.exists(key)) continue;
            seen.set(key, true);
            (transition ? transitions : calls).push(makePositionLink(ref.target.name, uri, ref.target, lens));
        }
        if (transitions.length > 0) flow.push(I18n.t('To {list}', {list: hoverList(transitions)}));
        if (calls.length > 0) flow.push(I18n.t('Calls {list}', {list: hoverList(calls)}));
        group(I18n.t('Flow'), flow);

        // The fields it uses, changed ones first: by character, and of the state
        final changedFields = new NodeIdMap<Bool>();
        final fields:Array<NObjectField> = [];
        final seenFields = new NodeIdMap<Bool>();
        for (changed in [true, false]) {
            final refs = changed
                ? lens.findModifiedStateFields(beatDecl).concat(lens.findModifiedCharacterFields(beatDecl))
                : lens.findReadStateFields(beatDecl).concat(lens.findReadCharacterFields(beatDecl));
            for (ref in refs) {
                if (seenFields.exists(ref.target.id)) continue;
                seenFields.set(ref.target.id, true);
                if (changed) changedFields.set(ref.target.id, true);
                fields.push(ref.target);
            }
        }
        function fieldLink(field:NObjectField):String {
            final link = makePositionLink(field.name, uri, field, lens);
            return changedFields.exists(field.id) ? '**' + link + '**' : link;
        }

        // The characters speaking in it, then the others it mentions or whose fields it uses
        final characters:Array<NCharacterDecl> = [];
        final speaking = new NodeIdMap<Bool>();
        final characterRefs = lens.findBeatCharacters(beatDecl);
        for (speaks in [true, false]) {
            for (ref in characterRefs) {
                if ((HxType.getClass(ref.origin) == NDialogueStatement) != speaks) continue;
                if (speaks) speaking.set(ref.target.id, true);
                if (!characters.contains(ref.target)) characters.push(ref.target);
            }
        }
        for (field in fields) {
            final character = lens.getFirstParentOfType(field, NCharacterDecl);
            if (character != null && !characters.contains(character)) characters.push(character);
        }
        final characterLines:Array<String> = [];
        for (character in characters) {
            final link = makePositionLink(shownCharacterName(character), uri, character, lens);
            final own = [for (field in fields) if (lens.getFirstParentOfType(field, NCharacterDecl) == character) fieldLink(field)];
            characterLines.push((speaking.exists(character.id) ? '**' + link + '**' : link) + (own.length > 0 ? ': ' + hoverList(own) : ''));
        }
        group(I18n.t('Characters'), characterLines);

        final stateFields = [for (field in fields) if (lens.getFirstParentOfType(field, NCharacterDecl) == null) fieldLink(field)];
        if (stateFields.length > 0) group(I18n.t('State§group'), [hoverList(stateFields)]);

        return groups.join("\n\n---\n\n");
    }

    function makeStateDeclHover(stateDecl:NStateDecl, uri:DocumentUri, content:String, lens:Lens):Hover {

        return makeSectionsHover(hoverTitle(stateDecl.temporary ? I18n.t('Temporary state') : I18n.t('State')),
            [hoverDescriptionForNode(stateDecl).join("\n"), hoverGroup(I18n.t('Fields'), fieldLines(stateDecl.fields, uri, lens))], content, stateDecl);

    }

    function makeMetadataDeclHover(metadata:NMetadataDecl, uri:DocumentUri, content:String, lens:Lens, ?pos:loreline.Position):Hover {

        return makeSectionsHover(hoverTitle(I18n.t('Metadata')),
            [hoverDescriptionForNode(metadata).join("\n"), hoverGroup(I18n.t('Fields'), fieldLines(metadata.fields, uri, lens))], content, metadata, pos);

    }

    function makeCharacterDeclHover(characterDecl:NCharacterDecl, uri:DocumentUri, content:String, lens:Lens, ?pos:loreline.Position):Hover {

        return makeSectionsHover(hoverName(shownCharacterName(characterDecl), I18n.t('character')),
            [hoverDescriptionForNode(characterDecl).join("\n"), hoverGroup(I18n.t('Fields'), fieldLines(listedCharacterFields(characterDecl), uri, lens))], content, characterDecl, pos);

    }

    function makeFunctionHover(func:NFunctionDecl, uri:DocumentUri, content:String, lens:Lens, lorelinePos:loreline.Position):Hover {

        // Parameter hover when pointing at a name in the signature parens
        final paramHover = makeFunctionSignatureParamHover(func, uri, content, lens, lorelinePos);
        if (paramHover != null) return paramHover;

        var expr = null;
        try {
            expr = lens.getLorscriptExpr(func, lorelinePos);
        }
        catch (e:Dynamic) {}
        if (expr != null) {

            final codeToLorscript = lens.getFuncLorscript(func).codeToLorscript;
            final exprPos = codeToLorscript.toLorelinePos(func.pos, expr.pmin, expr.pmax);

            // TODO: this is pretty basic for now, could be improved at some point
            final title = switch expr.e {
                case EConst(CString(s)): I18n.t('Text');
                case EConst(CFloat(f)): I18n.t('Number');
                case EConst(CInt(v)): I18n.t('Number');
                case EConst(c): I18n.t('Constant');
                case EIdent('false'): I18n.t('Boolean');
                case EIdent('true'): I18n.t('Boolean');
                case EIdent('null'): I18n.t('Null');
                case EIdent(v): I18n.t('Name');
                case EVar(n, t, e): I18n.t('Variable');
                case EParent(e): I18n.t('Parenthesis');
                case EBlock(e): I18n.t('Block');
                case EField(e, f): I18n.t('Field');
                case EBinop(op, e1, e2): I18n.t('Binary operation');
                case EUnop(op, prefix, e): I18n.t('Unary operation');
                case ECall(e, params): I18n.t('Function');
                case EIf(cond, e1, e2): I18n.t('Condition');
                case EWhile(cond, e): I18n.t('Loop');
                case EFor(v, it, e): I18n.t('Iteration');
                case EBreak: I18n.t('Break');
                case EContinue: I18n.t('Continue');
                case EFunction(args, e, name, ret): I18n.t('Function');
                case EReturn(e): I18n.t('Return');
                case EArray(e, index): I18n.t('Array access');
                case EArrayDecl(e): I18n.t('Array');
                case ENew(cl, params): I18n.t('New');
                case EThrow(e): I18n.t('Throw');
                case ETry(e, v, t, ecatch): I18n.t('Try');
                case EObject(fl): I18n.t('Object');
                case ETernary(cond, e1, e2): I18n.t('Ternary operation');
                case ESwitch(e, cases, defaultExpr): I18n.t('Switch');
                case EDoWhile(cond, e): I18n.t('Do... while');
                case EMeta(name, args, e): I18n.t('Metadata');
                case ECheckType(e, t): I18n.t('Type');
            }

            return makeHover(hoverTitle(title ?? I18n.t('Expression')), hoverDescriptionForNode(func), content, func, exprPos);
        }

        return makeFunctionDeclHover(func, content);

    }

    function makeFunctionDeclHover(func:NFunctionDecl, content:String, ?lorelinePos:loreline.Position):Hover {

        var name = null;
        if (func.name != null) {
            name = func.name + '(';
            if (func.args != null) {
                var first = true;
                for (arg in func.args) {
                    if (!first) {
                        name += ', ';
                    }
                    first = false;
                    name += arg;
                }
            }
            name += ')';
        }

        return makeSectionsHover(hoverName(func.name ?? I18n.t('function'), func.external ? I18n.t('function provided by the app') : I18n.t('function')),
            [hoverDescriptionForNode(func).join("\n"), hoverGroup(I18n.t('Parameters'), functionParameters(func))], content, func, lorelinePos);

    }

    /**
     * Creates a hover for a beat parameter, showing its default value when any.
     */
    function makeBeatParamHover(param:NBeatParam, beatDecl:NBeatDecl, uri:DocumentUri, content:String, lens:Lens, anchor:Node, ?pos:loreline.Position):Hover {

        return makeHover(hoverHeader(hoverName(param.name, hoverWhat('parameter', makePositionLink(beatDecl.name, uri, beatDecl, lens))), [param.defaultValue != null ? I18n.t('Defaults to {value}', {value: hoverValue(valueText(param.defaultValue))}) : null]), null, content, anchor, pos);

    }

    /**
     * Creates a hover for a function parameter from its raw signature entry
     * (e.g. "level = 1": name before the first `=`, default after).
     */
    function makeFunctionParamHover(rawArg:String, func:NFunctionDecl, uri:DocumentUri, content:String, lens:Lens, anchor:Node, ?pos:loreline.Position):Hover {

        final eqIndex = rawArg.indexOf('=');
        final paramName = (eqIndex != -1 ? rawArg.substr(0, eqIndex) : rawArg).trim();

        return makeHover(hoverHeader(hoverName(paramName, hoverWhat('parameter', func.name != null ? makePositionLink(func.name, uri, func, lens) : null)), [eqIndex != -1 ? I18n.t('Defaults to {value}', {value: hoverValue(rawArg.substr(eqIndex + 1).trim())}) : null]), null, content, anchor, pos);

    }

    /**
     * Returns the raw text of a constant string literal (single Raw part), null otherwise.
     */
    function constantStringValue(expr:NExpr):Null<String> {

        if (expr is NStringLiteral) {
            final str:NStringLiteral = cast expr;
            if (str.parts != null && str.parts.length == 1) {
                switch str.parts[0].partType {
                    case Raw(text): return text;
                    case _:
                }
            }
        }

        return null;

    }

    /**
     * Resolves the static beat name of a call/transition/insertion owner,
     * when it can be known without running the script: a static target name,
     * or a constant string literal target expression.
     */
    function staticBeatTargetName(owner:Node):Null<String> {

        switch HxType.getClass(owner) {
            case NBeatCall:
                final beatCall:NBeatCall = cast owner;
                return constantStringValue(beatCall.targetExpr);
            case NTransition:
                final transition:NTransition = cast owner;
                if (transition.targetExpr != null) return constantStringValue(transition.targetExpr);
                if (transition.target != '.' && transition.target != '_') return transition.target;
            case NInsertion:
                final insertion:NInsertion = cast owner;
                if (insertion.targetExpr != null) return constantStringValue(insertion.targetExpr);
                return insertion.target;
            case _:
        }

        return null;

    }

    /**
     * Creates a parameter hint hover for the argument at the given index of
     * a call, beat call, transition or insertion, when the callee's
     * parameters can be resolved statically. Returns null otherwise.
     */
    function makeCallArgumentHover(owner:Node, index:Int, lens:Lens, uri:DocumentUri, content:String, anchor:Node):Null<Hover> {

        switch HxType.getClass(owner) {

            case NCall:
                final call:NCall = cast owner;
                if (call.target is NAccess) {
                    final access:NAccess = cast call.target;
                    if (access.target == null && access.name != null) {
                        // Beats win over functions, matching runtime precedence
                        final beat = lens.findBeatByNameFromNode(access.name, owner);
                        if (beat != null) {
                            return makeBeatParamHoverAt(beat, index, uri, content, lens, anchor);
                        }
                        final resolved = lens.resolveAccess(access);
                        if (resolved is NFunctionDecl) {
                            final func:NFunctionDecl = cast resolved;
                            if (func.args != null && index < func.args.length) {
                                return makeFunctionParamHover(func.args[index], func, uri, content, lens, anchor);
                            }
                        }
                    }
                }

            case NBeatCall | NTransition | NInsertion:
                final name = staticBeatTargetName(owner);
                if (name != null) {
                    final beat = lens.findBeatByNameFromNode(name, owner);
                    if (beat != null) {
                        return makeBeatParamHoverAt(beat, index, uri, content, lens, anchor);
                    }
                }

            case _:
        }

        return null;

    }

    /**
     * Param hover for the beat's parameter at the given index, if declared.
     */
    function makeBeatParamHoverAt(beat:NBeatDecl, index:Int, uri:DocumentUri, content:String, lens:Lens, anchor:Node):Null<Hover> {

        if (beat.params != null && index < beat.params.length) {
            return makeBeatParamHover(beat.params[index], beat, uri, content, lens, anchor);
        }

        return null;

    }

    /**
     * When the given node is the constant string target of a dynamic beat
     * call/transition/insertion (e.g. "Quest" in `beat("Quest", ...)`),
     * returns the resolved beat declaration.
     */
    function findConstantStringTargetBeat(node:Node, lens:Lens):Null<NBeatDecl> {

        final parent = lens.getParentNode(node);
        if (parent == null) return null;

        var isTarget = false;
        switch HxType.getClass(parent) {
            case NBeatCall:
                isTarget = (cast parent:NBeatCall).targetExpr == node;
            case NTransition:
                isTarget = (cast parent:NTransition).targetExpr == node;
            case NInsertion:
                isTarget = (cast parent:NInsertion).targetExpr == node;
            case _:
        }
        if (!isTarget) return null;

        final name = constantStringValue(cast node);
        if (name == null) return null;

        return lens.findBeatByNameFromNode(name, parent);

    }

    /**
     * The name that ends a text, possibly followed by spaces and multiline
     * comments, or null. Names take letters of any language and emoji, read
     * whole (see Identifiers). Lengths are in the units of `uLength`:
     * `nameLength` for the name, `gapLength` for what follows it, `totalLength`
     * for both.
     */
    static function nameBefore(text:String):Null<{nameLength:Int, gapLength:Int, totalLength:Int}> {
        final length = text.uLength();

        // Spaces and multiline comments before the end
        var end = length;
        while (end > 0) {
            final c = text.uCharCodeAt(end - 1);
            if (c == ' '.code || c == '\t'.code || c == '\n'.code || c == '\r'.code) {
                end--;
            }
            else if (c == '/'.code && end >= 2 && text.uCharCodeAt(end - 2) == '*'.code) {
                var p = end - 3;
                while (p >= 1 && !(text.uCharCodeAt(p - 1) == '/'.code && text.uCharCodeAt(p) == '*'.code)) p--;
                if (p < 1) break;
                end = p - 1;
            }
            else {
                break;
            }
        }

        // The name parts before them, starting with a name start
        var start = end;
        while (start > 0) {
            final previous = Chars.startBefore(text, start);
            if (!Identifiers.isPart(Chars.codeAt(text, previous))) break;
            start = previous;
        }
        while (start < end && !Identifiers.isStart(Chars.codeAt(text, start))) {
            start += Chars.unitsAt(text, start);
        }
        if (start >= end) return null;

        return {
            nameLength: end - start,
            gapLength: length - end,
            totalLength: length - start
        };
    }

    /**
     * Whether a text ends with `when` at the start of a line, then spaces and the
     * part of a strategy name typed so far: a strategy name comes next.
     */
    static function isWhenStrategyBefore(text:String):Bool {
        var p = text.uLength();

        // The strategy typed so far
        while (p > 0) {
            final previous = Chars.startBefore(text, p);
            if (!Identifiers.isPart(Chars.codeAt(text, previous))) break;
            p = previous;
        }

        // At least one space or tab after `when`
        final afterWhen = p;
        while (p > 0 && (text.uCharCodeAt(p - 1) == ' '.code || text.uCharCodeAt(p - 1) == '\t'.code)) p--;
        if (p == afterWhen || p < 4 || text.uSubstr(p - 4, 4) != 'when') return false;
        p -= 4;

        // Only spaces or tabs before it on its line
        while (p > 0 && (text.uCharCodeAt(p - 1) == ' '.code || text.uCharCodeAt(p - 1) == '\t'.code)) p--;
        return p == 0 || text.uCharCodeAt(p - 1) == '\n'.code;
    }

    /**
     * When the given position points at a parameter name inside the
     * function's signature parens, returns a parameter hover. The signature
     * is scanned from the source (raw args carry no positions), mirroring
     * the lexer's top-level comma splitting; bails out (no hover) on any
     * inconsistency rather than guessing.
     */
    function makeFunctionSignatureParamHover(func:NFunctionDecl, uri:DocumentUri, content:String, lens:Lens, lorelinePos:loreline.Position):Null<Hover> {

        if (func.args == null || func.args.length == 0) return null;

        // Locate the opening paren on the declaration line
        final max = content.length;
        var i = func.pos.offset;
        var openParen = -1;
        while (i < max) {
            final c = content.charCodeAt(i);
            if (c == '\n'.code) return null;
            if (c == '('.code) {
                openParen = i;
                break;
            }
            i++;
        }
        if (openParen == -1) return null;

        // Split segments on top-level commas up to the matching close paren
        final segments:Array<{start:Int, end:Int}> = [];
        var depth = 1;
        var inString = false;
        var segStart = openParen + 1;
        i = openParen + 1;
        while (i < max && depth > 0) {
            final c = content.charCodeAt(i);
            if (c == '\n'.code) return null;
            if (inString) {
                if (c == '\\'.code) i++;
                else if (c == '"'.code) inString = false;
            }
            else if (c == '"'.code) {
                inString = true;
            }
            else if (c == '('.code) {
                depth++;
            }
            else if (c == ')'.code) {
                depth--;
                if (depth == 0) {
                    segments.push({start: segStart, end: i});
                }
            }
            else if (c == ','.code && depth == 1) {
                segments.push({start: segStart, end: i});
                segStart = i + 1;
            }
            i++;
        }
        if (depth != 0 || segments.length != func.args.length) return null;

        // Find the identifier range of each segment and match the position
        for (index in 0...segments.length) {
            final segment = segments[index];
            var identStart = segment.start;
            while (identStart < segment.end && StringTools.isSpace(content, identStart)) identStart++;
            var identEnd = Identifiers.nameEnd(content, identStart);
            if (identEnd > segment.end) identEnd = segment.end;
            if (identEnd == identStart) continue;
            if (lorelinePos.offset >= identStart && lorelinePos.offset <= identEnd) {
                // The whole signature sits on the declaration line
                final identPos = new loreline.Position(func.pos.line, func.pos.column + (identStart - func.pos.offset), identStart, identEnd - identStart);
                return makeFunctionParamHover(func.args[index], func, uri, content, lens, func, identPos);
            }
        }

        return null;

    }

    /**
     * Completion items for the strategy of a when block: `first`, `pick` and the
     * functions of the script.
     */
    function getWhenStrategyCompletions(lens:Lens, replacementRange:Range):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];
        for (strategy in ['first', 'pick']) {
            items.push({
                label: strategy,
                kind: CompletionItemKind.Keyword,
                detail: I18n.t('When strategy'),
                insertText: strategy,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: whenStrategyDescription(strategy),
                textEdit: makeTextEdit(replacementRange, strategy)
            });
        }
        for (func in lens.getVisibleFunctions()) {
            if (func.name == null) continue;
            items.push({
                label: func.name,
                kind: CompletionItemKind.Function,
                detail: I18n.t('When strategy (function)'),
                insertText: func.name,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: whenStrategyDescription(func.name),
                textEdit: makeTextEdit(replacementRange, func.name)
            });
        }
        return items;
    }

    /**
     * What a strategy of a when block does, null for the default one.
     */
    static function whenStrategyDescription(strategy:Null<String>):String {
        return switch strategy {
            case null: I18n.t('Plays the most specific rule that applies, and takes turns between equally specific ones.');
            case 'first': I18n.t('Plays the first rule that applies, from top to bottom. Useful for thresholds.');
            case 'pick': I18n.t('Plays one of the rules that apply, at random.');
            case name: I18n.t('Lets the function `{name}` choose the rule to play.', {name: name});
        }
    }

    function makeWhenHover(when:NWhenStatement, content:String):Hover {
        final description = hoverDescriptionForNode(when);
        if (description.length > 0) description.push('');
        description.push(whenStrategyDescription(when.strategy));
        return makeHover(hoverTitle(I18n.t('When'), when.strategy), description, content, when);
    }

    function makeWhenRuleHover(rule:NWhenRule, content:String):Hover {
        final description = hoverDescriptionForNode(rule);
        if (description.length > 0) description.push('');
        if (rule.insertion != null) {
            description.push(rule.insertionCondition != null
                ? I18n.t('Brings the rules of the first when block of the inserted beat. Its condition only decides whether they come in.')
                : I18n.t('Brings the rules of the first when block of the inserted beat.'));
        }
        else {
            final criteria = AstUtils.whenRuleScore(rule);
            final alwaysEligible = rule.condition == null || AstUtils.isLiteralTrue(rule.condition);
            description.push(alwaysEligible ? I18n.t('Always applies') : I18n.count(criteria, '{n} condition', '{n} conditions'));
            if (rule.once) description.push(I18n.t('Played only once'));
        }
        return makeHover(hoverTitle(I18n.t('When rule')), description, content, rule);
    }

    function makeChoiceHover(choice:NChoiceStatement, content:String):Hover {

        return makeHover(hoverTitle(I18n.t('Choice')), hoverDescriptionForNode(choice), content, choice);

    }

    function makeImportHover(importNode:NImportStatement, content:String):Hover {

        return makeHover(hoverHeader(hoverName(importPathOf(importNode), I18n.t('import'))), hoverDescriptionForNode(importNode), content, importNode);

    }

    /** The path an import is written with, as written */
    static function importPathOf(importNode:NImportStatement):String {

        final parts = importNode.path?.parts;
        if (parts == null || parts.length == 0) return '';
        return switch parts[0].partType {
            case Raw(text): text;
            case _: '';
        }

    }

    function makeExprHover(expr:NExpr, content:String):Hover {

        return makeHover(hoverHeader(hoverTitle(I18n.t('Expression')), [valueText(expr)]), hoverDescriptionForNode(expr), content, expr);

    }

    function makeObjectFieldHover(field:NObjectField, uri:DocumentUri, content:String, lens:Lens):Hover {

        return makeHover(hoverHeader(fieldHeader(field, uri, lens), fieldNote(field, lens)), hoverDescriptionForNode(field), content, field);

    }

    /** The header of a field: what it belongs to, and the field as written in its block */
    function fieldHeader(field:NObjectField, uri:DocumentUri, lens:Lens):String {

        final owner = lens.getParentNode(field);
        if (owner is NCharacterDecl) return hoverName(field.name, hoverWhat('field', characterLink(cast owner, uri, lens)));
        if (owner is NMetadataDecl) return hoverName(field.name, I18n.t('metadata'));
        if (owner is NStateDecl) {
            // A field of the state of a beat names its beat
            final beat = lens.getFirstParentOfType(owner, NBeatDecl);
            final beatOwner = beat != null && beat.name != '_' ? makePositionLink(beat.name, uri, beat, lens) : null;
            return hoverName(field.name, hoverWhat('state field', beatOwner));
        }
        return hoverName(field.name, I18n.t('field'));

    }

    /** What a field means, kept under its title: only a known key of the metadata block has one */
    function fieldNote(field:NObjectField, lens:Lens):Array<String> {

        final meaning = lens.getParentNode(field) is NMetadataDecl ? MetadataKeys.meaning(field.name) : null;
        return meaning != null ? [meaning] : [];

    }

    function makeAccessHover(access:NAccess, uri:DocumentUri, content:String, lens:Lens):Hover {

        // Beat parameter usage (params shadow state fields, innermost beat first)
        final beatParam = lens.findBeatParamFromAccess(access);
        if (beatParam != null) {
            return makeBeatParamHover(beatParam.param, beatParam.beat, uri, content, lens, access);
        }

        final resolved = lens.resolveAccess(access);
        if (resolved != null) {

            if (resolved is NCharacterDecl) {
                return makeCharacterDeclHover(cast resolved, uri, content, lens, access.pos);
            }
            else if (resolved is NFunctionDecl) {
                return makeFunctionDeclHover(cast resolved, content, access.pos);
            }
            else if (resolved is NBeatDecl) {
                return makeBeatDeclHover(cast resolved, uri, content, lens, access);
            }
            else if (resolved is NMetadataDecl) {
                return makeMetadataDeclHover(cast resolved, uri, content, lens, access.pos);
            }

            final header = resolved is NObjectField ? hoverHeader(fieldHeader(cast resolved, uri, lens), fieldNote(cast resolved, lens)) : hoverTitle(I18n.t('Field'), access.name);
            return makeHover(header, hoverDescriptionForNode(access), content, access);
        }
        else {
            final parent = lens.getParentNode(access);

            if (parent is NCall) {
                final call:NCall = cast parent;
                if (call.target == access) {
                    return makeHover(hoverTitle(I18n.t('Function'), access.name + '()'), hoverDescriptionForNode(access), content, access);
                }
            }

            if (parent is NArrayAccess) {
                return makeHover(hoverTitle(I18n.t('Array access'), access.name + '[]'), hoverDescriptionForNode(access), content, access);
            }

            return makeHover(hoverTitle(I18n.t('Access'), access.name), hoverDescriptionForNode(access), content, access);
        }

        return null;

    }

    function makeArrayAccessHover(access:NArrayAccess, content:String, lens:Lens):Hover {

        return makeHover(hoverTitle(I18n.t('Array access'), printLoreline(access.target) + '[]'), hoverDescriptionForNode(access), content, access);

    }

    function makeDialogueStatementHover(expr:NDialogueStatement, uri:DocumentUri, content:String, lens:Lens):Hover {

        final characterDecl = lens.findCharacterFromDialogue(expr);
        if (characterDecl != null) {
            return makeHover(hoverTitle(I18n.t('Dialogue'), I18n.t('of {name}', {name: characterLink(characterDecl, uri, lens)})), hoverDescriptionForNode(expr), content, expr);
        }

        return makeHover(hoverTitle(I18n.t('Dialogue')), hoverDescriptionForNode(expr), content, expr);

    }

    function printLoreline(node:Node):String {

        final printer = new Printer();

        printer.enableComments = false;

        return printer.print(node).trim();

    }

    /**
     * The name a character is shown with, without the quotes it may be
     * written with, or its name in the script when it has none.
     */
    function shownCharacterName(character:NCharacterDecl):String {

        final name = characterName(character);
        return name.length >= 2 && name.startsWith('"') && name.endsWith('"') ? name.substr(1, name.length - 2) : name;

    }

    /** A link to a character, named as the story shows it */
    function characterLink(character:NCharacterDecl, uri:DocumentUri, lens:Lens):String {

        return makePositionLink(shownCharacterName(character), uri, character, lens);

    }

    function characterName(character:NCharacterDecl):String {

        final nameExpr = character.get('name');
        final printed = nameExpr != null ? printLoreline(nameExpr) : null;
        return printed != null && printed != 'null' && printed.trim() != '' && printed != '0' && printed != 'false' ? printed : character.name;

    }

    /**
     * Handle document symbol request
     */
    function handleDocumentSymbol(params:{
        textDocument:TextDocumentIdentifier
    }):Array<DocumentSymbol> {

        final ast = documents.get(params.textDocument.uri);
        if (ast == null) return [];

        final content = documentContents.get(params.textDocument.uri);
        if (content == null) return [];

        final printer = new SymbolPrinter(this, content);
        return printer.print(ast);

    }

    /**
     * Handle document formatting request
     */
    function handleDocumentFormatting(params:{
        textDocument:TextDocumentIdentifier,
        options:FormattingOptions
    }):Array<TextEdit> {

        final ast = documents.get(params.textDocument.uri);
        if (ast == null) return [];

        final content = documentContents.get(params.textDocument.uri);
        if (content == null) return [];

        try {
            var indent = new StringBuf();
            final tabSize = params.options.tabSize ?? 2;
            for (i in 0...tabSize) {
                indent.addChar(" ".code);
            }
            final printer = new Printer(indent.toString(), isWindows ? "\r\n" : "\n");

            return [{
                newText: printer.print(ast),
                range: rangeFromLorelinePosition(new loreline.Position(1, 1, 0, content.uLength()), content)
            }];
        }
        catch (e:Any) {
            onLog("Error when formatting: " + e);
        }

        return [];

    }

    function extractTextSectionsExcludingComments(text:String):Array<{offset:Int, length:Int}> {
        final results:Array<{offset:Int, length:Int}> = [];

        var i = 0;
        var startOffset = 0;
        var inSingleLineComment = false;
        var inMultiLineComment = false;

        while (i < text.uLength()) {
            // Check for comment starts
            if (!inSingleLineComment && !inMultiLineComment) {
                if (i + 1 < text.uLength() && text.uCharCodeAt(i) == '/'.code && text.uCharCodeAt(i + 1) == '/'.code) {
                    // Start of single line comment
                    if (i > startOffset) {
                        // Add text before comment, but trim trailing whitespace
                        var sectionText = text.uSubstr(startOffset, i - startOffset);
                        var trimmedLength = sectionText.rtrim().uLength();
                        if (trimmedLength > 0) {
                            results.push({offset: startOffset, length: trimmedLength});
                        }
                    }
                    inSingleLineComment = true;
                    i += 2; // Skip //
                    continue;
                } else if (i + 1 < text.uLength() && text.uCharCodeAt(i) == '/'.code && text.uCharCodeAt(i + 1) == '*'.code) {
                    // Start of multi-line comment
                    if (i > startOffset) {
                        // Add text before comment
                        results.push({offset: startOffset, length: i - startOffset});
                    }
                    inMultiLineComment = true;
                    i += 2; // Skip /*
                    continue;
                }
            }

            // Check for comment ends
            if (inSingleLineComment) {
                if (text.uCharCodeAt(i) == '\n'.code) {
                    inSingleLineComment = false;
                    startOffset = i + 1; // Start after newline
                }
            } else if (inMultiLineComment) {
                if (i + 1 < text.uLength() && text.uCharCodeAt(i) == '*'.code && text.uCharCodeAt(i + 1) == '/'.code) {
                    inMultiLineComment = false;
                    i += 2; // Skip */
                    startOffset = i; // Start after comment end
                    continue;
                }
            }

            i++;
        }

        // Add any remaining text that's not in a comment
        if (!inSingleLineComment && !inMultiLineComment && i > startOffset) {
            results.push({offset: startOffset, length: i - startOffset});
        }

        return results;

    }

    /**
     * Convert an LSP Protocol Position to a Loreline Position
     *
     * LSP positions are 0-based for both line and character
     * Loreline positions are 1-based for both line and column. The LSP
     * `character` is a UTF-16 unit (the `positionEncoding` declared), equal
     * to a Loreline column because the server runs on UTF-16 targets.
     *
     * @param protocolPos The LSP Protocol position with line and character fields
     * @param content document content string to compute offset
     * @param length Optional length to include in position
     * @return A Loreline Position instance
     */
    public static function toLorelinePosition(protocolPos:loreline.lsp.Protocol.Position, content:String, ?length:Int = 0):loreline.Position {
        // Convert from 0-based to 1-based indexing
        final line = protocolPos.line + 1;
        final column = protocolPos.character + 1;

        // Calculate absolute offset if content is provided
        final offset = computeLorelineOffset(line, column, content);

        return new loreline.Position(line, column, offset, length);
    }

    static function computeLorelineOffset(line:Int, column:Int, content:String) {

        var offset = 0;

        if (content != null) {
            var currentLine = 1;
            var currentCol = 1;
            var i = 0;

            while (i < content.uLength()) {
                if (currentLine == line && currentCol == column) {
                    offset = i;
                    break;
                }

                if (content.uCharCodeAt(i) == '\n'.code) {
                    currentLine++;
                    currentCol = 1;
                } else {
                    currentCol++;
                }
                i++;
            }

            // Handle position at end of content
            if (currentLine == line && currentCol == column) {
                offset = i;
            }
        }

        return offset;

    }

    /**
     * Convert a Loreline Position to an LSP Protocol Position
     *
     * Loreline positions are 1-based for both line and column
     * LSP positions are 0-based for both line and character
     *
     * @param lorelinePos The Loreline position instance
     * @return An LSP Protocol position
     */
    public function fromLorelinePosition(lorelinePos:loreline.Position):loreline.lsp.Protocol.Position {
        return {
            // Convert from 1-based to 0-based indexing
            line: lorelinePos.line - 1,
            character: lorelinePos.column - 1
        };
    }

    public function rangeFromLorelinePosition(lorelinePos:loreline.Position, content:String):loreline.lsp.Protocol.Range {
        final start = fromLorelinePosition(lorelinePos);
        final end = fromLorelinePosition(lorelinePos.withOffset(content, lorelinePos.length));
        return {
            start: start,
            end: end
        };
    }

    inline function makeTextEdit(range:Range, newText:String):TextEdit {
        return { range: range, newText: newText };
    }

    function firstLineRange(range:Range, content:String):Range {
        // Skip preceding whitespace lines
        var lineStart = range.start.line;
        final lines = content.split("\n");
        while (lineStart < lines.length && lines[lineStart].trim().length == 0) {
            lineStart++;
        }

        // Find end of first non-empty line
        if (lineStart >= lines.length) lineStart = lines.length - 1;
        var lineEnd = lineStart;
        var charEnd = lines[lineEnd].uLength();

        return {
            start: {
                line: lineStart,
                character: range.start.character
            },
            end: {
                line: lineEnd,
                character: charEnd
            }
        };
     }

}