package loreline.lsp;

import Type as HxType;
import haxe.Json;
import haxe.io.Path;
import loreline.Error;
import loreline.Lexer;
import loreline.Node;
import loreline.Parser;
import loreline.lsp.Protocol;

using StringTools;
using loreline.Utf8;

/**
 * Main LSP server implementation for Loreline
 */
class Server {

    final RE_IDENTIFIER_BEFORE = ~/([a-zA-Z_][a-zA-Z0-9_]*)((?:\s*|\/\*(?:[^*]|\*[^\/])*\*\/)*)$/;

    final RE_ARROW_BEFORE = ~/(->)((?:\s*|\/\*(?:[^*]|\*[^\/])*\*\/)*)$/;

    final RE_ARRAY_ACCESS_BEFORE = ~/(\])((?:\s*|\/\*(?:[^*]|\*[^\/])*\*\/)*)$/;

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

        final uri = uriFromPath(path);
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
    public function handleMessage(msg:Message):Null<ResponseMessage> {
        try {
            // Check message type and dispatch accordingly
            if (Reflect.hasField(msg, "method")) {
                if (Reflect.hasField(msg, "id")) {
                    // Request message
                    return handleRequest(cast msg);
                } else {
                    // Notification message
                    handleNotification(cast msg);
                    return null;
                }
            }

            return createErrorResponse(null, ErrorCodes.InvalidRequest, "Invalid message");

        } catch (e:Dynamic) {
            return createErrorResponse(null, ErrorCodes.ParseError, Std.string(e));
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
    function handleRequest(request:RequestMessage):ResponseMessage {
        try {
            if (!initialized && request.method != "initialize") {
                throw { code: ErrorCodes.ServerNotInitialized, message: "Server not initialized" };
            }

            final result = resolveRequest(request);
            return createResponse(request.id, result);

        } catch (e:Any) {
            if (Reflect.hasField(e, 'code') && Reflect.hasField(e, 'message')) {
                final err:ResponseError = e;
                return createErrorResponse(request.id, err.code, err.message);
            }
            else {
                return createErrorResponse(request.id, ErrorCodes.InternalError, Std.string(e));
            }
        }
        return null;
    }

    function resolveRequest(request:RequestMessage):Any {

        return switch (request.method) {
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
                documentFormattingProvider: true  // For code formatting
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

        for (key => imports in documentImports) {
            for (i in 0...imports.length) {
                final imp = imports[i];
                if (imp == uri) {
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

                    // Check for parser errors
                    final errors = parser.getErrors();
                    if (errors != null && errors.length > 0) {
                        for (error in errors) {
                            addDiagnostic(uri, error.pos, error.message, DiagnosticSeverity.Error);
                        }
                    }

                    // Check for errors in functions
                    for (func in lens.getNodesOfType(NFunctionDecl, false)) {
                        final funcHscript = lens.getFuncHscript(func);
                        if (funcHscript.error != null) {
                            addDiagnostic(uri, funcHscript.error.pos, funcHscript.error.message, DiagnosticSeverity.Error);
                        }
                    }

                    // Look for transitions to unknown beats
                    for (transition in lens.getNodesOfType(NTransition, false)) {
                        if (transition.target != '.') {
                            if (lens.findBeatByNameFromNode(transition.target, transition) == null) {
                                addDiagnostic(uri, transition.targetPos, 'Unknown beat: ${transition.target}', DiagnosticSeverity.Error);
                            }
                        }
                    }

                    // Look for insertions of unknown beats
                    for (insertion in lens.getNodesOfType(NInsertion, false)) {
                        if (insertion.target != '.') {
                            if (lens.findBeatByNameFromNode(insertion.target, insertion) == null) {
                                addDiagnostic(uri, insertion.targetPos, 'Unknown beat: ${insertion.target}', DiagnosticSeverity.Error);
                            }
                        }
                    }

                    // Check for references to unknown characters in dialogue statements
                    for (dialogue in lens.getNodesOfType(NDialogueStatement, false)) {
                        final parentBeat = lens.getFirstParentOfType(dialogue, NBeatDecl);
                        if (parentBeat != null && parentBeat.name != "_") {
                            final characterDecl = lens.findCharacterFromDialogue(dialogue);
                            if (characterDecl == null) {
                                addDiagnostic(
                                    uri,
                                    dialogue.characterPos,
                                    'Unknown character: ${dialogue.character}',
                                    DiagnosticSeverity.Warning
                                );
                            }
                        }
                    }

                    // Add semantic validation
                    validateDocument(uri, ast);
                }
                else {
                    for (e in errors) {
                        if (e is Error) {
                            // Handle lexer/parser errors
                            final err:Error = cast e;
                            addDiagnostic(uri, err.pos, err.message, DiagnosticSeverity.Error);
                        }
                        else {
                            // Handle unexpected errors
                            addDiagnostic(uri, null, Std.string(e), DiagnosticSeverity.Error);
                        }
                    }
                }
            }, e -> errors.push(e));

            // Publish diagnostics
            publishDiagnostics(uri);
        } else {
            fetchAst(uri, content, (lexer, parser, ast) -> {
                if (ast != null) {
                    setDocument(uri, ast);
                }
            });
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

    function updateDocumentIfNeeded(uri:String) {

        if (dirtyDocuments.exists(uri)) {
            handleFile(pathFromUri(uri), content -> {
                if (content != null) {
                    updateDocument(uri, content, true);
                }
            });
        }

    }

    function fetchAst(uri:String, content:String, callback:(lexer:Lexer, parser:Parser, ast:Script)->Void, ?handleError:(err:Any)->Void):Null<Script> {

        final lexer = new Lexer(content);
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

            var imports = new Imports();
            imports.resolve(filePath, tokens, handleFile, handleError, (hasErrors, resolvedImports) -> {

                final parser = new Parser(tokens, {
                    rootPath: filePath,
                    path: filePath,
                    imports: resolvedImports
                });

                result = parser.parse();
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
    function addDiagnostic(uri:String, pos:Null<loreline.Position>, message:String, severity:DiagnosticSeverity) {
        final diagnostics = documentDiagnostics.get(uri);
        if (diagnostics == null) return;

        final range = if (pos != null) {
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

        diagnostics.push({
            range: range,
            severity: severity,
            source: "loreline",
            message: message
        });
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
        updateDocumentIfNeeded(uri);

        final ast = documents.get(uri);
        if (ast == null) return [];

        final content = documentContents.get(uri);
        if (content == null) return [];

        final lorelinePos = toLorelinePosition(params.position, content);
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
        if (params.context != null && triggerCharacter != null) {
            switch triggerCharacter {
                case ".": // Field access completion
                    var prevText = content.uSubstr(0, lorelinePos.offset);
                    var dotIdx = prevText.lastIndexOf(".");
                    if (dotIdx < 0) return [];
                    prevText = prevText.uSubstr(0, dotIdx);
                    var resolved:Node = null;
                    if (RE_IDENTIFIER_BEFORE.match(prevText)) {
                        final beforePos = lorelinePos.withOffset(content, -RE_IDENTIFIER_BEFORE.matched(0).uLength() - 1);
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
                            #if hscript
                            final hscriptCompletion = lens.getHscriptCompletion(func, lorelinePos);
                            if (hscriptCompletion?.completion != null) {
                                switch hscriptCompletion.completion.expr.e {
                                    case EField(e, f):
                                        switch hscriptCompletion.completion.t {
                                            case TAnon(fields):
                                                final items:Array<CompletionItem> = [];
                                                for (field in fields) {
                                                    items.push({
                                                        label: field.name,
                                                        kind: CompletionItemKind.Field,
                                                        detail: "Object field",
                                                        insertText: field.name,
                                                        insertTextMode: AsIs,
                                                        insertTextFormat: PlainText,
                                                        documentation: ''
                                                    });
                                                }
                                                return items;
                                            case _:
                                        }
                                    case _:
                                }
                            }
                            #end
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
                                    detail: "Character property",
                                    insertText: field.name,
                                    insertTextMode: AsIs,
                                    insertTextFormat: PlainText,
                                    documentation: documentationForNode(field)
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
                                            detail: "Object field",
                                            insertText: field.name,
                                            insertTextMode: AsIs,
                                            insertTextFormat: PlainText,
                                            documentation: documentationForNode(field)
                                        });
                                    }
                                    return items;
                            }
                    }

                    return [];

                case "$": // Variable interpolation completion
                    return getVariableCompletions(lens, node, lorelinePos);

                case "<": // Tag completion
                    if (node is NFunctionDecl) {
                        return [];
                    }
                    return getTagCompletions(lens);

                case "\"": // String completion - no special handling needed
                    return [];

                case " ": // Transition?
                    final prevText = content.uSubstr(0, lorelinePos.offset);
                    final isTransition = RE_ARROW_BEFORE.match(prevText);
                    if (isTransition) {
                        final matchedLen = RE_ARROW_BEFORE.matched(0).uLength();
                        final trimmedLen = RE_ARROW_BEFORE.matched(0).rtrim().uLength();
                        final spaces = matchedLen != trimmedLen ? RE_ARROW_BEFORE.matched(0).uSubstr(trimmedLen, matchedLen - trimmedLen) : '';
                        return getBeatCompletions(lens, node, spaces.uLength() > 0 ? '' : ' ');
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
                return getBeatCompletions(lens, node, spaces.uLength() > 0 ? '' : ' ');
            }

            // Return all available completions for CTRL + Space
            final items:Array<CompletionItem> = [];

            // Add locals completion (if inside a function)
            if (node is NFunctionDecl) {
                final func:NFunctionDecl = cast node;
                #if hscript
                final hscriptCompletion = lens.getHscriptCompletion(func, lorelinePos);
                if (hscriptCompletion?.locals != null) {
                    for (name => local in hscriptCompletion.locals) {
                        items.push({
                            label: name,
                            kind: CompletionItemKind.Field,
                            detail: "Local variable",
                            insertText: name,
                            insertTextMode: AsIs,
                            insertTextFormat: PlainText,
                            documentation: ''
                        });
                    }
                }
                #end
            }

            // Add state field completions
            for (field in lens.getVisibleStateFields(node)) {
                items.push({
                    label: field.name,
                    kind: CompletionItemKind.Variable,
                    detail: "State field",
                    insertText: field.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(field)
                });
            }

            // Add character completions
            for (character in lens.getVisibleCharacters()) {
                items.push({
                    label: character.name,
                    kind: CompletionItemKind.Struct,
                    detail: "Character",
                    insertText: character.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(character)
                });
            }

            // Add function completions
            for (func in lens.getVisibleFunctions()) {
                if (func.name != null) {
                    items.push({
                        label: func.name,
                        kind: CompletionItemKind.Function,
                        detail: "Function",
                        insertText: func.name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: documentationForNode(func)
                    });
                }
            }

            // Add beat completions
            if (!(node is NFunctionDecl)) {
                for (beat in lens.getVisibleBeats(node)) {
                    items.push({
                        label: beat.name,
                        kind: CompletionItemKind.Class,
                        detail: "Beat",
                        insertText: beat.name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: documentationForNode(beat)
                    });
                }
            }

            return items;
        }

        return [];
    }

    /**
     * Get completion items for variables in scope
     */
    function getVariableCompletions(lens:Lens, node:Node, lorelinePos:loreline.Position):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];

        // Add locals completion (if inside a function)
        if (node is NFunctionDecl) {
            final func:NFunctionDecl = cast node;
            #if hscript
            final hscriptCompletion = lens.getHscriptCompletion(func, lorelinePos);
            if (hscriptCompletion?.locals != null) {
                for (name => local in hscriptCompletion.locals) {
                    items.push({
                        label: name,
                        kind: CompletionItemKind.Field,
                        detail: "Local variable",
                        insertText: name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText,
                        documentation: ''
                    });
                }
            }
            #end
        }

        // Add state fields
        for (field in lens.getVisibleStateFields(node)) {
            items.push({
                label: field.name,
                kind: CompletionItemKind.Variable,
                detail: "State field",
                documentation: documentationForNode(field)
            });
        }

        // Add characters (can be used in interpolation)
        for (character in lens.getVisibleCharacters()) {
            items.push({
                label: character.name,
                kind: CompletionItemKind.Class,
                detail: "Character",
                documentation: documentationForNode(character)
            });
        }

        // Add function completions
        for (func in lens.getVisibleFunctions()) {
            if (func.name != null) {
                items.push({
                    label: func.name,
                    kind: CompletionItemKind.Function,
                    detail: "Function",
                    insertText: func.name,
                    insertTextMode: AsIs,
                    insertTextFormat: PlainText,
                    documentation: documentationForNode(func)
                });
            }
        }

        return items;
    }

    /**
     * Get completion items for beats in scope
     */
    function getBeatCompletions(lens:Lens, node:Node, insert:String):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];

        // Add state fields
        for (beat in lens.getVisibleBeats(node)) {
            items.push({
                label: beat.name,
                kind: CompletionItemKind.Class,
                detail: "Beat",
                insertText: (insert ?? '') + beat.name,
                insertTextMode: AsIs,
                insertTextFormat: PlainText,
                documentation: documentationForNode(beat)
            });
        }

        return items;
    }

    /**
     * Get completion items for tags based on existing tags in the script
     */
    function getTagCompletions(lens:Lens):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];
        final counts = lens.countTags();

        for (tag in lens.getAllTags()) {
            final uses = counts.get(tag);
            items.push({
                label: tag,
                kind: CompletionItemKind.Enum,
                detail: "Tag",
                documentation: 'Used $uses time' + (uses == 1 ? '' : 's')
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
        updateDocumentIfNeeded(uri);

        final ast = documents.get(uri);
        if (ast == null) return result;

        final content = documentContents.get(uri);
        final lorelinePos = toLorelinePosition(params.position, content);

        final lens = new Lens(ast);
        var node = lens.getNodeAtPosition(lorelinePos);

        if (node is NLiteral) {
            var parent = node;
            do {
                parent = lens.getParentNode(parent);
                if (parent != null) {
                    switch HxType.getClass(parent) {
                        case NAccess | NArrayAccess:
                            node = parent;
                            break;
                        case _:
                    }
                }
            }
            while (parent != null);
        }

        if (node != null) {
            switch HxType.getClass(node) {

                case NAccess:
                    final access:NAccess = cast node;
                    final resolved = lens.resolveAccess(access);
                    if (resolved != null) {
                        final peekNode:Node = switch HxType.getClass(resolved) {
                            case NObjectField: cast (lens.getFirstParentOfType(resolved, NCharacterDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NStateDecl):Node) ?? resolved;
                            case _: resolved;
                        }
                        result.push({
                            targetUri: resolveNodeUri(uri, resolved, lens),
                            targetRange: rangeFromLorelinePosition(peekNode.pos, content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(resolved.pos, content), content),
                            originSelectionRange: rangeFromLorelinePosition(access.pos, content)
                        });
                    }

                case NArrayAccess:
                    final access:NArrayAccess = cast node;
                    final resolved = lens.resolveArrayAccess(access);
                    if (resolved != null) {
                        final peekNode:Node = switch HxType.getClass(resolved) {
                            case NObjectField: cast (lens.getFirstParentOfType(resolved, NCharacterDecl):Node) ?? cast (lens.getFirstParentOfType(resolved, NStateDecl):Node) ?? resolved;
                            case _: resolved;
                        }
                        result.push({
                            targetUri: resolveNodeUri(uri, resolved, lens),
                            targetRange: rangeFromLorelinePosition(peekNode.pos, content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(resolved.pos, content), content),
                            originSelectionRange: rangeFromLorelinePosition(access.pos, content)
                        });
                    }

                case NTransition:
                    final transition:NTransition = cast node;
                    final beatDecl = lens.findBeatFromTransition(transition);
                    if (beatDecl != null) {
                        // Create a location link with more detailed targeting
                        result.push({
                            // The document containing the target
                            targetUri: resolveNodeUri(uri, beatDecl, lens),
                            // Full range of the beat declaration
                            targetRange: rangeFromLorelinePosition(beatDecl.pos, content),
                            // More precise range for the beat name
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, content), content),
                            // Range of the transition reference in the source
                            originSelectionRange: rangeFromLorelinePosition(transition.targetPos, content)
                        });
                    }

                case NInsertion:
                    final insertion:NInsertion = cast node;
                    final beatDecl = lens.findBeatFromInsertion(insertion);
                    if (beatDecl != null) {
                        // Create a location link with more detailed targeting
                        result.push({
                            // The document containing the target
                            targetUri: resolveNodeUri(uri, beatDecl, lens),
                            // Full range of the beat declaration
                            targetRange: rangeFromLorelinePosition(beatDecl.pos, content),
                            // More precise range for the beat name
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, content), content),
                            // Range of the insertion reference in the source
                            originSelectionRange: rangeFromLorelinePosition(insertion.targetPos, content)
                        });
                    }

                case NDialogueStatement:
                    final dialogue:NDialogueStatement = cast node;
                    final characterDecl = lens.findCharacterFromDialogue(dialogue);
                    if (characterDecl != null) {
                        // Create a location link for the character definition
                        result.push({
                            targetUri: resolveNodeUri(uri, characterDecl, lens),
                            targetRange: rangeFromLorelinePosition(characterDecl.pos, content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(characterDecl.pos, content), content),
                            originSelectionRange: rangeFromLorelinePosition(dialogue.characterPos, content)
                        });
                    }

                case NImportStatement:
                    final importNode:NImportStatement = cast node;
                    result.push({
                        targetUri: resolveNodeUri(uri, importNode, lens),
                        targetRange: rangeFromLorelinePosition(new loreline.Position(1, 1, 0, 0), ''),
                        targetSelectionRange: rangeFromLorelinePosition(new loreline.Position(1, 1, 0, 0), '')
                    });
            }
        }

        return result;
    }

    function resolveNodeUri(uri:String, node:Node, lens:Lens):String {
        final importNode = node is NImportStatement ? cast node : lens.getFirstParentOfType(node, NImportStatement);

        if (importNode != null) {
            final rootPath = pathFromUri(uri);
            if (rootPath != null) {
                var importPath = switch importNode.path.parts[0].partType {
                    case Raw(text): text;
                    case _: "";
                }

                if (!Path.isAbsolute(importPath)) {
                    importPath = Path.join([Path.directory(rootPath), importPath]);
                }

                importPath = Path.normalize(importPath);

                var ext = '.lor';
                if (rootPath != null && rootPath.endsWith('.lor.txt')) {
                    ext = '.lor.txt';
                }

                if (!importPath.toLowerCase().endsWith(ext)) {
                    importPath += ext;
                }

                uri = uriFromPath(importPath);
            }
        }

        return uri;

    }

    function makeDoubleQuotedTextHover(literal:NStringLiteral, lens:Lens, description:Array<String>, content:String, part:NStringPart, ?pos:loreline.Position):Hover {

        var kind = 'Text';
        var name = null;
        var origin = null;

        final parent = lens.getParentNode(literal);
        if (parent != null) {
            switch HxType.getClass(parent) {
                case NChoiceOption:
                    kind = 'Choice option';
                case NDialogueStatement:
                    kind = 'Dialogue';
                    final characterDecl = lens.findCharacterFromDialogue(cast parent);
                    if (characterDecl != null) {
                        origin = characterName(characterDecl);
                    }
                case _:
            }
        }

        return makeHover(hoverTitle(kind, name, origin), description, content, part, pos);

    }

    function makeUnquotedTextHover(literal:NStringLiteral, lens:Lens, cursorLorelinePos:loreline.Position, description:Array<String>, content:String, part:NStringPart, ?pos:loreline.Position):Hover {

        var spaceOffset = 0;
        if (pos == null) {
            pos = part.pos;
        }
        else {
            spaceOffset = pos.offset - part.pos.offset;
        }

        var kind = 'Text';
        var name = null;
        var origin = null;

        final parent = lens.getParentNode(literal);
        if (parent != null) {
            switch HxType.getClass(parent) {
                case NChoiceOption:
                    kind = 'Choice option';
                case NDialogueStatement:
                    kind = 'Dialogue';
                    final characterDecl = lens.findCharacterFromDialogue(cast parent);
                    if (characterDecl != null) {
                        origin = characterName(characterDecl);
                    }
                case _:
            }
        }

        switch part.partType {
            case Raw(text):
                final offset = cursorLorelinePos.offset - pos.offset;
                var first = true;
                for (sub in extractTextSectionsExcludingComments(text)) {
                    if (offset >= sub.offset && offset < sub.offset + sub.length - (first ? spaceOffset : 0)) {
                        return makeHover(hoverTitle(kind, name, origin), description, content, part, pos.withOffset(content, sub.offset - (first ? 0 : spaceOffset), sub.length - (first ? spaceOffset : 0)));
                    }
                    first = false;
                }
                return null;
            case _:
                return makeHover(hoverTitle(kind, name, origin), description, content, part, pos);
        }

    }

    function makeHover(title:String, description:Array<String>, content:String, node:Node, ?pos:loreline.Position):Hover {

        final value:Array<String> = [];

        if (title != null) {
            value.push(title);
        }

        if (description != null && description.length > 0) {
            if (title != null) {
                value.push("");
                value.push("---");
                value.push("");
            }

            value.push(description.join("\n"));
        }

        return {
            contents: {
                kind: MarkupKind.Markdown,
                value: value.join("\n")
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
        updateDocumentIfNeeded(uri);

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

        switch HxType.getClass(node) {
            case NBeatDecl:
                return makeBeatDeclHover(cast node, uri, content, lens);
            case NStateDecl:
                return makeStateDeclHover(cast node, content);
            case NCharacterDecl:
                return makeCharacterDeclHover(cast node, content);
            case NChoiceStatement:
                return makeChoiceHover(cast node, content);
            case NImportStatement:
                return makeImportHover(cast node, content);
            case NFunctionDecl:
                return makeFunctionHover(cast node, content, lens, lorelinePos);
            case NTransition:
                final transition:NTransition = cast node;
                if (transition.target == '.') {
                    return makeHover(hoverTitle('End'), hoverDescriptionForNode(cast node), content, node);
                }
                else if (transition.target == '_') {
                    return makeHover(hoverTitle('Root'), hoverDescriptionForNode(cast node), content, node);
                }
                else {
                    final beat = lens.findBeatFromTransition(transition);
                    if (beat != null) {
                        return makeBeatDeclHover(beat, uri, content, lens, node);
                    }
                    else {
                        return makeHover(hoverTitle('Transition'), hoverDescriptionForNode(cast node), content, node);
                    }
                }
            case NInsertion:
                final insertion:NInsertion = cast node;
                final beat = lens.findBeatFromInsertion(insertion);
                if (beat != null) {
                    return makeBeatDeclHover(beat, uri, content, lens, node);
                }
                else {
                    return makeHover(hoverTitle('Insertion'), hoverDescriptionForNode(cast node), content, node);
                }
            case NObjectField:
                return makeObjectFieldHover(cast node, content);
            case NAccess:
                var access:NAccess = cast node;
                var parent = lens.getParentNode(access);
                if (parent is NCall) {
                    final resolved = lens.resolveAccess(access);
                    if (resolved is NBeatDecl) {
                        return makeBeatDeclHover(cast resolved, uri, content, lens, access);
                    }
                }
                return makeAccessHover(access, content, lens);
            case NArrayAccess:
                var access:NArrayAccess = cast node;
                var parent = lens.getParentNode(access);
                return makeArrayAccessHover(access, content, lens);

            case NLiteral:
                final literal:NLiteral = cast node;
                switch literal.literalType {
                    case Number:
                        return makeHover(hoverTitle('Number'), hoverDescriptionForNode(literal), content, literal);
                    case Boolean:
                        return makeHover(hoverTitle('Boolean'), hoverDescriptionForNode(literal), content, literal);
                    case Null:
                        return makeHover(hoverTitle('Null'), hoverDescriptionForNode(literal), content, literal);
                    case Array:
                        return makeHover(hoverTitle('Array'), hoverDescriptionForNode(literal), content, literal);
                    case Object(style):
                        return makeHover(hoverTitle('Object'), hoverDescriptionForNode(literal), content, literal);
                }
            case NExpr | NAssign | NUnary | NBinary:
                return makeHover(hoverTitle('Expression'), hoverDescriptionForNode(cast node), content, node);
            case NIfStatement:
                return makeHover("**Condition**", null, content, node);
            case NDialogueStatement:
                return makeDialogueStatementHover(cast node, content, lens);
            case NStringLiteral | NTextStatement:
                return makeHover(hoverTitle('Text'), hoverDescriptionForNode(cast node), content, node);
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
                        return makeHover(hoverTitle('Tag', "&lt;" + (closing ? "/" : "") + printLoreline(expr) + "&gt;"), hoverDescriptionForNode(expr), content, stringPart);
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
                                return makeHover(hoverTitle('Tag', "&lt;" + (closing ? "/" : "") + printLoreline(expr) + "&gt;"), hoverDescriptionForNode(expr), content, parentStringPart);
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
                                            return makeUnquotedTextHover(literal, lens, lorelinePos, hoverDescriptionForNode(literal.parts[partIndex]), content, stringPart, stringPart.pos.withOffset(content, spaces, stringPart.pos.length - spaces));
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
                                    return makeDoubleQuotedTextHover(literal, lens, hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 2));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == 0) {
                            switch literal.parts[0].partType {
                                case Raw(text):
                                    return makeDoubleQuotedTextHover(literal, lens, hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == literal.parts.length - 1) {
                            switch literal.parts[literal.parts.length - 1].partType {
                                case Raw(text):
                                    return makeDoubleQuotedTextHover(literal, lens, hoverDescriptionForNode(literal.parts[literal.parts.length - 1]), content, stringPart, stringPart.pos.withOffset(content, 0, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                    }
                }

                switch stringPart.partType {
                    case Raw(text):
                        return makeUnquotedTextHover(literal, lens, lorelinePos, hoverDescriptionForNode(stringPart), content, stringPart);
                    case Expr(expr):
                    case Tag(closing, expr):
                }
            case _:
        }
        return null;

    }

    function hoverTitle(kind:String, ?name:String, ?origin:String):String {

        var title = kind;

        if (name != null) {
            title += ': **' + name + '**';
        }
        else {
            title = '**' + title + '**';
        }

        if (origin != null) {
            title += ' (' + origin + ')';
        }

        return title;

    }

    function documentationForNode(node:AstNode):MarkupContent {

        final description:Array<String> = [];

        if (node.leadingComments != null) {
            for (comment in node.leadingComments) {
                description.push(comment.content.trim());
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

        return {
            kind: MarkupKind.Markdown,
            value: description.join('\n')
        };

    }

    function hoverDescriptionForNode(node:AstNode):Array<String> {

        final description:Array<String> = [];

        if (node.leadingComments != null) {
            for (comment in node.leadingComments) {
                description.push('_' + comment.content.trim().replace('_', '\\_') + '_');
            }
        }

        if (node.trailingComments != null) {
            if (description.length > 0) {
                description.push('');
                description.push('---');
                description.push('');
            }
            for (comment in node.trailingComments) {
                description.push('_' + comment.content.trim().replace('_', '\\_') + '_');
            }
        }

        return description;

    }

    function makePositionLink(text:String, uri:DocumentUri, node:Node, ?extra:String):String {
        return '[${text}](${uri}#${node.pos.line},${node.pos.column})' + (extra != null ? ' ($extra)' : '');
    }

    function makeBeatDeclHover(beatDecl:NBeatDecl, uri:DocumentUri, content:String, lens:Lens, ?origin:Node):Hover {
        final description:Array<String> = [];

        // Add any comments as description
        final comments = hoverDescriptionForNode(beatDecl);
        if (comments.length > 0) {
            for (comment in comments) {
                description.push(comment);
            }
            description.push("");
            description.push("---");
            description.push("");
        }

        // Add character interactions
        final characters = lens.findBeatCharacters(beatDecl);
        if (characters.length > 0) {
            // Group by interaction type
            final dialogs = new Map<String, Bool>();
            final accessed = new Map<String, Bool>();

            final dialogTargets = [];
            final otherTargets = [];

            for (ref in characters) {

                if (HxType.getClass(ref.origin) == NDialogueStatement && !dialogs.exists(ref.target.name)) {
                    if (!dialogs.exists(ref.target.name)) {
                        dialogs.set(ref.target.name, true);
                        dialogTargets.push(makePositionLink('**' + characterName(ref.target) + '**', uri, ref.target));
                    }
                }

                if (HxType.getClass(ref.origin) == NAccess && !accessed.exists(ref.target.name)) {
                    if (!dialogs.exists(ref.target.name) && !accessed.exists(ref.target.name)) {
                        accessed.set(ref.target.name, true);
                        otherTargets.push(makePositionLink('' + characterName(ref.target) + '', uri, ref.target));
                    }
                }
            }

            final targets = dialogTargets.concat(otherTargets);
            if (targets.length > 0) {
                description.push("- Characters: " + targets.join(', '));
            }

            description.push("");
            description.push("---");
            description.push("");
        }

        // Add state fields
        final readFields = lens.findReadStateFields(beatDecl);
        final modifiedFields = lens.findModifiedStateFields(beatDecl);
        final characterReadFields = lens.findReadCharacterFields(beatDecl);
        final characterModifiedFields = lens.findModifiedCharacterFields(beatDecl);
        if (readFields.length > 0 || modifiedFields.length > 0 || characterReadFields.length > 0 || characterModifiedFields.length > 0) {

            final stateTargets = [];
            final usedStateTargets = new NodeIdMap<Bool>();

            if (modifiedFields.length > 0) {
                for (ref in modifiedFields) {
                    if (!usedStateTargets.exists(ref.target.id)) {
                        usedStateTargets.set(ref.target.id, true);
                        stateTargets.push('**' + makePositionLink(ref.target.name, uri, ref.target) + '**');
                    }
                }
            }

            if (readFields.length > 0) {
                for (ref in readFields) {
                    if (!usedStateTargets.exists(ref.target.id)) {
                        usedStateTargets.set(ref.target.id, true);
                        stateTargets.push(makePositionLink(ref.target.name, uri, ref.target));
                    }
                }
            }

            if (stateTargets.length > 0) {
                description.push('- State: ' + stateTargets.join(', '));
            }

            final characters = [];
            final usedCharacters = new NodeIdMap<Bool>();

            if (characterModifiedFields.length > 0) {
                for (ref in characterModifiedFields) {
                    final refCharacter = lens.getFirstParentOfType(ref.target, NCharacterDecl);
                    if (!usedCharacters.exists(refCharacter.id)) {
                        usedCharacters.set(refCharacter.id, true);
                        characters.push(refCharacter);
                    }
                }
            }

            if (characterReadFields.length > 0) {
                for (ref in characterReadFields) {
                    final refCharacter = lens.getFirstParentOfType(ref.target, NCharacterDecl);
                    if (!usedCharacters.exists(refCharacter.id)) {
                        usedCharacters.set(refCharacter.id, true);
                        characters.push(refCharacter);
                    }
                }
            }

            for (character in characters) {

                final characterTargets = [];
                final usedCharacterTargets = new NodeIdMap<Bool>();

                if (characterModifiedFields.length > 0) {
                    for (ref in characterModifiedFields) {
                        final refCharacter = lens.getFirstParentOfType(ref.target, NCharacterDecl);
                        if (refCharacter.id == character.id) {
                            usedCharacterTargets.set(ref.target.id, true);
                            characterTargets.push('**' + makePositionLink(ref.target.name, uri, ref.target) + '**');
                        }
                    }
                }

                if (characterReadFields.length > 0) {
                    for (ref in characterReadFields) {
                        if (!usedCharacterTargets.exists(ref.target.id)) {
                            final refCharacter = lens.getFirstParentOfType(ref.target, NCharacterDecl);
                            if (refCharacter.id == character.id) {
                                usedCharacterTargets.set(ref.target.id, true);
                                characterTargets.push(makePositionLink(ref.target.name, uri, ref.target));
                            }
                        }
                    }
                }

                description.push('- ${characterName(character)}: ' + characterTargets.join(', '));
            }

            description.push("");
            description.push("---");
            description.push("");
        }

        final incomingBeats = lens.findReferencesToBeat(beatDecl);
        final outgoingBeats = lens.findOutboundBeats(beatDecl);

        if (incomingBeats.length > 0 || outgoingBeats.length > 0) {

            // Add incoming beats (references to this beat)
            if (incomingBeats.length > 0) {
                final targets = [];
                for (ref in incomingBeats) {
                    final incoming = lens.getFirstParentOfType(ref.origin, NBeatDecl);
                    if (incoming != null) {
                        targets.push(makePositionLink(incoming.name, uri, incoming));
                    }
                }
                description.push("- From: " + targets.join(', '));
            }

            // Add outgoing beats
            if (outgoingBeats.length > 0) {
                final callTargets = [];
                final transitionTargets = [];
                for (ref in outgoingBeats) {
                    if (ref.origin is NTransition) {
                        transitionTargets.push(makePositionLink(ref.target.name, uri, ref.target));
                    }
                    else {
                        callTargets.push(makePositionLink(ref.target.name, uri, ref.target));
                    }
                }
                if (transitionTargets.length > 0) {
                    description.push("- To: " + transitionTargets.join(', '));
                }
                if (callTargets.length > 0) {
                    description.push("- Calling: " + callTargets.join(', '));
                }
            }

            description.push("");
            description.push("---");
            description.push("");
        }

        while (description[description.length-1] == "" || description[description.length-1] == "---") description.pop();

        return makeHover(
            hoverTitle('Beat', beatDecl.name),
            description,
            content,
            origin ?? beatDecl
        );
    }

    function makeStateDeclHover(stateDecl:NStateDecl, content:String):Hover {

        return makeHover(hoverTitle('State'), hoverDescriptionForNode(stateDecl), content, stateDecl);

    }

    function makeCharacterDeclHover(characterDecl:NCharacterDecl, content:String, ?pos:loreline.Position):Hover {

        return makeHover(hoverTitle('Character', characterName(characterDecl)), hoverDescriptionForNode(characterDecl), content, characterDecl, pos);

    }

    function makeFunctionHover(func:NFunctionDecl, content:String, lens:Lens, lorelinePos:loreline.Position):Hover {

        #if hscript
        var expr = null;
        try {
            expr = lens.getHscriptExpr(func, lorelinePos);
        }
        catch (e:Dynamic) {}
        if (expr != null) {

            final codeToHscript = lens.getFuncHscript(func).codeToHscript;
            final exprPos = codeToHscript.toLorelinePos(func.pos, expr.pmin, expr.pmax);

            // TODO: this is pretty basic for now, could be improved at some point
            final title = switch expr.e {
                case EConst(CString(s)): 'String';
                case EConst(CFloat(f)): 'Number';
                case EConst(CInt(v)): 'Number';
                case EConst(c): 'Constant';
                case EIdent('false'): 'Boolean';
                case EIdent('true'): 'Boolean';
                case EIdent('null'): 'Null';
                case EIdent(v): 'Identifier';
                case EVar(n, t, e): 'Variable';
                case EParent(e): 'Parenthesis';
                case EBlock(e): 'Block';
                case EField(e, f): 'Field';
                case EBinop(op, e1, e2): 'Binary operation';
                case EUnop(op, prefix, e): 'Unary operation';
                case ECall(e, params): 'Function';
                case EIf(cond, e1, e2): 'Condition';
                case EWhile(cond, e): 'Loop';
                case EFor(v, it, e): 'Iteration';
                case EBreak: 'Break';
                case EContinue: 'Continue';
                case EFunction(args, e, name, ret): 'Function';
                case EReturn(e): 'Return';
                case EArray(e, index): 'Array access';
                case EArrayDecl(e): 'Array';
                case ENew(cl, params): 'New';
                case EThrow(e): 'Throw';
                case ETry(e, v, t, ecatch): 'Try';
                case EObject(fl): 'Object';
                case ETernary(cond, e1, e2): 'Ternary operation';
                case ESwitch(e, cases, defaultExpr): 'Switch';
                case EDoWhile(cond, e): 'Do... while';
                case EMeta(name, args, e): 'Metadata';
                case ECheckType(e, t): 'Type';
            }

            return makeHover(hoverTitle(title ?? 'Expression'), hoverDescriptionForNode(func), content, func, exprPos);
        }
        #end

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

        return makeHover(hoverTitle('Function', name), hoverDescriptionForNode(func), content, func, lorelinePos);

    }

    function makeChoiceHover(choice:NChoiceStatement, content:String):Hover {

        return makeHover(hoverTitle('Choice'), hoverDescriptionForNode(choice), content, choice);

    }

    function makeImportHover(importNode:NImportStatement, content:String):Hover {

        return makeHover(hoverTitle('Import'), hoverDescriptionForNode(importNode), content, importNode);

    }

    function makeExprHover(expr:NExpr, content:String):Hover {

        return makeHover(printLoreline(expr), hoverDescriptionForNode(expr), content, expr);

    }

    function makeObjectFieldHover(field:NObjectField, content:String):Hover {

        return makeHover(hoverTitle('Field', field.name), hoverDescriptionForNode(field), content, field);

    }

    function makeAccessHover(access:NAccess, content:String, lens:Lens):Hover {

        final resolved = lens.resolveAccess(access);
        if (resolved != null) {

            if (resolved is NCharacterDecl) {
                return makeCharacterDeclHover(cast resolved, content, access.pos);
            }
            else if (resolved is NFunctionDecl) {
                return makeFunctionDeclHover(cast resolved, content, access.pos);
            }

            final parentCharacter = lens.getFirstParentOfType(resolved, NCharacterDecl);
            final parentState = lens.getFirstParentOfType(resolved, NStateDecl);

            var key = 'Field';
            if (parentCharacter != null) {
                key = characterName(parentCharacter);
                key = 'Character field (' + key + ')';
            }
            else if (parentState != null) {
                key = 'State field';
            }

            return makeHover(hoverTitle(key, access.name), hoverDescriptionForNode(access), content, access);
        }
        else {
            final parent = lens.getParentNode(access);

            if (parent is NCall) {
                return makeHover(hoverTitle('Function', access.name + '()'), hoverDescriptionForNode(access), content, access);
            }
            else if (parent is NArrayAccess) {
                return makeHover(hoverTitle('Array access', access.name + '[]'), hoverDescriptionForNode(access), content, access);
            }
            else {
                return makeHover(hoverTitle('Access', access.name), hoverDescriptionForNode(access), content, access);
            }
        }

        return null;

    }

    function makeArrayAccessHover(access:NArrayAccess, content:String, lens:Lens):Hover {

        return makeHover(hoverTitle('Array access', printLoreline(access.target) + '[]'), hoverDescriptionForNode(access), content, access);

    }

    function makeDialogueStatementHover(expr:NDialogueStatement, content:String, lens:Lens):Hover {

        final characterDecl = lens.findCharacterFromDialogue(expr);
        if (characterDecl != null) {
            return makeHover(hoverTitle('Dialogue', null, characterName(characterDecl)), hoverDescriptionForNode(expr), content, expr);
        }

        return makeHover(hoverTitle('Dialogue'), hoverDescriptionForNode(expr), content, expr);

    }

    function printLoreline(node:Node):String {

        final printer = new Printer();

        printer.enableComments = false;

        return printer.print(node).trim();

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

        updateDocumentIfNeeded(params.textDocument.uri);

        final ast = documents.get(params.textDocument.uri);
        if (ast == null) return [];

        final content = documentContents.get(params.textDocument.uri);
        if (content == null) return [];

        final printer = new SymbolPrinter(content);
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
     * Loreline positions are 1-based for both line and column
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

            while (i < content.length) {
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
    function fromLorelinePosition(lorelinePos:loreline.Position):loreline.lsp.Protocol.Position {
        return {
            // Convert from 1-based to 0-based indexing
            line: lorelinePos.line - 1,
            character: lorelinePos.column - 1
        };
    }

    function rangeFromLorelinePosition(lorelinePos:loreline.Position, content:String):loreline.lsp.Protocol.Range {
        final start = fromLorelinePosition(lorelinePos);
        final end = fromLorelinePosition(lorelinePos.withOffset(content, lorelinePos.length));
        return {
            start: start,
            end: end
        };
    }

    function firstLineRange(range:Range, content:String):Range {
        // Skip preceding whitespace lines
        var lineStart = range.start.line;
        final lines = content.split("\n");
        while (lineStart < lines.length && lines[lineStart].trim().length == 0) {
            lineStart++;
        }

        // Find end of first non-empty line
        var lineEnd = lineStart;
        var charEnd = lines[lineEnd].length;

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