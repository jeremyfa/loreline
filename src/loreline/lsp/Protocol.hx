package loreline.lsp;

/**
 * LSP Message types
 */
enum abstract MessageType(Int) {
    var Error = 1;
    var Warning = 2;
    var Info = 3;
    var Log = 4;
}

/**
 * Response error codes
 */
enum abstract ErrorCodes(Int) {
    var ParseError = -32700;
    var InvalidRequest = -32600;
    var MethodNotFound = -32601;
    var InvalidParams = -32602;
    var InternalError = -32603;
    var ServerNotInitialized = -32002;
    var UnknownErrorCode = -32001;
}

/**
 * Either type helper
 */
abstract EitherType<T1, T2>(Dynamic) from T1 from T2 to T1 to T2 {}

/**
 * Base message type
 */
typedef Message = {
    var jsonrpc:String;
}

/**
 * Request ID type (can be number or string)
 */
abstract RequestId(Dynamic) from Int from String to Int to String {}

/**
 * Request message
 */
typedef RequestMessage = Message & {
    var ?id:RequestId;
    var method:String;
    var ?params:Any;
}

/**
 * Response message
 */
typedef ResponseMessage = Message & {
    var id:RequestId;
    var ?result:Any;
    var ?error:ResponseError;
}

/**
 * Response error
 */
typedef ResponseError = {
    var code:ErrorCodes;
    var message:String;
    var ?data:Any;
}

/**
 * Notification message
 */
typedef NotificationMessage = Message & {
    var method:String;
    var ?params:Any;
}

/**
 * Position in a text document
 */
typedef Position = {
    var line:Int;
    var character:Int;
}

/**
 * A range in a text document
 */
typedef Range = {
    var start:Position;
    var end:Position;
}

/**
 * Location in a text document
 */
typedef Location = {
    var uri:String;
    var range:Range;
}

/**
 * Text document identifier
 */
typedef TextDocumentIdentifier = {
    var uri:String;
}

/**
 * Versioned text document identifier
 */
typedef VersionedTextDocumentIdentifier = TextDocumentIdentifier & {
    var version:Int;
}

/**
 * Text document item
 */
typedef TextDocumentItem = {
    var uri:String;
    var languageId:String;
    var version:Int;
    var text:String;
}

/**
 * Text document content change event
 */
typedef TextDocumentContentChangeEvent = {
    var ?range:Range;
    var ?rangeLength:Int;
    var text:String;
}

/**
 * Initialization parameters
 */
typedef InitializeParams = {
    var processId:Null<Int>;
    var ?rootPath:String;
    var ?rootUri:String;
    var capabilities:ClientCapabilities;
    var ?trace:String;
    var ?workspaceFolders:Array<WorkspaceFolder>;
}

/**
 * Client capabilities
 */
typedef ClientCapabilities = {
    var ?workspace:WorkspaceClientCapabilities;
    var ?textDocument:TextDocumentClientCapabilities;
    var ?experimental:Any;
}

/**
 * Server capabilities
 */
typedef ServerCapabilities = {
    var ?textDocumentSync:TextDocumentSyncOptions;
    var ?completionProvider:CompletionOptions;
    var ?hoverProvider:Bool;
    var ?definitionProvider:Bool;
    var ?referencesProvider:Bool;
    var ?documentSymbolProvider:Bool;
    var ?documentFormattingProvider:Bool;
}

/**
 * Text document sync options
 */
typedef TextDocumentSyncOptions = {
    var ?openClose:Bool;
    var ?change:Int;
    var ?save:SaveOptions;
}

/**
 * Save options
 */
typedef SaveOptions = {
    var ?includeText:Bool;
}

/**
 * Completion provider options
 */
typedef CompletionOptions = {
    var ?resolveProvider:Bool;
    var ?triggerCharacters:Array<String>;
}

/**
 * Completion item kinds
 */
enum abstract CompletionItemKind(Int) {
    var Text = 1;
    var Method = 2;
    var Function = 3;
    var Constructor = 4;
    var Field = 5;
    var Variable = 6;
    var Class = 7;
    var Interface = 8;
    var Module = 9;
    var Property = 10;
    var Unit = 11;
    var Value = 12;
    var Enum = 13;
    var Keyword = 14;
    var Snippet = 15;
    var Color = 16;
    var File = 17;
    var Reference = 18;
    var Folder = 19;
    var EnumMember = 20;
    var Constant = 21;
    var Struct = 22;
    var Event = 23;
    var Operator = 24;
    var TypeParameter = 25;
}

/**
 * Completion item
 */
typedef CompletionItem = {
    var label:String;
    var ?kind:CompletionItemKind;
    var ?detail:String;
    var ?documentation:String;
    var ?sortText:String;
    var ?filterText:String;
    var ?insertText:String;
    var ?textEdit:TextEdit;
    var ?additionalTextEdits:Array<TextEdit>;
    var ?commitCharacters:Array<String>;
    var ?command:Command;
    var ?data:Any;
}

/**
 * Text edit
 */
typedef TextEdit = {
    var range:Range;
    var newText:String;
}

/**
 * Command
 */
typedef Command = {
    var title:String;
    var command:String;
    var ?arguments:Array<Any>;
}

