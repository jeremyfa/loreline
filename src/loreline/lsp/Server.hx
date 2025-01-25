package loreline.lsp;

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
        js.Node.console.log(message);
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
                    change: 1  // TextDocumentSyncKind.Full
                },
                // Enable completion with specific trigger characters
                completionProvider: {
                    resolveProvider: false,  // We don't provide additional resolution
                    triggerCharacters: [
                        ".",  // For field access (character.name)
                        "$",  // For interpolation ($variable)
                        "<",  // For tags (<happy>)
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
        Sys.exit(shutdown ? 0 : 1);
    }

    /**
     * Handle document open
     */
    function handleDidOpenTextDocument(params:{textDocument:TextDocumentItem}) {
        final doc = params.textDocument;
        updateDocument(doc.uri, doc.text);
    }

    /**
     * Handle document change
     */
    function handleDidChangeTextDocument(params:{
        textDocument:VersionedTextDocumentIdentifier,
        contentChanges:Array<TextDocumentContentChangeEvent>
    }) {
        if (params.contentChanges.length > 0) {
            // We're using full document sync, so just take the last change
            final change = params.contentChanges[params.contentChanges.length - 1];
            updateDocument(params.textDocument.uri, change.text);
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
    function updateDocument(uri:String, content:String) {
        documentContents.set(uri, content);
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

            // TODO: Add semantic validation
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
        final ast = documents.get(params.textDocument.uri);
        if (ast == null) return [];

        // TODO: Calculate completions based on context:
        // - Beat names after ->
        // - Character names before :
        // - Variable names after $ or ${
        // - Tag names after < or </
        return [];
    }

    /**
     * Handle definition request
     */
    function handleDefinition(params:{
        textDocument:TextDocumentIdentifier,
        position:Position
    }):Array<Location> {
        final result = [];

        onLog("handleDefinition");
        final uri = params.textDocument.uri;

        final ast = documents.get(uri);
        if (ast == null) return result;

        final content = documentContents.get(uri);
        final lorelinePos = toLorelinePosition(params.position, content);

        final lens = new Lens(ast);
        final node = lens.getNodeAtPosition(lorelinePos);
        onLog("DEF NODE: " + node != null ? Type.getClassName(Type.getClass(node)) : '-');

        if (node != null) {
            switch Type.getClass(node) {
                case NTransition:
                    final transition:NTransition = cast node;
                    final beatDecl = lens.findReferencedBeat(transition);
                    if (beatDecl != null) {
                        result.push({
                            uri: uri,
                            range: firstLineRange(rangeFromLorelinePosition(beatDecl.pos, content), content)
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

    function makeHover(title:String, description:Array<String>, content:String, node:Node, ?pos:loreline.Position, code:String = 'loreline'):Hover {

        final value:Array<String> = [];

        if (title != null) {
            if (code != null && code.length > 0) {
                value.push("```" + code);
            }
            value.push(title);
            if (code != null && code.length > 0) {
                value.push("```");
            }
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

        onLog("POS " + Json.stringify(params.position));
        onLog("LOR POS " + lorelinePos + ' offset=${lorelinePos.offset} column=${lorelinePos.column}');
        onLog('NODE: ' + (node != null ? Type.getClassName(Type.getClass(node)) : null));
        if (node != null) {
            return makeNodeHover(lens, content, node);
        }

        // TODO: Show hover information:
        // - Beat summary/contents
        // - Character properties
        // - Variable type/value
        // - Tag documentation
        return null;
    }

    function makeNodeHover(lens:Lens, content:String, node:Node):Null<Hover> {

        onLog(Json.stringify(node.pos.toJson()));

        switch Type.getClass(node) {
            case NBeatDecl:
                return makeBeatDeclHover(cast node, content);
            case NChoiceStatement:
                return makeChoiceHover(cast node, content);
            case NTransition:
                return makeExprHover(cast node, content);
            case NAccess:
                var access:NAccess = cast node;
                var parent = lens.getParentNode(access);
                if (parent is NCall) {
                    return makeExprHover(cast parent, content);
                }
                else if (parent is NArrayAccess) {
                    return makeExprHover(cast parent, content);
                }
                return makeExprHover(cast node, content);
            case NLiteral | NExpr | NAssign | NUnary | NBinary:
                return makeExprHover(cast node, content);
            case NIfStatement:
                return makeHover("if", null, content, node, null, "loreline.expression");
            case NStringLiteral | NDialogueStatement:
                return makeStatementHover(cast node, content);
            case NStringPart:
                var parent = node;
                do {
                    parent = lens.getParentNode(parent);
                    // if (parent != null) {
                    //     onLog("PARENT: " + Type.getClassName(Type.getClass(parent)));
                    // }
                }
                while (parent != null);

                final stringPart:NStringPart = cast node;

                switch stringPart.type {
                    case Raw(text):
                    case Expr(expr):
                        return makeNodeHover(lens, content, expr);
                    case Tag(closing, expr):
                        return makeHover("<" + printLoreline(expr) + ">", hoverDescriptionForNode(expr), content, stringPart);
                }

                final literal = lens.getParentOfType(node, NStringLiteral);

                if (literal != null) {
                    final literalParent = lens.getParentNode(literal);
                    if (literalParent != null && literalParent is NStringPart) {
                        final parentStringPart:NStringPart = cast literalParent;
                        switch parentStringPart.type {
                            case Raw(text):
                            case Expr(expr):
                                return makeNodeHover(lens, content, expr);
                            case Tag(closing, expr):
                                return makeHover("<" + printLoreline(expr) + ">", hoverDescriptionForNode(expr), content, parentStringPart);
                        }
                    }

                    final partIndex = literal.parts.indexOf(stringPart);
                    if (literal.quotes == Unquoted) {
                        if (partIndex > 0) {
                            // In unquoted strings, we ignore space between leading tags and actual text
                            var keepWhitespace = true;
                            for (i in 0...partIndex) {
                                switch literal.parts[i].type {
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
                                switch literal.parts[partIndex].type {
                                    case Raw(text):
                                        final spaces = text.uLength() - text.ltrim().uLength();
                                        if (spaces > 0) {
                                            return makeHover(text.trim(), hoverDescriptionForNode(literal), content, stringPart, stringPart.pos.withOffset(content, spaces, stringPart.pos.length - spaces));
                                        }
                                    case _:
                                }
                            }
                        }
                    }
                    else if (literal.quotes == DoubleQuotes) {
                        if (literal.parts.length == 1) {
                            switch literal.parts[0].type {
                                case Raw(text):
                                    return makeHover(text.trim(), hoverDescriptionForNode(literal), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 2));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == 0) {
                            switch literal.parts[0].type {
                                case Raw(text):
                                    return makeHover(text.trim(), hoverDescriptionForNode(literal), content, stringPart, stringPart.pos.withOffset(content, -1, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                        else if (partIndex == literal.parts.length - 1) {
                            switch literal.parts[literal.parts.length - 1].type {
                                case Raw(text):
                                    return makeHover(text.trim(), hoverDescriptionForNode(literal), content, stringPart, stringPart.pos.withOffset(content, 0, stringPart.pos.length + 1));
                                case Expr(expr):
                                case Tag(closing, expr):
                            }
                        }
                    }
                }

                switch stringPart.type {
                    case Raw(text):
                        return makeHover(text.trim(), hoverDescriptionForNode(cast node), content, stringPart);
                    case Expr(expr):
                    case Tag(closing, expr):
                }

            case _:
        }
        return null;

    }

    function hoverDescriptionForNode(node:AstNode):Array<String> {

        final description:Array<String> = [];

        if (node.leadingComments != null) {
            for (comment in node.leadingComments) {
                description.push(comment.content);
            }
        }

        if (node.trailingComments != null) {
            if (description.length > 0) {
                description.push('');
                description.push('---');
                description.push('');
            }
            for (comment in node.trailingComments) {
                description.push(comment.content);
            }
        }

        return description;

    }

    function makeBeatDeclHover(beatDecl:NBeatDecl, content:String):Hover {

        return makeHover('beat ${beatDecl.name}', hoverDescriptionForNode(beatDecl), content, beatDecl);

    }

    function makeChoiceHover(choice:NChoiceStatement, content:String):Hover {

        return makeHover('choice', hoverDescriptionForNode(choice), content, choice);

    }

    function makeExprHover(expr:NExpr, content:String):Hover {

        return makeHover(printLoreline(expr), hoverDescriptionForNode(expr), content, expr, null, 'loreline.expression');

    }

    function makeStatementHover(expr:NExpr, content:String):Hover {

        return makeHover(printLoreline(expr), hoverDescriptionForNode(expr), content, expr);

    }

    function printLoreline(node:Node):String {

        final printer = new Printer();

        printer.enableComments = false;

        return printer.print(node).trim();

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