package loreline.lsp;

import Type as HxType;
import haxe.Json;
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

    // Map of document URIs to their parsed ASTs
    final documents:Map<String, Script> = [];

    // Map of document URIs to their text content
    final documentContents:Map<String, String> = [];

    // Map of document URIs to their diagnostics
    final documentDiagnostics:Map<String, Array<Diagnostic>> = [];

    // Client capabilities from initialize request
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

    public function new() {}

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

            final result = switch (request.method) {
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
                    null;
                    // TODO
                    //handleReferences(cast request.params);

                case "textDocument/formatting":
                    handleDocumentFormatting(cast request.params);

                case _:
                    throw { code: ErrorCodes.MethodNotFound, message: 'Method not found: ${request.method}'};
            }

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

    /**
     * Update document content and parse
     */
    function updateDocument(uri:String, content:String, runDiagnostics:Bool = true) {
        documentContents.set(uri, content);

        if (runDiagnostics) {
            documentDiagnostics.set(uri, []);

            try {
                // Parse document and update AST
                final lexer = new Lexer(content);
                final parser = new Parser(lexer.tokenize());
                final ast = parser.parse();
                documents.set(uri, ast);

                // Check for parser errors
                final errors = parser.getErrors();
                if (errors != null && errors.length > 0) {
                    for (error in errors) {
                        addDiagnostic(uri, error.pos, error.message, DiagnosticSeverity.Error);
                    }
                }

                // Add semantic validation
                validateDocument(uri, ast);

            } catch (e:Error) {
                // Handle lexer/parser errors
                addDiagnostic(uri, e.pos, e.message, DiagnosticSeverity.Error);
            } catch (e:Dynamic) {
                // Handle unexpected errors
                addDiagnostic(uri, null, Std.string(e), DiagnosticSeverity.Error);
            }

            // Publish diagnostics
            publishDiagnostics(uri);
        } else {
            try {
                // Just update AST without diagnostics
                final lexer = new Lexer(content);
                final parser = new Parser(lexer.tokenize());
                documents.set(uri, parser.parse());
            } catch (_:Dynamic) {
                // Ignore parsing errors during editing
            }
        }
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
                    //if (beforeNode != null && beforeNode == lens.getFirstParentOfType(node, HxType.getClass(beforeNode))) {
                        node = beforeNode;
                    //}
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
                        final beforeNode = lens.getNodeAtPosition(lorelinePos.withOffset(content, -RE_IDENTIFIER_BEFORE.matched(0).uLength() - 1));
                        if (beforeNode == null || !(beforeNode is NAccess)) {
                            return [];
                        }
                        final access:NAccess = cast beforeNode;
                        resolved = lens.resolveAccess(access);
                    }
                    else if (RE_ARRAY_ACCESS_BEFORE.match(prevText)) {
                        final beforeNode = lens.getNodeAtPosition(lorelinePos.withOffset(content, -RE_ARRAY_ACCESS_BEFORE.matched(0).uLength() - 1));
                        if (beforeNode == null || !(beforeNode is NArrayAccess)) {
                            return [];
                        }
                        final access:NArrayAccess = cast beforeNode;
                        resolved = lens.resolveArrayAccess(access);
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
                    return getVariableCompletions(lens, node);

                case "<": // Tag completion
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

            // Add beat completions
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

            return items;
        }

        /*
        // Handle context-specific completion
        switch (HxType.getClass(node)) {
            case NTransition:
                // Complete beat names after ->
                final items:Array<CompletionItem> = [];
                for (beat in lens.getVisibleBeats(node)) {
                    items.push({
                        label: beat.name,
                        kind: CompletionItemKind.Class,
                        detail: "Beat",
                        insertText: beat.name,
                        insertTextMode: AsIs,
                        insertTextFormat: PlainText
                    });
                }
                return items;

            case NDialogueStatement:
                // Complete character names before :
                final dialogue:NDialogueStatement = cast node;
                if (dialogue.character == null || dialogue.character.length == 0) {
                    final items:Array<CompletionItem> = [];
                    for (character in lens.getVisibleCharacters()) {
                        items.push({
                            label: character.name,
                            kind: CompletionItemKind.Class,
                            detail: "Character",
                            insertText: character.name,
                            insertTextMode: AsIs,
                            insertTextFormat: PlainText
                        });
                    }
                    return items;
                }

            case NStringPart:
                final stringPart:NStringPart = cast node;
                switch (stringPart.type) {
                    case Raw(_):
                        return []; // No completion in raw text
                    case Expr(expr):
                        return getVariableCompletions(lens, expr);
                    case Tag(closing, content):
                        return getTagCompletions(lens);
                }

            case NAccess:
                final access:NAccess = cast node;
                if (access.target == null) {
                    return getVariableCompletions(lens, node);
                }

            case _:
                // No specific completion
        }
        */

        return [];
    }

    /**
     * Get completion items for variables in scope
     */
    function getVariableCompletions(lens:Lens, node:Node):Array<CompletionItem> {
        final items:Array<CompletionItem> = [];

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
                            targetUri: uri,
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
                            targetUri: uri,
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
                            targetUri: uri,
                            // Full range of the beat declaration
                            targetRange: rangeFromLorelinePosition(beatDecl.pos, content),
                            // More precise range for the beat name
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, content), content),
                            // Range of the transition reference in the source
                            originSelectionRange: rangeFromLorelinePosition(transition.targetPos, content)
                        });
                    }

                case NDialogueStatement:
                    final dialogue:NDialogueStatement = cast node;
                    final characterDecl = lens.findCharacterFromDialogue(dialogue);
                    if (characterDecl != null) {
                        // Create a location link for the character definition
                        result.push({
                            targetUri: uri,
                            targetRange: rangeFromLorelinePosition(characterDecl.pos, content),
                            targetSelectionRange: firstLineRange(rangeFromLorelinePosition(characterDecl.pos, content), content),
                            originSelectionRange: rangeFromLorelinePosition(dialogue.characterPos, content)
                        });
                    }
            }
        }

        // TODO: Find definitions:
        // - Go to beat definition from transition
        // - Go to character definition from dialogue
        // - Go to variable definition from interpolation
        return result;
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

        final ast = documents.get(uri);
        if (ast == null) return null;

        final content = documentContents.get(uri);
        final lorelinePos = toLorelinePosition(params.position, content);

        final lens = new Lens(ast);
        final node = lens.getNodeAtPosition(lorelinePos);

        if (node != null) {
            return makeNodeHover(lens, uri, content, node);
        }

        // TODO: Show hover information:
        // - Beat summary/contents
        // - Character fields
        // - Variable type/value
        // - Tag documentation
        return null;
    }

    function makeNodeHover(lens:Lens, uri:DocumentUri, content:String, node:Node):Null<Hover> {

        onLog(Json.stringify(node.pos.toJson()));

        switch HxType.getClass(node) {
            case NBeatDecl:
                return makeBeatDeclHover(cast node, uri, content, lens);
            case NStateDecl:
                return makeStateDeclHover(cast node, content);
            case NCharacterDecl:
                return makeCharacterDeclHover(cast node, content);
            case NChoiceStatement:
                return makeChoiceHover(cast node, content);
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
                return makeDialogueStatementHover(cast node, content);
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
                        return makeNodeHover(lens, uri, content, expr);
                    case Tag(closing, expr):
                        return makeHover(hoverTitle('Tag', "&lt;" + printLoreline(expr) + "&gt;"), hoverDescriptionForNode(expr), content, stringPart);
                }

                final literal = lens.getFirstParentOfType(node, NStringLiteral);

                if (literal != null) {
                    final literalParent = lens.getParentNode(literal);
                    if (literalParent != null && literalParent is NStringPart) {
                        final parentStringPart:NStringPart = cast literalParent;
                        switch parentStringPart.partType {
                            case Raw(text):
                            case Expr(expr):
                                return makeNodeHover(lens, uri, content, expr);
                            case Tag(closing, expr):
                                return makeHover(hoverTitle('Tag', "&lt;" + printLoreline(expr) + "&gt;"), hoverDescriptionForNode(expr), content, parentStringPart);
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
                                            return makeHover(hoverTitle('Text'), hoverDescriptionForNode(literal.parts[partIndex]), content, stringPart, stringPart.pos.withOffset(content, spaces, stringPart.pos.length - spaces));
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
                                    return makeHover(hoverTitle('Text'), hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 2));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == 0) {
                            switch literal.parts[0].partType {
                                case Raw(text):
                                    return makeHover(hoverTitle('Text'), hoverDescriptionForNode(literal.parts[0]), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == literal.parts.length - 1) {
                            switch literal.parts[literal.parts.length - 1].partType {
                                case Raw(text):
                                    return makeHover(hoverTitle('Text'), hoverDescriptionForNode(literal.parts[literal.parts.length - 1]), content, stringPart, stringPart.pos.withOffset(content, 0, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                    }
                }

                switch stringPart.partType {
                    case Raw(text):
                        return makeHover(hoverTitle('Text'), hoverDescriptionForNode(stringPart), content, stringPart);
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
                    // final refType = HxType.getClass(ref.origin) == NTransition ? "transition" : "call";
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

    function makeChoiceHover(choice:NChoiceStatement, content:String):Hover {

        return makeHover(hoverTitle('Choice'), hoverDescriptionForNode(choice), content, choice);

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
                return makeHover(hoverTitle('Function call', access.name + '()'), hoverDescriptionForNode(access), content, access);
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

    function makeDialogueStatementHover(expr:NDialogueStatement, content:String):Hover {

        return makeHover(hoverTitle('Dialogue'), hoverDescriptionForNode(expr), content, expr);

    }

    function printLoreline(node:Node):String {

        final printer = new Printer();

        printer.enableComments = false;

        return printer.print(node).trim();

    }

    function characterName(character:NCharacterDecl):String {

        final nameExpr = character.get('name');
        return nameExpr != null ? printLoreline(nameExpr) : character.name;

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

        // TODO: Format document:
        // - Proper indentation
        // - Consistent spacing
        // - Line breaks between blocks
        return [];
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
     function toLorelinePosition(protocolPos:loreline.lsp.Protocol.Position, content:String, ?length:Int = 0):loreline.Position {
        // Convert from 0-based to 1-based indexing
        final line = protocolPos.line + 1;
        final column = protocolPos.character + 1;

        // Calculate absolute offset if content is provided
        final offset = computeLorelineOffset(line, column, content);

        return new loreline.Position(line, column, offset, length);
    }

    function computeLorelineOffset(line:Int, column:Int, content:String) {

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