/**
 * Markup content
 */
typedef MarkupContent = {
    var kind:MarkupKind;
    var value:String;
}

/**
 * Markup kinds
 */
enum abstract MarkupKind(String) {
    var PlainText = "plaintext";
    var Markdown = "markdown";
}

/**
 * Hover
 */
typedef Hover = {
    var contents:EitherType<MarkupContent, EitherType<MarkedString, Array<MarkedString>>>;
    var ?range:Range;
}

/**
 * Marked string (deprecated, use MarkupContent instead)
 */
typedef MarkedString = EitherType<String, {
    var language:String;
    var value:String;
}>;

/**
 * Diagnostic severity
 */
enum abstract DiagnosticSeverity(Int) {
    var Error = 1;
    var Warning = 2;
    var Information = 3;
    var Hint = 4;
}

/**
 * Diagnostic information
 */
typedef Diagnostic = {
    var range:Range;
    var ?severity:DiagnosticSeverity;
    var ?code:String;
    var ?source:String;
    var message:String;
    var ?relatedInformation:Array<DiagnosticRelatedInformation>;
}

/**
 * Related diagnostic information
 */
typedef DiagnosticRelatedInformation = {
    var location:Location;
    var message:String;
}

/**
 * Workspace folder
 */
typedef WorkspaceFolder = {
    var uri:String;
    var name:String;
}

/**
 * Workspace client capabilities
 */
typedef WorkspaceClientCapabilities = {
    var ?applyEdit:Bool;
    var ?workspaceEdit:WorkspaceEditCapabilities;
    var ?didChangeConfiguration:DynamicRegistrationCapabilities;
    var ?didChangeWatchedFiles:DynamicRegistrationCapabilities;
    var ?symbol:DynamicRegistrationCapabilities;
    var ?executeCommand:DynamicRegistrationCapabilities;
}

/**
 * Text document client capabilities
 */
typedef TextDocumentClientCapabilities = {
    var ?synchronization:TextDocumentSyncClientCapabilities;
    var ?completion:CompletionClientCapabilities;
    var ?hover:HoverClientCapabilities;
    var ?definition:DefinitionClientCapabilities;
}

/**
 * Dynamic registration capabilities
 */
typedef DynamicRegistrationCapabilities = {
    var ?dynamicRegistration:Bool;
}

/**
 * Workspace edit capabilities
 */
typedef WorkspaceEditCapabilities = {
    var ?documentChanges:Bool;
}

/**
 * Completion client capabilities
 */
typedef CompletionClientCapabilities = DynamicRegistrationCapabilities & {
    var ?completionItem:{
        var ?snippetSupport:Bool;
        var ?commitCharactersSupport:Bool;
        var ?documentationFormat:Array<String>;
        var ?deprecatedSupport:Bool;
        var ?preselectSupport:Bool;
    };
    var ?completionItemKind:{
        var ?valueSet:Array<Int>;
    };
    var ?contextSupport:Bool;
}

/**
 * Hover client capabilities
 */
typedef HoverClientCapabilities = DynamicRegistrationCapabilities & {
    var ?contentFormat:Array<String>;
}

/**
 * Definition client capabilities
 */
typedef DefinitionClientCapabilities = DynamicRegistrationCapabilities & {
    var ?linkSupport:Bool;
}

/**
 * Text document sync client capabilities
 */
typedef TextDocumentSyncClientCapabilities = DynamicRegistrationCapabilities & {
    var ?willSave:Bool;
    var ?willSaveWaitUntil:Bool;
    var ?didSave:Bool;
}

/**
 * Completion trigger kinds
 */
enum abstract CompletionTriggerKind(Int) {
    var Invoked = 1;
    var TriggerCharacter = 2;
    var TriggerForIncompleteCompletions = 3;
}

/**
 * Completion context
 */
typedef CompletionContext = {
    var triggerKind:CompletionTriggerKind;
    var ?triggerCharacter:String;
}

/**
 * Document symbol kinds
 */
enum abstract SymbolKind(Int) {
    var File = 1;
    var Module = 2;
    var Namespace = 3;
    var Package = 4;
    var Class = 5;
    var Method = 6;
    var Property = 7;
    var Field = 8;
    var Constructor = 9;
    var Enum = 10;
    var Interface = 11;
    var Function = 12;
    var Variable = 13;
    var Constant = 14;
    var String = 15;
    var Number = 16;
    var Boolean = 17;
    var Array = 18;
    var Object = 19;
    var Key = 20;
    var Null = 21;
    var EnumMember = 22;
    var Struct = 23;
    var Event = 24;
    var Operator = 25;
    var TypeParameter = 26;
}

/**
 * Document symbol
 */
typedef DocumentSymbol = {
    var name:String;
    var detail:String;
    var kind:SymbolKind;
    var deprecated:Bool;
    var range:Range;
    var selectionRange:Range;
    var ?children:Array<DocumentSymbol>;
}

/**
 * Formatting options
 */
typedef FormattingOptions = {
    var tabSize:Int;
    var insertSpaces:Bool;
    var ?trimTrailingWhitespace:Bool;
    var ?insertFinalNewline:Bool;
    var ?trimFinalNewlines:Bool;
}
