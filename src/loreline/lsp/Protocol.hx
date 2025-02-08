package loreline.lsp;

// Language Server Protocol implementation for Haxe
// Based on LSP specification version 3.17

/**
 * A type for JSON-based RPC message identifiers
 */
abstract RequestId(Dynamic) from Int from String to Int to String {}

/**
 * URI type with basic validation
 */
abstract URI(String) {
	public inline function new(uri:String) {
		this = uri;
	}

	@:from public static function fromString(uri:String):URI {
		return new URI(uri);
	}

	@:to public function toString():String {
		return this;
	}
}

/**
 * Either type for handling union types in LSP
 */
abstract Either<T1, T2>(Dynamic) from T1 from T2 to T1 to T2 {}

/**
 * LSP Any type for extensibility
 */
typedef LSPAny = Dynamic;

/**
 * LSP Array type
 */
typedef LSPArray = Array<LSPAny>;

/**
 * LSP Object type
 */
typedef LSPObject = Dynamic;

/**
 * Message types supported by LSP
 */
enum abstract MessageType(Int) {
	var Error = 1;
	var Warning = 2;
	var Info = 3;
	var Log = 4;
	var Debug = 5; // Added in 3.18.0
}

/**
 * Error codes for LSP responses
 */
enum abstract ErrorCodes(Int) {
	// JSON RPC error codes
	var ParseError = -32700;
	var InvalidRequest = -32600;
	var MethodNotFound = -32601;
	var InvalidParams = -32602;
	var InternalError = -32603;

	// LSP reserved error ranges
	var jsonrpcReservedErrorRangeStart = -32099;
	var ServerNotInitialized = -32002;
	var UnknownErrorCode = -32001;
	var jsonrpcReservedErrorRangeEnd = -32000;

	// LSP error codes
	var lspReservedErrorRangeStart = -32899;
	var RequestFailed = -32803;
	var ServerCancelled = -32802;
	var ContentModified = -32801;
	var RequestCancelled = -32800;
	var lspReservedErrorRangeEnd = -32800;
}

/**
 * Base message interface
 */
typedef Message = {
	var jsonrpc:String; // Must be "2.0"
}

/**
 * Request message interface
 */
typedef RequestMessage = Message & {
	var id:RequestId;
	var method:String;
	var ?params:LSPAny;
}

/**
 * Response message interface
 */
typedef ResponseMessage = Message & {
	var id:RequestId;
	var ?result:LSPAny;
	var ?error:ResponseError;
}

/**
 * Response error interface
 */
typedef ResponseError = {
	var code:ErrorCodes;
	var message:String;
	var ?data:LSPAny;
}

/**
 * Notification message interface
 */
typedef NotificationMessage = Message & {
	var method:String;
	var ?params:LSPAny;
}

/**
 * Cancel params for request cancellation
 */
typedef CancelParams = {
	var id:RequestId;
}

/**
 * Progress token type
 */
typedef ProgressToken = Either<Int, String>;

/**
 * Progress params for reporting progress
 */
typedef ProgressParams = {
	var token:ProgressToken;
	var value:LSPAny;
}

/**
 * Position encodings supported by LSP 3.17+
 */
enum abstract PositionEncodingKind(String) {
	var UTF8 = "utf-8";
	var UTF16 = "utf-16"; // Default encoding
	var UTF32 = "utf-32";
}

/**
 * Position in a text document
 */
typedef Position = {
	/**
	 * Line position in a document (zero-based)
	 */
	var line:Int;

	/**
	 * Character offset on a line (zero-based)
	 * Interpretation depends on negotiated PositionEncodingKind
	 */
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
 * A location in a text document expressed as a range and a document URI
 */
typedef Location = {
	/**
	 * The URI of the document containing the location
	 */
	var uri:URI;

	/**
	 * The range in the document where the location exists
	 */
	var range:Range;
}

/**
 * Represents a related location in code. Provides additional metadata about
 * the relationship between locations when navigating code.
 */
typedef LocationLink = {
	/**
	 * Span of the origin of this link.
	 * Used as the underlined span for mouse interaction. Defaults to the word range at
	 * the definition position.
	 */
	var ?originSelectionRange:Range;

	/**
	 * The target resource identifier of this link
	 */
	var targetUri:URI;

	/**
	 * The full target range of this link. For example, if this link represents
	 * a function declaration, this would be the range of the entire function declaration.
	 */
	var targetRange:Range;

	/**
	 * The span of the target that should be highlighted, like the function name in
	 * a function declaration. Must be contained by the target range.
	 */
	var targetSelectionRange:Range;
}

/**
 * Diagnostic severities
 */
enum abstract DiagnosticSeverity(Int) {
	var Error = 1;
	var Warning = 2;
	var Information = 3;
	var Hint = 4;
}

/**
 * Diagnostic tags
 */
enum abstract DiagnosticTag(Int) {
	var Unnecessary = 1;
	var Deprecated = 2;
}

/**
 * Code description for diagnostics
 */
typedef CodeDescription = {
	var href:URI;
}

/**
 * A diagnostic represents a problem detected by a language service, like
 * a compiler error or warning.
 */
typedef Diagnostic = {
	/**
	 * The range at which the message applies
	 */
	var range:Range;

	/**
	 * The diagnostic's severity. Can be omitted. If omitted it is up to the
	 * client to interpret diagnostics as error, warning, info or hint.
	 */
	var ?severity:DiagnosticSeverity;

	/**
	 * The diagnostic's code, which usually appear in the user interface
	 * Can be a string or a number.
	 */
	var ?code:Either<Int, String>;

	/**
	 * An optional property to describe the error code.
	 * Requires the code field to be present.
	 */
	var ?codeDescription:CodeDescription;

	/**
	 * A human-readable string describing the source of this
	 * diagnostic, e.g. 'typescript' or 'super lint'.
	 */
	var ?source:String;

	/**
	 * The diagnostic's message. Should be a short, human-readable description
	 * of the problem being diagnosed.
	 */
	var message:String;

	/**
	 * Additional metadata about the diagnostic
	 */
	var ?tags:Array<DiagnosticTag>;

	/**
	 * An array of related diagnostic information, e.g. when symbol-names within
	 * a scope collide all definitions can be marked via this property.
	 */
	var ?relatedInformation:Array<DiagnosticRelatedInformation>;

	/**
	 * A data entry field that is preserved between a `textDocument/publishDiagnostics`
	 * notification and `textDocument/codeAction` request.
	 */
	var ?data:LSPAny;
}

/**
 * Additional information related to a primary diagnostic
 */
typedef DiagnosticRelatedInformation = {
	/**
	 * The location of this related diagnostic information
	 */
	var location:Location;

	/**
	 * The message of this related diagnostic information
	 */
	var message:String;
}

/**
 * Represents a command that should be triggered
 */
typedef Command = {
	/**
	 * Title of the command, like `save`
	 */
	var title:String;

	/**
	 * The identifier of the actual command handler
	 */
	var command:String;

	/**
	 * Arguments that the command handler should be invoked with
	 */
	var ?arguments:Array<LSPAny>;
}

/**
 * Markup content kinds
 */
enum abstract MarkupKind(String) {
	var PlainText = "plaintext";
	var Markdown = "markdown";
}

/**
 * Markup content
 */
typedef MarkupContent = {
	var kind:MarkupKind;
	var value:String;
}

/**
 * Text documents are identified by URIs and have a specific language.
 * This structure is used when opening a document in the editor.
 */
typedef TextDocumentItem = {
	/**
	 * The text document's URI - must be unique among all opened documents
	 */
	var uri:URI;

	/**
	 * The language identifier (e.g., 'haxe', 'javascript', etc.)
	 */
	var languageId:String;

	/**
	 * Version number that increases with each change
	 * Used to ensure sync between client and server
	 */
	var version:Int;

	/**
	 * The complete content of the document
	 */
	var text:String;
}

/**
 * Represents a reference to an opened text document
 */
typedef TextDocumentIdentifier = {
	var uri:URI;
}

/**
 * A versioned reference to a text document
 * Used to ensure changes are applied to the correct version
 */
typedef VersionedTextDocumentIdentifier = TextDocumentIdentifier & {
	var version:Int;
}

/**
 * Ways in which the text document can be synchronized
 */
enum abstract TextDocumentSyncKind(Int) {
	/**
	 * Documents should not be synced at all
	 */
	var None = 0;

	/**
	 * Full content is sent on each change
	 */
	var Full = 1;

	/**
	 * Only incremental updates are sent
	 */
	var Incremental = 2;
}

/**
 * Describes how a document changes. Can be either a full change
 * or an incremental change with a specific range.
 */
typedef TextDocumentContentChangeEvent = {
	/**
	 * The range of the document that changed
	 * If omitted, the entire content changed
	 */
	var ?range:Range;

	/**
	 * The length of the range that got replaced
	 * @deprecated Use range instead
	 */
	var ?rangeLength:Int;

	/**
	 * The new text for the provided range
	 * Or the entire new content if no range is provided
	 */
	var text:String;
}

/**
 * Save options that describe if the client should include
 * document content on save
 */
typedef SaveOptions = {
	var ?includeText:Bool;
}

/**
 * Document synchronization options
 */
typedef TextDocumentSyncOptions = {
	/**
	 * Whether open/close notifications should be sent
	 */
	var ?openClose:Bool;

	/**
	 * How content changes are synced
	 */
	var ?change:TextDocumentSyncKind;

	/**
	 * Whether save notifications should be sent
	 */
	var ?save:Either<Bool, SaveOptions>;

	/**
	 * Whether willSave notifications should be sent
	 */
	var ?willSave:Bool;

	/**
	 * Whether willSaveWaitUntil requests should be sent
	 */
	var ?willSaveWaitUntil:Bool;
}

/**
 * Language Feature: Completion Support
 */
/**
 * Completion trigger kinds describe how completion was initiated
 */
enum abstract CompletionTriggerKind(Int) {
	/**
	 * Completion was triggered by symbol input or manually
	 */
	var Invoked = 1;

	/**
	 * Completion was triggered by a trigger character
	 */
	var TriggerCharacter = 2;

	/**
	 * Completion was re-triggered as the current completion list is incomplete
	 */
	var TriggerForIncompleteCompletions = 3;
}

/**
 * Contains additional information about the context in which
 * completion was triggered
 */
typedef CompletionContext = {
	var triggerKind:CompletionTriggerKind;
	var ?triggerCharacter:String;
}

/**
 * Completion item kinds categorize the type of completion being offered
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
 * Completion item tags provide additional metadata
 */
enum abstract CompletionItemTag(Int) {
	var Deprecated = 1;
}

/**
 * Determines how inserted text should be interpreted
 */
enum abstract InsertTextFormat(Int) {
	/**
	 * Plain text insertion
	 */
	var PlainText = 1;

	/**
	 * Snippet with placeholders and variables
	 */
	var Snippet = 2;
}

/**
 * Controls the behavior of the indentation when inserting text
 */
enum abstract InsertTextMode(Int) {
	/**
	 * The insertion is done without any modification
	 */
	var AsIs = 1;

	/**
	 * The insertion is adjusted to match the current line's indentation
	 */
	var AdjustIndentation = 2;
}

/**
 * Additional details for a completion item's label
 */
typedef CompletionItemLabelDetails = {
	/**
	 * Additional details like function signatures
	 */
	var ?detail:String;

	/**
	 * More information like fully qualified names
	 */
	var ?description:String;
}

/**
 * A special edit that provides both insert and replace behaviors
 */
typedef InsertReplaceEdit = {
	var newText:String;
	var insert:Range;
	var replace:Range;
}

/**
 * Represents a completion item in the completion list
 */
typedef CompletionItem = {
	/**
	 * The label shown in the UI
	 */
	var label:String;

	/**
	 * Additional label details
	 */
	var ?labelDetails:CompletionItemLabelDetails;

	/**
	 * The kind of this completion item
	 */
	var ?kind:CompletionItemKind;

	/**
	 * Tags providing additional metadata
	 */
	var ?tags:Array<CompletionItemTag>;

	/**
	 * More detail like function signatures
	 */
	var ?detail:String;

	/**
	 * Documentation in plain text or markdown
	 */
	var ?documentation:Either<String, MarkupContent>;

	/**
	 * Whether this item is deprecated
	 * @deprecated Use tags instead
	 */
	var ?deprecated:Bool;

	/**
	 * Select this item when showing
	 */
	var ?preselect:Bool;

	/**
	 * Used for sorting completions
	 */
	var ?sortText:String;

	/**
	 * Used when filtering completions
	 */
	var ?filterText:String;

	/**
	 * Text to insert when selected
	 */
	var ?insertText:String;

	/**
	 * The format of the insert text
	 */
	var ?insertTextFormat:InsertTextFormat;

	/**
	 * Controls indentation adjustment
	 */
	var ?insertTextMode:InsertTextMode;

	/**
	 * Edit to apply when inserting this completion
	 */
	var ?textEdit:Either<TextEdit, InsertReplaceEdit>;

	/**
	 * Additional text edits to apply
	 */
	var ?additionalTextEdits:Array<TextEdit>;

	/**
	 * Characters that trigger completion acceptance
	 */
	var ?commitCharacters:Array<String>;

	/**
	 * Command to execute after insertion
	 */
	var ?command:Command;

	/**
	 * Data used by the completion resolver
	 */
	var ?data:LSPAny;
}

/**
 * Represents a collection of completion items
 */
typedef CompletionList = {
	/**
	 * This list isn't complete - further typing should retrigger completion
	 */
	var isIncomplete:Bool;

	/**
	 * The completion items
	 */
	var items:Array<CompletionItem>;
}

/**
 * Language Feature: Hover Support
 */
/**
 * Represents the hover information shown in tooltips
 */
typedef Hover = {
	/**
	 * The hover's content
	 */
	var contents:Either<MarkupContent, Either<Array<MarkedString>, MarkedString>>;

	/**
	 * Optional range to highlight
	 */
	var ?range:Range;
}

/**
 * @deprecated Use MarkupContent instead
 */
typedef MarkedString = Either<String, {
	var language:String;
	var value:String;
}>;

/**
 * Language Feature: SignatureHelp Support
 */
/**
 * Information about a parameter
 */
typedef ParameterInformation = {
	/**
	 * The parameter's label
	 */
	var label:Either<String, Array<Int> /* [int, int] */>;

	/**
	 * Documentation for the parameter
	 */
	var ?documentation:Either<String, MarkupContent>;
}

/**
 * Information about a function signature
 */
typedef SignatureInformation = {
	/**
	 * The signature's label
	 */
	var label:String;

	/**
	 * Documentation for the signature
	 */
	var ?documentation:Either<String, MarkupContent>;

	/**
	 * Information about the parameters
	 */
	var ?parameters:Array<ParameterInformation>;

	/**
	 * The index of the active parameter
	 */
	var ?activeParameter:Int;
}

/**
 * Represents signature help information
 */
typedef SignatureHelp = {
	/**
	 * The available signatures
	 */
	var signatures:Array<SignatureInformation>;

	/**
	 * The active signature
	 */
	var ?activeSignature:Int;

	/**
	 * The active parameter
	 */
	var ?activeParameter:Int;
}

/**
 * Represents the various kinds of symbols that can exist in code.
 * These help IDEs display appropriate icons and organize symbol hierarchies.
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
 * Tags that can be applied to symbols to indicate special states
 */
enum abstract SymbolTag(Int) {
	/**
	 * Marks the symbol as deprecated. IDEs typically show these with strikethrough.
	 */
	var Deprecated = 1;
}

/**
 * Represents a symbol in a document with hierarchical information.
 * This allows IDEs to show accurate symbol trees in outline views.
 */
typedef DocumentSymbol = {
	/**
	 * The name shown in the UI
	 */
	var name:String;

	/**
	 * More detail (e.g., type information, signatures)
	 */
	var detail:String;

	/**
	 * The kind of symbol
	 */
	var kind:SymbolKind;

	/**
	 * Optional tags for this symbol
	 */
	var ?tags:Array<SymbolTag>;

	/**
	 * Indicates if this symbol is deprecated
	 * @deprecated Use tags instead
	 */
	var ?deprecated:Bool;

	/**
	 * Range covering the entire symbol definition
	 */
	var range:Range;

	/**
	 * Range for the symbol name specifically
	 */
	var selectionRange:Range;

	/**
	 * Children of this symbol
	 */
	var ?children:Array<DocumentSymbol>;
}

/**
 * Code Action support enables IDEs to offer quick fixes and refactorings
 */
/**
 * Describes the kind of code action being offered
 */
enum abstract CodeActionKind(String) {
	/**
	 * Empty kind
	 */
	var Empty = "";

	/**
	 * Base kind for quickfix actions
	 */
	var QuickFix = "quickfix";

	/**
	 * Base kind for refactoring actions
	 */
	var Refactor = "refactor";

	/**
	 * Base kind for refactoring extraction actions
	 */
	var RefactorExtract = "refactor.extract";

	/**
	 * Base kind for refactoring inline actions
	 */
	var RefactorInline = "refactor.inline";

	/**
	 * Base kind for refactoring rewrite actions
	 */
	var RefactorRewrite = "refactor.rewrite";

	/**
	 * Base kind for source actions
	 */
	var Source = "source";

	/**
	 * Base kind for organize imports actions
	 */
	var SourceOrganizeImports = "source.organizeImports";

	/**
	 * Base kind for fix all actions
	 */
	var SourceFixAll = "source.fixAll";
}

/**
 * Represents a code action that can be performed
 */
typedef CodeAction = {
	/**
	 * Title shown in the UI
	 */
	var title:String;

	/**
	 * Kind of the code action
	 */
	var ?kind:CodeActionKind;

	/**
	 * Diagnostics that this code action resolves
	 */
	var ?diagnostics:Array<Diagnostic>;

	/**
	 * Marks this as a preferred action
	 */
	var ?isPreferred:Bool;

	/**
	 * Marks that the action cannot currently be applied
	 */
	var ?disabled:{
		var reason:String;
	};

	/**
	 * The workspace edit this code action performs
	 */
	var ?edit:WorkspaceEdit;

	/**
	 * A command this code action executes
	 */
	var ?command:Command;

	/**
	 * Data used by the code action resolver
	 */
	var ?data:LSPAny;
}

/**
 * Workspace-level features and types
 */
/**
 * Represents a workspace folder
 */
typedef WorkspaceFolder = {
	/**
	 * The folder's URI
	 */
	var uri:URI;

	/**
	 * User-facing name of the folder
	 */
	var name:String;
}

/**
 * Describes changes to workspace folders
 */
typedef WorkspaceFoldersChangeEvent = {
	/**
	 * Added workspace folders
	 */
	var added:Array<WorkspaceFolder>;

	/**
	 * Removed workspace folders
	 */
	var removed:Array<WorkspaceFolder>;
}

/**
 * Represents a workspace edit with support for file operations
 */
typedef WorkspaceEdit = {
	/**
	 * Text document edits
	 */
	var ?changes:Map<String, Array<TextEdit>>;

	/**
	 * Document changes with optional version checking
	 */
	var ?documentChanges:Array<Either<TextDocumentEdit, Either<CreateFile, Either<RenameFile, DeleteFile>>>>;

	/**
	 * Change annotations
	 */
	var ?changeAnnotations:Map<String, ChangeAnnotation>;
}

/**
 * Represents a text document edit with version information
 */
typedef TextDocumentEdit = {
	/**
	 * The text document to change
	 */
	var textDocument:VersionedTextDocumentIdentifier;

	/**
	 * The edits to apply
	 */
	var edits:Array<Either<TextEdit, AnnotatedTextEdit>>;
}

/**
 * Text edit
 */
typedef TextEdit = {
	var range:Range;
	var newText:String;
}

/**
 * A special text edit with an annotation
 */
typedef AnnotatedTextEdit = TextEdit & {
	var annotationId:String;
}

/**
 * Describes a change annotation
 */
typedef ChangeAnnotation = {
	/**
	 * A human-readable description of the change
	 */
	var label:String;

	/**
	 * Whether the change needs explicit confirmation
	 */
	var ?needsConfirmation:Bool;

	/**
	 * A human-readable description of the change
	 */
	var ?description:String;
}

/**
 * File operation to create a file
 */
typedef CreateFile = {
	/**
	 * A create
	 */
	var kind:String; // Must be 'create'

	/**
	 * The resource to create
	 */
	var uri:String;

	/**
	 * Creation options
	 */
	var ?options:CreateFileOptions;

	/**
	 * An optional annotation identifier
	 */
	var ?annotationId:String;
}

/**
 * Options for creating a file
 */
typedef CreateFileOptions = {
	/**
	 * Overwrite existing file
	 */
	var ?overwrite:Bool;

	/**
	 * Ignore if exists
	 */
	var ?ignoreIfExists:Bool;
}

/**
 * File operation to rename a file
 */
typedef RenameFile = {
	/**
	 * A rename
	 */
	var kind:String; // Must be 'rename'

	/**
	 * The old (existing) location
	 */
	var oldUri:String;

	/**
	 * The new location
	 */
	var newUri:String;

	/**
	 * Rename options
	 */
	var ?options:RenameFileOptions;

	/**
	 * An optional annotation identifier
	 */
	var ?annotationId:String;
}

/**
 * Options for renaming a file
 */
typedef RenameFileOptions = {
	/**
	 * Overwrite target if existing
	 */
	var ?overwrite:Bool;

	/**
	 * Ignore if target exists
	 */
	var ?ignoreIfExists:Bool;
}

/**
 * File operation to delete a file
 */
typedef DeleteFile = {
	/**
	 * A delete
	 */
	var kind:String; // Must be 'delete'

	/**
	 * The file to delete
	 */
	var uri:String;

	/**
	 * Delete options
	 */
	var ?options:DeleteFileOptions;

	/**
	 * An optional annotation identifier
	 */
	var ?annotationId:String;
}

/**
 * Options for deleting a file
 */
typedef DeleteFileOptions = {
	/**
	 * Delete content recursively
	 */
	var ?recursive:Bool;

	/**
	 * Ignore if not exists
	 */
	var ?ignoreIfNotExists:Bool;
}

/**
 * Client Capabilities define what features a client (IDE/editor) supports.
 * These are sent to the server during initialization to negotiate features.
 */
typedef ClientCapabilities = {
	/**
	 * Workspace-specific client capabilities
	 */
	var ?workspace:WorkspaceClientCapabilities;

	/**
	 * Text document specific client capabilities
	 */
	var ?textDocument:TextDocumentClientCapabilities;

	/**
	 * Window specific client capabilities
	 */
	var ?window:WindowClientCapabilities;

	/**
	 * General client capabilities
	 */
	var ?general:GeneralClientCapabilities;

	/**
	 * Experimental client capabilities
	 */
	var ?experimental:LSPAny;
}

/**
 * General client capabilities that aren't specific to any feature
 */
typedef GeneralClientCapabilities = {
	/**
	 * Client capability that signals how stale requests are handled
	 */
	var ?staleRequestSupport:{
		/**
		 * The client will actively cancel the request
		 */
		var cancel:Bool;
		/**
		 * The list of requests for which the client will retry
		 * if the server returns ContentModified error
		 */
		var retryOnContentModified:Array<String>;
	};

	/**
	 * Client capabilities specific to regular expressions
	 */
	var ?regularExpressions:RegularExpressionsClientCapabilities;

	/**
	 * Client capabilities specific to markdown parsing
	 */
	var ?markdown:MarkdownClientCapabilities;

	/**
	 * The position encodings supported by the client
	 */
	var ?positionEncodings:Array<PositionEncodingKind>;
}

/**
 * Regular expression capabilities
 */
typedef RegularExpressionsClientCapabilities = {
	/**
	 * The engine's name
	 */
	var engine:String;

	/**
	 * The engine's version
	 */
	var ?version:String;
}

/**
 * Markdown parsing capabilities
 */
typedef MarkdownClientCapabilities = {
	/**
	 * The name of the parser
	 */
	var parser:String;

	/**
	 * The version of the parser
	 */
	var ?version:String;

	/**
	 * A list of HTML tags that the client supports in Markdown
	 */
	var ?allowedTags:Array<String>;
}

/**
 * Text document specific client capabilities
 */
typedef TextDocumentClientCapabilities = {
	/**
	 * Capabilities specific to synchronization
	 */
	var ?synchronization:TextDocumentSyncClientCapabilities;

	/**
	 * Capabilities specific to completion
	 */
	var ?completion:CompletionClientCapabilities;

	/**
	 * Capabilities specific to hover
	 */
	var ?hover:HoverClientCapabilities;

	/**
	 * Capabilities specific to signature help
	 */
	var ?signatureHelp:SignatureHelpClientCapabilities;

	/**
	 * Capabilities specific to go to declaration
	 */
	var ?declaration:DeclarationClientCapabilities;

	/**
	 * Capabilities specific to go to definition
	 */
	var ?definition:DefinitionClientCapabilities;

	/**
	 * Capabilities specific to type definition
	 */
	var ?typeDefinition:TypeDefinitionClientCapabilities;

	/**
	 * Capabilities specific to implementation
	 */
	var ?implementation:ImplementationClientCapabilities;

	/**
	 * Capabilities specific to references
	 */
	var ?references:ReferenceClientCapabilities;

	/**
	 * Capabilities specific to document highlight
	 */
	var ?documentHighlight:DocumentHighlightClientCapabilities;

	/**
	 * Capabilities specific to document symbol
	 */
	var ?documentSymbol:DocumentSymbolClientCapabilities;

	/**
	 * Capabilities specific to code action
	 */
	var ?codeAction:CodeActionClientCapabilities;

	/**
	 * Capabilities specific to code lens
	 */
	var ?codeLens:CodeLensClientCapabilities;

	/**
	 * Capabilities specific to document formatting
	 */
	var ?formatting:DocumentFormattingClientCapabilities;

	/**
	 * Capabilities specific to document range formatting
	 */
	var ?rangeFormatting:DocumentRangeFormattingClientCapabilities;

	/**
	 * Capabilities specific to document on type formatting
	 */
	var ?onTypeFormatting:DocumentOnTypeFormattingClientCapabilities;

	/**
	 * Capabilities specific to rename
	 */
	var ?rename:RenameClientCapabilities;

	/**
	 * Capabilities specific to linked editing range
	 */
	var ?linkedEditingRange:LinkedEditingRangeClientCapabilities;
}

/**
 * Server Capabilities define what features a language server provides.
 * This comprehensive type allows servers to declare their supported features,
 * enabling clients to adjust their behavior accordingly.
 */
typedef ServerCapabilities = {
	/**
	 * The position encoding the server picked from the encodings offered
	 * by the client via the client capability `general.positionEncodings`.
	 * If the client didn't provide any position encodings the only valid
	 * value that a server can return is 'utf-16'.
	 * If omitted it defaults to 'utf-16'.
	 */
	var ?positionEncoding:PositionEncodingKind;

	/**
	 * Defines how text documents are synced. Is either a detailed structure
	 * defining each notification or for backwards compatibility the
	 * TextDocumentSyncKind number. If omitted it defaults to
	 * `TextDocumentSyncKind.None`.
	 */
	var ?textDocumentSync:Either<TextDocumentSyncKind, TextDocumentSyncOptions>;

	/**
	 * Defines how notebook documents are synced.
	 * @since 3.17.0
	 */
	var ?notebookDocumentSync:Either<NotebookDocumentSyncOptions, NotebookDocumentSyncRegistrationOptions>;

	/**
	 * The server provides completion support.
	 */
	var ?completionProvider:CompletionOptions;

	/**
	 * The server provides hover support.
	 */
	var ?hoverProvider:Either<Bool, HoverOptions>;

	/**
	 * The server provides signature help support.
	 */
	var ?signatureHelpProvider:SignatureHelpOptions;

	/**
	 * The server provides go to declaration support.
	 * @since 3.14.0
	 */
	var ?declarationProvider:Either<Bool, Either<DeclarationOptions, DeclarationRegistrationOptions>>;

	/**
	 * The server provides goto definition support.
	 */
	var ?definitionProvider:Either<Bool, DefinitionOptions>;

	/**
	 * The server provides goto type definition support.
	 * @since 3.6.0
	 */
	var ?typeDefinitionProvider:Either<Bool, Either<TypeDefinitionOptions, TypeDefinitionRegistrationOptions>>;

	/**
	 * The server provides goto implementation support.
	 * @since 3.6.0
	 */
	var ?implementationProvider:Either<Bool, Either<ImplementationOptions, ImplementationRegistrationOptions>>;

	/**
	 * The server provides find references support.
	 */
	var ?referencesProvider:Either<Bool, ReferenceOptions>;

	/**
	 * The server provides document highlight support.
	 */
	var ?documentHighlightProvider:Either<Bool, DocumentHighlightOptions>;

	/**
	 * The server provides document symbol support.
	 */
	var ?documentSymbolProvider:Either<Bool, DocumentSymbolOptions>;

	/**
	 * The server provides code actions.
	 */
	var ?codeActionProvider:Either<Bool, CodeActionOptions>;

	/**
	 * The server provides code lens support.
	 */
	var ?codeLensProvider:CodeLensOptions;

	/**
	 * The server provides document link support.
	 */
	var ?documentLinkProvider:DocumentLinkOptions;

	/**
	 * The server provides color provider support.
	 * @since 3.6.0
	 */
	var ?colorProvider:Either<Bool, Either<DocumentColorOptions, DocumentColorRegistrationOptions>>;

	/**
	 * The server provides document formatting support.
	 */
	var ?documentFormattingProvider:Either<Bool, DocumentFormattingOptions>;

	/**
	 * The server provides document range formatting support.
	 */
	var ?documentRangeFormattingProvider:Either<Bool, DocumentRangeFormattingOptions>;

	/**
	 * The server provides document formatting on typing.
	 */
	var ?documentOnTypeFormattingProvider:DocumentOnTypeFormattingOptions;

	/**
	 * The server provides rename support.
	 */
	var ?renameProvider:Either<Bool, RenameOptions>;

	/**
	 * The server provides folding provider support.
	 * @since 3.10.0
	 */
	var ?foldingRangeProvider:Either<Bool, Either<FoldingRangeOptions, FoldingRangeRegistrationOptions>>;

	/**
	 * The server provides execute command support.
	 */
	var ?executeCommandProvider:ExecuteCommandOptions;

	/**
	 * The server provides selection range support.
	 * @since 3.15.0
	 */
	var ?selectionRangeProvider:Either<Bool, Either<SelectionRangeOptions, SelectionRangeRegistrationOptions>>;

	/**
	 * The server provides linked editing range support.
	 * @since 3.16.0
	 */
	var ?linkedEditingRangeProvider:Either<Bool, Either<LinkedEditingRangeOptions, LinkedEditingRangeRegistrationOptions>>;

	/**
	 * The server provides call hierarchy support.
	 * @since 3.16.0
	 */
	var ?callHierarchyProvider:Either<Bool, Either<CallHierarchyOptions, CallHierarchyRegistrationOptions>>;

	/**
	 * The server provides semantic tokens support.
	 * @since 3.16.0
	 */
	var ?semanticTokensProvider:Either<SemanticTokensOptions, SemanticTokensRegistrationOptions>;

	/**
	 * The server provides moniker support.
	 * @since 3.16.0
	 */
	var ?monikerProvider:Either<Bool, Either<MonikerOptions, MonikerRegistrationOptions>>;

	/**
	 * The server provides type hierarchy support.
	 * @since 3.17.0
	 */
	var ?typeHierarchyProvider:Either<Bool, Either<TypeHierarchyOptions, TypeHierarchyRegistrationOptions>>;

	/**
	 * The server provides inline values.
	 * @since 3.17.0
	 */
	var ?inlineValueProvider:Either<Bool, Either<InlineValueOptions, InlineValueRegistrationOptions>>;

	/**
	 * The server provides inlay hints.
	 * @since 3.17.0
	 */
	var ?inlayHintProvider:Either<Bool, Either<InlayHintOptions, InlayHintRegistrationOptions>>;

	/**
	 * The server has support for pull model diagnostics.
	 * @since 3.17.0
	 */
	var ?diagnosticProvider:Either<DiagnosticOptions, DiagnosticRegistrationOptions>;

	/**
	 * The server provides workspace symbol support.
	 */
	var ?workspaceSymbolProvider:Either<Bool, WorkspaceSymbolOptions>;

	/**
	 * Workspace specific server capabilities.
	 */
	var ?workspace:{
		/**
		 * The server supports workspace folders.
		 * @since 3.6.0
		 */
		var ?workspaceFolders:WorkspaceFoldersServerCapabilities;
		/**
		 * The server is interested in file notifications/requests.
		 * @since 3.16.0
		 */
		var ?fileOperations:{
			var ?didCreate:FileOperationRegistrationOptions;
			var ?willCreate:FileOperationRegistrationOptions;
			var ?didRename:FileOperationRegistrationOptions;
			var ?willRename:FileOperationRegistrationOptions;
			var ?didDelete:FileOperationRegistrationOptions;
			var ?willDelete:FileOperationRegistrationOptions;
		};
	};

	/**
	 * Experimental server capabilities.
	 */
	var ?experimental:LSPAny;
}

/**
 * Advanced Features: Semantic Tokens
 */
/**
 * Token types supported by semantic highlighting
 */
enum abstract SemanticTokenTypes(String) {
	var Namespace = "namespace";
	var Type = "type";
	var Class = "class";
	var Enum = "enum";
	var Interface = "interface";
	var Struct = "struct";
	var TypeParameter = "typeParameter";
	var Parameter = "parameter";
	var Variable = "variable";
	var Property = "property";
	var EnumMember = "enumMember";
	var Event = "event";
	var Function = "function";
	var Method = "method";
	var Macro = "macro";
	var Keyword = "keyword";
	var Modifier = "modifier";
	var Comment = "comment";
	var String = "string";
	var Number = "number";
	var Regexp = "regexp";
	var Operator = "operator";
	var Decorator = "decorator";
}

/**
 * Token modifiers for semantic highlighting
 */
enum abstract SemanticTokenModifiers(String) {
	var Declaration = "declaration";
	var Definition = "definition";
	var Readonly = "readonly";
	var Static = "static";
	var Deprecated = "deprecated";
	var Abstract = "abstract";
	var Async = "async";
	var Modification = "modification";
	var Documentation = "documentation";
	var DefaultLibrary = "defaultLibrary";
}

/**
 * Data structure for semantic token information
 */
typedef SemanticTokens = {
	/**
	 * Optional result id to support delta updates
	 */
	var ?resultId:String;

	/**
	 * Actual tokens encoded as relative positions
	 */
	var data:Array<Int>;
}

/**
 * Advanced Features: Linked Editing Ranges
 */
typedef LinkedEditingRanges = {
	/**
	 * A list of ranges that can be edited together
	 */
	var ranges:Array<Range>;

	/**
	 * Optional word pattern to validate content
	 */
	var ?wordPattern:String;
}

/**
 * Advanced Features: Moniker Support
 * Monikers help associate symbols across different indexes
 */
typedef Moniker = {
	/**
	 * The scheme of the moniker (e.g., 'tsc' or 'haxe')
	 */
	var scheme:String;

	/**
	 * The identifier of the moniker
	 */
	var identifier:String;

	/**
	 * The scope in which the moniker is unique
	 */
	var unique:UniquenessLevel;

	/**
	 * The moniker kind if known
	 */
	var ?kind:MonikerKind;
}

/**
 * Moniker uniqueness levels
 */
enum abstract UniquenessLevel(String) {
	var Document = "document";
	var Project = "project";
	var Group = "group";
	var Scheme = "scheme";
	var Global = "global";
}

/**
 * Moniker kinds
 */
enum abstract MonikerKind(String) {
	var Import = "import";
	var Export = "export";
	var Local = "local";
}

/**
 * Advanced Features: Type Hierarchy
 */
typedef TypeHierarchyItem = {
	/**
	 * The name of this item
	 */
	var name:String;

	/**
	 * The kind of this item
	 */
	var kind:SymbolKind;

	/**
	 * Tags associated with this item
	 */
	var ?tags:Array<SymbolTag>;

	/**
	 * More detail about this item
	 */
	var ?detail:String;

	/**
	 * The resource identifier of this item
	 */
	var uri:URI;

	/**
	 * The range enclosing this symbol
	 */
	var range:Range;

	/**
	 * The range for the symbol's name
	 */
	var selectionRange:Range;

	/**
	 * Data for resolving the item
	 */
	var ?data:LSPAny;
}

/**
 * Notebook Document Support
 */
typedef NotebookDocument = {
	/**
	 * The notebook document's URI
	 */
	var uri:URI;

	/**
	 * The type of the notebook
	 */
	var notebookType:String;

	/**
	 * The version number of this document
	 */
	var version:Int;

	/**
	 * Additional metadata stored with the notebook
	 */
	var ?metadata:LSPObject;

	/**
	 * The cells of the notebook
	 */
	var cells:Array<NotebookCell>;
}

/**
 * Represents a notebook cell
 */
typedef NotebookCell = {
	/**
	 * The cell's kind
	 */
	var kind:NotebookCellKind;

	/**
	 * The URI of the cell's text document content
	 */
	var document:URI;

	/**
	 * Additional metadata stored with the cell
	 */
	var ?metadata:LSPObject;

	/**
	 * The cell's execution summary
	 */
	var ?executionSummary:ExecutionSummary;
}

/**
 * Notebook cell kinds
 */
enum abstract NotebookCellKind(Int) {
	var Markup = 1;
	var Code = 2;
}

/**
 * Execution summary for a notebook cell
 */
typedef ExecutionSummary = {
	/**
	 * The execution order of the cell
	 */
	var executionOrder:Int;

	/**
	 * Whether the execution was successful
	 */
	var ?success:Bool;
}

/**
 * Capabilities that allow a client to signal dynamic registration support.
 * Dynamic registration allows servers to register and unregister features
 * after initialization.
 */
typedef DynamicRegistrationCapabilities = {
	/**
	 * Whether the client supports dynamic registration of this feature
	 */
	var ?dynamicRegistration:Bool;
}

/**
 * Text document sync client capabilities define how document content changes
 * are communicated between client and server
 */
typedef TextDocumentSyncClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Whether the client supports sending willSave notifications
	 */
	var ?willSave:Bool;

	/**
	 * Whether the client supports sending a willSaveWaitUntil request and
	 * waiting for edits before saving
	 */
	var ?willSaveWaitUntil:Bool;

	/**
	 * Whether the client supports sending didSave notifications
	 */
	var ?didSave:Bool;
}

/**
 * Completion client capabilities define what completion features a client supports,
 * like snippets, documentation formats, and auto-completion behavior
 */
typedef CompletionClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Specific capabilities of the `CompletionItem`
	 */
	var ?completionItem:{
		/**
		 * Client supports snippets as insert text
		 */
		var ?snippetSupport:Bool;
		/**
		 * Client supports commit characters
		 */
		var ?commitCharactersSupport:Bool;
		/**
		 * Documentation format supported
		 */
		var ?documentationFormat:Array<MarkupKind>;
		/**
		 * Client supports deprecated items
		 */
		var ?deprecatedSupport:Bool;
		/**
		 * Client supports preselect items
		 */
		var ?preselectSupport:Bool;
		/**
		 * Client supports tags on completion items
		 */
		var ?tagSupport:{
			var valueSet:Array<CompletionItemTag>;
		};
		/**
		 * Client supports insert/replace edit mode
		 */
		var ?insertReplaceSupport:Bool;
		/**
		 * Properties the client can resolve lazily
		 */
		var ?resolveSupport:{
			var properties:Array<String>;
		};
		/**
		 * Client supports insert text modes
		 */
		var ?insertTextModeSupport:{
			var valueSet:Array<InsertTextMode>;
		};
		/**
		 * Client supports completion item label details
		 */
		var ?labelDetailsSupport:Bool;
	};

	/**
	 * The client supports completion item kinds
	 */
	var ?completionItemKind:{
		var ?valueSet:Array<CompletionItemKind>;
	};

	/**
	 * The client supports sending context information
	 */
	var ?contextSupport:Bool;

	/**
	 * The client's default insert text mode
	 */
	var ?insertTextMode:InsertTextMode;
}

/**
 * Hover client capabilities define what hover features a client supports,
 * like content format and dynamic updates
 */
typedef HoverClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Client supports the following content formats for hover
	 */
	var ?contentFormat:Array<MarkupKind>;
}

/**
 * Signature help capabilities define how function signatures are displayed
 * and managed in the client
 */
typedef SignatureHelpClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * The client supports the following `SignatureInformation` properties
	 */
	var ?signatureInformation:{
		/**
		 * Client supports the following content formats
		 */
		var ?documentationFormat:Array<MarkupKind>;
		/**
		 * Client capabilities specific to parameter information
		 */
		var ?parameterInformation:{
			/**
			 * Client supports processing label offsets
			 */
			var ?labelOffsetSupport:Bool;
		};
		/**
		 * Client supports the `activeParameter` property
		 */
		var ?activeParameterSupport:Bool;
	};

	/**
	 * The client supports sending context information
	 */
	var ?contextSupport:Bool;
}

/**
 * Declaration client capabilities define how go-to-declaration is supported
 */
typedef DeclarationClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Whether the client supports additional metadata in links
	 */
	var ?linkSupport:Bool;
}

/**
 * Definition client capabilities define how go-to-definition is supported
 */
typedef DefinitionClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Whether the client supports additional metadata in links
	 */
	var ?linkSupport:Bool;
}

/**
 * Type definition client capabilities define how go-to-type-definition is supported
 */
typedef TypeDefinitionClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Whether the client supports additional metadata in links
	 */
	var ?linkSupport:Bool;
}

/**
 * Implementation client capabilities define how go-to-implementation is supported
 */
typedef ImplementationClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Whether the client supports additional metadata in links
	 */
	var ?linkSupport:Bool;
}

/**
 * Reference client capabilities define how find-references is supported
 */
typedef ReferenceClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Document highlight client capabilities define how symbol highlighting works
 */
typedef DocumentHighlightClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Document symbol client capabilities define how symbol information is presented
 */
typedef DocumentSymbolClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Specific capabilities for the `SymbolKind` property
	 */
	var ?symbolKind:{
		/**
		 * The symbol kind values the client supports
		 */
		var ?valueSet:Array<SymbolKind>;
	};

	/**
	 * The client supports hierarchical document symbols
	 */
	var ?hierarchicalDocumentSymbolSupport:Bool;

	/**
	 * The client supports tags on `SymbolInformation`
	 */
	var ?tagSupport:{
		/**
		 * The tags supported by the client
		 */
		var valueSet:Array<SymbolTag>;
	};

	/**
	 * The client supports an additional label shown in UI
	 */
	var ?labelSupport:Bool;
}

/**
 * Code action client capabilities define how code actions are handled
 */
typedef CodeActionClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * The client supports code action literals
	 */
	var ?codeActionLiteralSupport:{
		/**
		 * The code action kind is supported
		 */
		var codeActionKind:{
			/**
			 * The code action kind values the client supports
			 */
			var valueSet:Array<CodeActionKind>;
		};
	};

	/**
	 * Whether code action supports the `isPreferred` property
	 */
	var ?isPreferredSupport:Bool;

	/**
	 * Whether code action supports the `disabled` property
	 */
	var ?disabledSupport:Bool;

	/**
	 * Whether code action supports the `data` property
	 */
	var ?dataSupport:Bool;

	/**
	 * Whether the client supports resolving additional properties
	 */
	var ?resolveSupport:{
		/**
		 * Properties that a client can resolve lazily
		 */
		var properties:Array<String>;
	};

	/**
	 * Whether the client honors change annotations
	 */
	var ?honorsChangeAnnotations:Bool;
}

/**
 * Code lens client capabilities define how code lenses are handled
 */
typedef CodeLensClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Document formatting client capabilities
 */
typedef DocumentFormattingClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Document range formatting client capabilities
 */
typedef DocumentRangeFormattingClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Document on type formatting client capabilities
 */
typedef DocumentOnTypeFormattingClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Rename client capabilities define how symbol renaming is handled
 */
typedef RenameClientCapabilities = DynamicRegistrationCapabilities & {
	/**
	 * Client supports testing validity before rename
	 */
	var ?prepareSupport:Bool;

	/**
	 * Client supports handling of prepare default behavior
	 */
	var ?prepareSupportDefaultBehavior:PrepareSupportDefaultBehavior;

	/**
	 * Whether the client honors change annotations
	 */
	var ?honorsChangeAnnotations:Bool;
}

/**
 * Linked editing range client capabilities
 */
typedef LinkedEditingRangeClientCapabilities = DynamicRegistrationCapabilities;

/**
 * Window client capabilities define what window/UI features the client supports
 */
typedef WindowClientCapabilities = {
	/**
	 * Whether the client supports server-initiated progress
	 */
	var ?workDoneProgress:Bool;

	/**
	 * Capabilities specific to showMessage requests
	 */
	var ?showMessage:ShowMessageRequestClientCapabilities;

	/**
	 * Client capabilities for the show document request
	 */
	var ?showDocument:ShowDocumentClientCapabilities;
}

/**
 * Workspace client capabilities define what workspace-level features are supported
 */
typedef WorkspaceClientCapabilities = {
	/**
	 * The client supports applying batch edits to the workspace
	 */
	var ?applyEdit:Bool;

	/**
	 * Capabilities specific to `WorkspaceEdit`
	 */
	var ?workspaceEdit:WorkspaceEditClientCapabilities;

	/**
	 * Capabilities specific to the `workspace/didChangeConfiguration` notification
	 */
	var ?didChangeConfiguration:DynamicRegistrationCapabilities;

	/**
	 * Capabilities specific to the `workspace/didChangeWatchedFiles` notification
	 */
	var ?didChangeWatchedFiles:DidChangeWatchedFilesClientCapabilities;

	/**
	 * Capabilities specific to the `workspace/symbol` request
	 */
	var ?symbol:WorkspaceSymbolClientCapabilities;

	/**
	 * Capabilities specific to the `workspace/executeCommand` request
	 */
	var ?executeCommand:DynamicRegistrationCapabilities;

	/**
	 * The client has support for workspace folders
	 */
	var ?workspaceFolders:Bool;

	/**
	 * The client supports `workspace/configuration` requests
	 */
	var ?configuration:Bool;

	/**
	 * Capabilities specific to semantic tokens workspace requests
	 */
	var ?semanticTokens:SemanticTokensWorkspaceClientCapabilities;

	/**
	 * Capabilities specific to code lenses workspace requests
	 */
	var ?codeLens:CodeLensWorkspaceClientCapabilities;

	/**
	 * The client has support for file requests/notifications
	 */
	var ?fileOperations:FileOperationsClientCapabilities;
}

/**
 * Additional client capabilities
 */
/**
 * Message request client capabilities
 */
typedef ShowMessageRequestClientCapabilities = {
	/**
	 * Capabilities specific to the `MessageActionItem`
	 */
	var ?messageActionItem:{
		/**
		 * Whether the client supports additional attributes
		 */
		var ?additionalPropertiesSupport:Bool;
	};
}

/**
 * Show document client capabilities
 */
typedef ShowDocumentClientCapabilities = {
	/**
	 * The client has support for showing documents
	 */
	var support:Bool;
}

/**
 * Workspace edit client capabilities
 */
typedef WorkspaceEditClientCapabilities = {
	/**
	 * The client supports versioned document changes
	 */
	var ?documentChanges:Bool;

	/**
	 * The resource operations the client supports
	 */
	var ?resourceOperations:Array<ResourceOperationKind>;

	/**
	 * The failure handling strategy supported by the client
	 */
	var ?failureHandling:FailureHandlingKind;

	/**
	 * Whether the client normalizes line endings
	 */
	var ?normalizesLineEndings:Bool;

	/**
	 * Whether the client supports change annotations
	 */
	var ?changeAnnotationSupport:{
		/**
		 * Whether the client groups edits with equal labels
		 */
		var ?groupsOnLabel:Bool;
	};
}

/**
 * File operation client capabilities
 */
typedef FileOperationsClientCapabilities = {
	/**
	 * Whether the client supports dynamic registration
	 */
	var ?dynamicRegistration:Bool;

	/**
	 * The client has support for sending didCreateFiles notifications
	 */
	var ?didCreate:Bool;

	/**
	 * The client has support for sending willCreateFiles requests
	 */
	var ?willCreate:Bool;

	/**
	 * The client has support for sending didRenameFiles notifications
	 */
	var ?didRename:Bool;

	/**
	 * The client has support for sending willRenameFiles requests
	 */
	var ?willRename:Bool;

	/**
	 * The client has support for sending didDeleteFiles notifications
	 */
	var ?didDelete:Bool;

	/**
	 * The client has support for sending willDeleteFiles requests
	 */
	var ?willDelete:Bool;
}

/**
 * Base interface for options that support progress reporting
 */
typedef WorkDoneProgressOptions = {
	/**
	 * Whether the server supports work done progress for this feature
	 */
	var ?workDoneProgress:Bool;
}

/**
 * Options for configuring the completion feature on the server.
 * These options tell the client what special behaviors the server supports
 * for code completion.
 */
typedef CompletionOptions = WorkDoneProgressOptions & {
	/**
	 * Characters that trigger completion automatically when typed.
	 * For example, '.' might trigger member completions.
	 */
	var ?triggerCharacters:Array<String>;

	/**
	 * Characters that automatically commit a completion when typed.
	 * For example, ';' might commit a statement completion.
	 */
	var ?allCommitCharacters:Array<String>;

	/**
	 * Whether the server supports resolving additional completion item
	 * properties after a completion item has been selected.
	 */
	var ?resolveProvider:Bool;

	/**
	 * The server supports the following completion item properties
	 */
	var ?completionItem:{
		/**
		 * The server has support for completion item label details
		 */
		var ?labelDetailsSupport:Bool;
	};
}

/**
 * Options that define how the server handles hover requests.
 * Hover provides contextual information when a user hovers over code.
 */
typedef HoverOptions = WorkDoneProgressOptions & {}

/**
 * Options for configuring function signature help.
 * This helps users understand function parameters as they type.
 */
typedef SignatureHelpOptions = WorkDoneProgressOptions & {
	/**
	 * Characters that trigger signature help automatically.
	 * For example, '(' might show function parameter help.
	 */
	var ?triggerCharacters:Array<String>;

	/**
	 * Characters that re-trigger signature help after it's already showing.
	 * For example, ',' might re-trigger to show the next parameter.
	 */
	var ?retriggerCharacters:Array<String>;
}

/**
 * Options for the go-to-declaration feature.
 * This allows users to navigate to where a symbol is declared.
 */
typedef DeclarationOptions = WorkDoneProgressOptions & {}

/**
 * Options for the go-to-definition feature.
 * This allows users to navigate to where a symbol is defined.
 */
typedef DefinitionOptions = WorkDoneProgressOptions & {}

/**
 * Options for the go-to-type-definition feature.
 * This allows users to navigate to where a type is defined.
 */
typedef TypeDefinitionOptions = WorkDoneProgressOptions & {}

/**
 * Options for the go-to-implementation feature.
 * This allows users to navigate to where an interface is implemented.
 */
typedef ImplementationOptions = WorkDoneProgressOptions & {}

/**
 * Options for the find-references feature.
 * This helps users find all references to a symbol.
 */
typedef ReferenceOptions = WorkDoneProgressOptions & {}

/**
 * Options for document highlight feature.
 * This highlights all occurrences of a symbol in the current document.
 */
typedef DocumentHighlightOptions = WorkDoneProgressOptions & {}

/**
 * Options for document symbol provider.
 * This provides a list of symbols in the current document.
 */
typedef DocumentSymbolOptions = WorkDoneProgressOptions & {
	/**
	 * A human-readable label that helps distinguish this symbol provider
	 */
	var ?label:String;
}

/**
 * Options for code actions.
 * Code actions provide quick fixes and refactoring options.
 */
typedef CodeActionOptions = WorkDoneProgressOptions & {
	/**
	 * CodeActionKinds that this server may return
	 */
	var ?codeActionKinds:Array<CodeActionKind>;

	/**
	 * Whether the server supports resolving additional properties
	 */
	var ?resolveProvider:Bool;
}

/**
 * Options for code lens.
 * Code lenses provide actionable contextual information inline.
 */
typedef CodeLensOptions = WorkDoneProgressOptions & {
	/**
	 * Whether the server supports resolving additional code lens properties
	 */
	var ?resolveProvider:Bool;
}

/**
 * Options for workspace symbol provider.
 * This allows searching for symbols across the workspace.
 */
typedef WorkspaceSymbolOptions = WorkDoneProgressOptions & {
	/**
	 * Whether the server supports resolving additional properties
	 */
	var ?resolveProvider:Bool;
}

/**
 * Client capabilities for watching files in the workspace
 */
typedef DidChangeWatchedFilesClientCapabilities = {
	/**
	 * Whether the client supports dynamic registration
	 */
	var ?dynamicRegistration:Bool;

	/**
	 * Whether the client has support for relative patterns
	 */
	var ?relativePatternSupport:Bool;
}

/**
 * Client capabilities for workspace symbol features
 */
typedef WorkspaceSymbolClientCapabilities = {
	/**
	 * Symbol request supports dynamic registration
	 */
	var ?dynamicRegistration:Bool;

	/**
	 * Specific capabilities for the `SymbolKind` property
	 */
	var ?symbolKind:{
		var ?valueSet:Array<SymbolKind>;
	};

	/**
	 * The client supports tags on symbols
	 */
	var ?tagSupport:{
		var valueSet:Array<SymbolTag>;
	};

	/**
	 * The client supports partial workspace symbol results
	 */
	var ?resolveSupport:{
		/**
		 * The properties that a client can resolve lazily
		 */
		var properties:Array<String>;
	};
}

/**
 * Client capabilities for semantic tokens in the workspace
 */
typedef SemanticTokensWorkspaceClientCapabilities = {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client
	 */
	var ?refreshSupport:Bool;
}

/**
 * Client capabilities for code lens in the workspace
 */
typedef CodeLensWorkspaceClientCapabilities = {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client
	 */
	var ?refreshSupport:Bool;
}

/**
 * The kinds of resource operations that can be performed
 */
enum abstract ResourceOperationKind(String) {
	/**
	 * Supports creating new files and folders
	 */
	var Create = "create";

	/**
	 * Supports renaming existing files and folders
	 */
	var Rename = "rename";

	/**
	 * Supports deleting existing files and folders
	 */
	var Delete = "delete";
}

/**
 * How the client should handle failures during a workspace edit
 */
enum abstract FailureHandlingKind(String) {
	/**
	 * Applying changes stops after the first error
	 */
	var Abort = "abort";

	/**
	 * All operations are executed transactionally
	 */
	var Transactional = "transactional";

	/**
	 * Changes are applied as a transaction only for text changes
	 */
	var TextOnlyTransactional = "textOnlyTransactional";

	/**
	 * Client tries to undo the operations already executed
	 */
	var Undo = "undo";
}

/**
 * PrepareSupportDefaultBehavior defines how the client handles the
 * preparation phase of a rename operation when explicit prepare support
 * (`prepareProvider`) is not available from the server.
 *
 * This was introduced to help standardize rename behavior across clients
 * when servers don't implement explicit rename preparation. Before this,
 * clients would have varying default behaviors which could lead to
 * inconsistent user experiences.
 *
 * The value indicates the strategy the client uses to determine what text
 * to select for renaming when the server doesn't provide explicit guidance.
 */
enum abstract PrepareSupportDefaultBehavior(Int) {
	/**
	 * The client's default behavior is to select the identifier according
	 * to the language's syntax rules.
	 *
	 * For example, in most programming languages, when renaming a variable,
	 * the client would automatically select the whole variable name based on
	 * standard identifier rules (like alphanumeric characters and underscores).
	 * This provides a consistent experience that matches what users expect
	 * when renaming symbols in their code.
	 */
	var Identifier = 1;
}

/**
 * Information about the client that helps servers customize their behavior
 * based on the client's identity and version.
 */
typedef ClientInfo = {
	/**
	 * The name of the client as defined by the client implementation
	 */
	var name:String;

	/**
	 * The client's version
	 */
	var ?version:String;
}

/**
 * Trace value that indicates the level of verbosity the server should use
 * for logging its execution trace.
 */
enum abstract TraceValue(String) {
	/**
	 * No traces are logged
	 */
	var Off = "off";

	/**
	 * Only high-level messages are logged
	 */
	var Messages = "messages";

	/**
	 * Detailed trace information is logged
	 */
	var Verbose = "verbose";
}

/**
 * Parameters used during the initialization handshake between client and server.
 * These parameters define the capabilities of both sides and establish the
 * working context for the LSP session.
 */
typedef InitializeParams = {
	> WorkDoneProgressParams,

	/**
	 * The process ID of the parent process that started the server.
	 * Is null if the process has not been started by another process.
	 * If the parent process is not alive then the server should exit.
	 */
	var processId:Null<Int>;

	/**
	 * Information about the client
	 */
	var ?clientInfo:ClientInfo;

	/**
	 * The locale the client is currently showing the user interface in.
	 * This must not necessarily be the locale of the operating system.
	 * Uses IETF language tags as the value's syntax.
	 */
	var ?locale:String;

	/**
	 * The rootPath of the workspace. Is null if no folder is open.
	 * @deprecated in favour of rootUri.
	 */
	var ?rootPath:Null<String>;

	/**
	 * The rootUri of the workspace. Is null if no folder is open.
	 * If both rootPath and rootUri are set, rootUri wins.
	 * @deprecated in favour of workspaceFolders.
	 */
	var rootUri:Null<DocumentUri>;

	/**
	 * User provided initialization options
	 */
	var ?initializationOptions:LSPAny;

	/**
	 * The capabilities provided by the client (editor or tool)
	 */
	var capabilities:ClientCapabilities;

	/**
	 * The initial trace setting. If omitted trace is disabled ('off').
	 */
	var ?trace:TraceValue;

	/**
	 * The workspace folders configured in the client when the server starts.
	 * This property is only available if the client supports workspace folders.
	 * It can be null if the client supports workspace folders but none are
	 * configured.
	 */
	var ?workspaceFolders:Null<Array<WorkspaceFolder>>;
}

/**
 * The result returned by the server after initialization. It includes
 * the server's capabilities and additional information about the server.
 */
typedef InitializeResult = {
	/**
	 * The capabilities the language server provides
	 */
	var capabilities:ServerCapabilities;

	/**
	 * Information about the server
	 */
	var ?serverInfo:{
		/**
		 * The name of the server as defined by the server implementation
		 */
		var name:String;
		/**
		 * The server's version
		 */
		var ?version:String;
	};
}

/**
 * Known error codes for initialization errors
 */
enum abstract InitializeErrorCodes(Int) {
	/**
	 * If the protocol version provided by the client can't be handled by the server
	 * @deprecated This initialize error got replaced by client capabilities
	 */
	var UnknownProtocolVersion = 1;
}

/**
 * The data type returned when an initialization error occurs
 */
typedef InitializeError = {
	/**
	 * Indicates whether the client execute the following retry logic:
	 * (1) show the message provided by the ResponseError to the user
	 * (2) user selects retry or cancel
	 * (3) if user selected retry the initialize method is sent again.
	 */
	var retry:Bool;
}

/**
 * Parameters for progress reporting during work done
 */
typedef WorkDoneProgressParams = {
	/**
	 * An optional token that a server can use to report work done progress
	 */
	var ?workDoneToken:ProgressToken;
}

/**
 * Parameters for reporting partial results
 */
typedef PartialResultParams = {
	/**
	 * An optional token that a server can use to report partial results
	 */
	var ?partialResultToken:ProgressToken;
}

/**
 * The type used when reporting cancellation data from a diagnostic request
 */
typedef DiagnosticServerCancellationData = {
	var retriggerRequest:Bool;
}

/**
 * A special type for document URIs in the LSP protocol. While technically
 * a string, this type represents a properly formatted URI that points to a
 * text document. The URI format follows RFC 3986
 * (https://tools.ietf.org/html/rfc3986).
 *
 * Example formats:
 * - file:///c:/project/readme.md     (Windows file, forward slashes)
 * - file:///home/user/project/readme.md (Unix file)
 * - untitled:Untitled-1   (Unsaved document)
 */
typedef DocumentUri = String;

/**
 * Capabilities specific to the workspace/configuration request.
 */
typedef ConfigurationClientCapabilities = {
	/**
	 * Whether workspace/configuration requests are supported by the client
	 */
	var ?workspaceConfiguration:Bool;
}

/**
 * Capabilities specific to workspaceFolders.
 */
typedef WorkspaceFoldersServerCapabilities = {
	/**
	 * The server has support for workspace folders
	 */
	var ?supported:Bool;

	/**
	 * Whether the server wants to receive workspace folder
	 * change notifications. If a string is provided, it is treated as an ID
	 * under which the notification is registered on the client side.
	 */
	var ?changeNotifications:Either<String, Bool>;
}

/**
 * Workspace specific server capabilities
 */
typedef WorkspaceServerCapabilities = {
	/**
	 * The server supports workspace folder.
	 */
	var ?workspaceFolders:WorkspaceFoldersServerCapabilities;

	/**
	 * The server is interested in file notifications/requests.
	 */
	var ?fileOperations:{
		/**
		 * The server is interested in receiving didCreateFiles notifications.
		 */
		var ?didCreate:FileOperationRegistrationOptions;
		/**
		 * The server is interested in receiving willCreateFiles requests.
		 */
		var ?willCreate:FileOperationRegistrationOptions;
		/**
		 * The server is interested in receiving didRenameFiles notifications.
		 */
		var ?didRename:FileOperationRegistrationOptions;
		/**
		 * The server is interested in receiving willRenameFiles requests.
		 */
		var ?willRename:FileOperationRegistrationOptions;
		/**
		 * The server is interested in receiving didDeleteFiles notifications.
		 */
		var ?didDelete:FileOperationRegistrationOptions;
		/**
		 * The server is interested in receiving willDeleteFiles requests.
		 */
		var ?willDelete:FileOperationRegistrationOptions;
	};
}

/**
 * Static registration options to be returned in the initialize result.
 */
typedef StaticRegistrationOptions = {
	/**
	 * The id used to register the request. The id can be used to deregister
	 * the request again. See also Registration#id.
	 */
	var ?id:String;
}

/**
 * Error codes for initialization failures
 */
enum abstract InitializeErrorCode(Int) {
	/**
	 * The server has detected that the client has missing capabilities
	 * that are required for proper operation. This is considered a failure
	 * condition and the server should exit.
	 */
	var MissingCapability = 1;
}

/**
 * A pattern to describe in which file operation requests or notifications
 * the server is interested in. If a pattern matches both file and folder,
 * then the file pattern takes precedence over the folder pattern.
 */
typedef FileOperationPattern = {
	/**
	 * The glob pattern to match. Glob patterns can have the following syntax:
	 * - `*` to match one or more characters in a path segment
	 * - `?` to match on one character in a path segment
	 * - `**` to match any number of path segments, including none
	 * - `{}` to group conditions (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
	 * - `[]` to declare a range of characters to match in a path segment
	 *   (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
	 * - `[!...]` to negate a range of characters to match in a path segment
	 *   (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
	 */
	var glob:String;

	/**
	 * Whether to match files or folders with this pattern.
	 * If not specified, matches both files and folders.
	 */
	var ?matches:FileOperationPatternKind;

	/**
	 * Additional options used during matching.
	 * For example, case sensitivity settings.
	 */
	var ?options:FileOperationPatternOptions;
}

/**
 * A filter to describe in which file operation requests or notifications
 * the server is interested in. If a filter matches a file or folder, then
 * the request or notification will be handled; otherwise, it will be ignored.
 */
typedef FileOperationFilter = {
	/**
	 * A URI scheme, such as `file` or `untitled`. If not specified,
	 * matches files with any scheme.
	 */
	var ?scheme:String;

	/**
	 * The actual file operation pattern that this filter applies to.
	 * The pattern describes what files or folders this filter matches.
	 */
	var pattern:FileOperationPattern;
}

/**
 * Matching options for file operation patterns. These options allow
 * for more fine-grained control over how patterns are matched against
 * file system paths.
 */
typedef FileOperationPatternOptions = {
	/**
	 * Whether the pattern should be matched ignoring case.
	 * If true, then `example.ts` and `EXAMPLE.TS` would be considered equal.
	 */
	var ?ignoreCase:Bool;
}

/**
 * The options to register for file operations. This type is used when
 * a server wants to be notified about file system changes that match
 * specific patterns.
 */
typedef FileOperationRegistrationOptions = {
	/**
	 * An array of file operation filters that describe which file events
	 * the server is interested in. The server will only receive notifications
	 * for files that match at least one of these filters.
	 *
	 * For example, a server might register for all TypeScript files using
	 * a filter with a pattern like `**​/*.ts`.
	 */
	var filters:Array<FileOperationFilter>;
}

/**
 * The kind of file operation pattern, indicating whether the pattern
 * should match files, folders, or both.
 */
enum abstract FileOperationPatternKind(String) {
	/**
	 * The pattern matches on files only.
	 */
	var File = "file";

	/**
	 * The pattern matches on folders only.
	 */
	var Folder = "folder";
}

/**
 * Value-object describing what options should be used when formatting code.
 * These options give fine-grained control over how the formatter should behave,
 * allowing consistent formatting across different editors and tools.
 */
typedef FormattingOptions = {
	/**
	 * Size of a tab in spaces.
	 * This is a fundamental setting that affects how indentation is calculated.
	 * For example, if tabSize is 4, then one level of indentation will be 4 spaces wide.
	 */
	var tabSize:Int;

	/**
	 * Prefer spaces over tabs.
	 * When true, the formatter should use spaces for indentation even if the tab key is pressed.
	 * When false, actual tab characters will be used instead of spaces.
	 */
	var insertSpaces:Bool;

	/**
	 * Trim trailing whitespace on each line when formatting.
	 * This helps maintain clean code by removing unnecessary spaces at line ends.
	 *
	 * @since 3.15.0
	 */
	var ?trimTrailingWhitespace:Bool;

	/**
	 * Insert a newline character at the end of the file if one does not exist.
	 * This is considered a best practice in many programming communities and
	 * is required by some tools.
	 *
	 * @since 3.15.0
	 */
	var ?insertFinalNewline:Bool;

	/**
	 * Trim all newlines after the final newline at the end of the file.
	 * This helps maintain a single consistent final newline rather than
	 * having multiple blank lines at the end of files.
	 *
	 * @since 3.15.0
	 */
	var ?trimFinalNewlines:Bool;

	/**
	 * Allows for additional formatting options to be specified using a key-value pattern.
	 * This extensibility point lets language servers define their own custom formatting options.
	 *
	 * For example, a Haxe formatter might support options like:
	 * - "haxe.braceStyle": "allman"
	 * - "haxe.maxLineLength": 120
	 *
	 * The type of the value can be boolean, integer, or string.
	 */
	@:optional
	@:haxe.DynamicAccess
	var properties:Map<String, Either<Bool, Either<Int, String>>>;
}

/**
 * Parameters for document formatting requests. These are sent from the client
 * to request formatting of an entire document.
 */
typedef DocumentFormattingParams = {
	> WorkDoneProgressParams,

	/**
	 * The document to format
	 */
	var textDocument:TextDocumentIdentifier;

	/**
	 * The formatting options to use
	 */
	var options:FormattingOptions;
}

/**
 * Parameters for range formatting requests. These are sent from the client
 * to request formatting of a specific range within a document.
 */
typedef DocumentRangeFormattingParams = {
	> WorkDoneProgressParams,

	/**
	 * The document to format
	 */
	var textDocument:TextDocumentIdentifier;

	/**
	 * The range to format within the document
	 */
	var range:Range;

	/**
	 * The formatting options to use
	 */
	var options:FormattingOptions;
}

/**
 * Parameters for on-type formatting requests. These are sent when the server
 * should format the document after a specific character is typed.
 */
typedef DocumentOnTypeFormattingParams = {
	/**
	 * The document to format
	 */
	var textDocument:TextDocumentIdentifier;

	/**
	 * The position at which the character was typed that triggered formatting
	 */
	var position:Position;

	/**
	 * The character that triggered the formatting request, typically
	 * something like a closing brace or semicolon
	 */
	var ch:String;

	/**
	 * The formatting options to use
	 */
	var options:FormattingOptions;
}

/**
 * Options that control how notebook documents are synchronized between
 * client and server. Notebook synchronization is a newer feature that helps
 * IDEs support interactive notebooks like Jupyter.
 * @since 3.17.0
 */
typedef NotebookDocumentSyncOptions = {
	/**
	 * The notebooks to be synced. Each item specifies a notebook type
	 * and optionally what cells within that notebook should be synced.
	 */
	var notebookSelector:Array<{
		/**
		 * The notebook to be synced. Can be a string for the notebook type
		 * or a more detailed filter.
		 */
		var notebook:Either<String, NotebookDocumentFilter>;
		/**
		 * The cells of the matching notebook to be synced
		 */
		var ?cells:Array<{
			var language:String;
		}>;
	}>;

	/**
	 * Whether save notifications should be forwarded to the server.
	 * Will only be honored if mode === `notebook`.
	 */
	var ?save:Bool;
}

/**
 * Registration options for notebook synchronization. Extends the basic options
 * with registration-specific fields.
 * @since 3.17.0
 */
typedef NotebookDocumentSyncRegistrationOptions = NotebookDocumentSyncOptions &
	StaticRegistrationOptions & {}

/**
 * Options for declaration support. Declarations show where a symbol is originally
 * declared, which can be different from its definition.
 */
typedef DeclarationRegistrationOptions = TextDocumentRegistrationOptions &
	DeclarationOptions &
	StaticRegistrationOptions & {}

/**
 * Options for type definition support. Type definitions show where a type
 * is defined, which is particularly useful in statically typed languages.
 */
typedef TypeDefinitionRegistrationOptions = TextDocumentRegistrationOptions &
	TypeDefinitionOptions &
	StaticRegistrationOptions & {}

/**
 * Options for implementation support. This helps users navigate to where
 * interfaces or abstract classes are implemented.
 */
typedef ImplementationRegistrationOptions = TextDocumentRegistrationOptions &
	ImplementationOptions &
	StaticRegistrationOptions & {}

/**
 * Options for document links. Document links help users navigate between
 * related documents, like following an import statement to its source.
 */
typedef DocumentLinkOptions = WorkDoneProgressOptions & {
	/**
	 * Document links have a resolve provider as well, which can
	 * add additional information to a link after it's created.
	 */
	var ?resolveProvider:Bool;
}

/**
 * Options for document color support. This helps editors display and
 * edit color values in documents.
 */
typedef DocumentColorOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for document color support.
 */
typedef DocumentColorRegistrationOptions = TextDocumentRegistrationOptions &
	StaticRegistrationOptions &
	DocumentColorOptions & {}

/**
 * Options for document formatting. This controls how the server formats
 * entire documents when requested.
 */
typedef DocumentFormattingOptions = WorkDoneProgressOptions & {}

/**
 * Options for document range formatting. This allows formatting of
 * selected portions of a document.
 */
typedef DocumentRangeFormattingOptions = WorkDoneProgressOptions & {}

/**
 * Options for on-type formatting. This enables real-time formatting as
 * the user types, like automatically adjusting indentation after a brace.
 */
typedef DocumentOnTypeFormattingOptions = {
	/**
	 * A character that triggers formatting, like `{` or `;`
	 */
	var firstTriggerCharacter:String;

	/**
	 * Additional characters that trigger formatting
	 */
	var ?moreTriggerCharacter:Array<String>;
}

/**
 * Options for rename support. This controls how symbols can be renamed
 * throughout a workspace.
 */
typedef RenameOptions = {
	> WorkDoneProgressOptions,

	/**
	 * Whether renames should be checked and tested before being executed.
	 * This allows the server to verify that a rename would be valid.
	 */
	var ?prepareProvider:Bool;
}

/**
 * Options for folding range support. Folding ranges let users collapse
 * sections of code for better overview.
 */
typedef FoldingRangeOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for folding range support.
 */
typedef FoldingRangeRegistrationOptions = TextDocumentRegistrationOptions &
	FoldingRangeOptions &
	StaticRegistrationOptions & {}

/**
 * Options for execute command support. Execute commands allow servers to
 * define custom actions that clients can invoke.
 */
typedef ExecuteCommandOptions = WorkDoneProgressOptions & {
	/**
	 * The commands to be executed on the server. Each command should
	 * have a unique identifier.
	 */
	var commands:Array<String>;
}

/**
 * Options for selection range support. Selection ranges help editors
 * intelligently expand or shrink selections based on code structure.
 */
typedef SelectionRangeOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for selection range support.
 */
typedef SelectionRangeRegistrationOptions = TextDocumentRegistrationOptions &
	SelectionRangeOptions &
	StaticRegistrationOptions & {}

/**
 * Options for linked editing range support. This allows coordinated editing
 * of related pieces of code, like renaming both opening and closing tags.
 */
typedef LinkedEditingRangeOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for linked editing range support.
 */
typedef LinkedEditingRangeRegistrationOptions = TextDocumentRegistrationOptions &
	LinkedEditingRangeOptions &
	StaticRegistrationOptions & {}

/**
 * Options for call hierarchy support. Call hierarchies show the relationships
 * between functions that call each other.
 */
typedef CallHierarchyOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for call hierarchy support.
 */
typedef CallHierarchyRegistrationOptions = TextDocumentRegistrationOptions &
	CallHierarchyOptions &
	StaticRegistrationOptions & {}

/**
 * Options for semantic token support. Semantic tokens provide additional
 * syntax highlighting based on semantic analysis.
 */
typedef SemanticTokensOptions = WorkDoneProgressOptions & {
	/**
	 * The legend used by the server
	 */
	var legend:SemanticTokensLegend;

	/**
	 * Server supports providing semantic tokens for a specific range
	 */
	var ?range:Either<Bool, {}>;

	/**
	 * Server supports providing semantic tokens for a full document
	 */
	var ?full:Either<Bool, {
		/**
		 * The server supports deltas for full documents
		 */
		var ?delta:Bool;
	}>;
}

/**
 * Registration options for semantic token support.
 */
typedef SemanticTokensRegistrationOptions = TextDocumentRegistrationOptions &
	SemanticTokensOptions &
	StaticRegistrationOptions & {}

/**
 * Options for moniker support. Monikers provide stable identifiers
 * for symbols that can be used across different versions of a document.
 */
typedef MonikerOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for moniker support.
 */
typedef MonikerRegistrationOptions = TextDocumentRegistrationOptions &
	MonikerOptions &
	StaticRegistrationOptions & {}

/**
 * Options for type hierarchy support. Type hierarchies show inheritance
 * relationships between types.
 */
typedef TypeHierarchyOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for type hierarchy support.
 */
typedef TypeHierarchyRegistrationOptions = TextDocumentRegistrationOptions &
	TypeHierarchyOptions &
	StaticRegistrationOptions & {}

/**
 * Options for inline value support. Inline values show computed values
 * directly in the editor during debugging.
 */
typedef InlineValueOptions = WorkDoneProgressOptions & {}

/**
 * Registration options for inline value support.
 */
typedef InlineValueRegistrationOptions = TextDocumentRegistrationOptions &
	InlineValueOptions &
	StaticRegistrationOptions & {}

/**
 * Options for inlay hint support. Inlay hints show additional information
 * within the text, like type annotations or parameter names.
 */
typedef InlayHintOptions = WorkDoneProgressOptions & {
	/**
	 * Whether the server provides support to resolve additional
	 * information for an inlay hint item.
	 */
	var ?resolveProvider:Bool;
}

/**
 * Registration options for inlay hint support.
 */
typedef InlayHintRegistrationOptions = TextDocumentRegistrationOptions &
	InlayHintOptions &
	StaticRegistrationOptions & {}

/**
 * Options for diagnostic support. The diagnostic pull model lets clients
 * request diagnostics when needed rather than receiving constant updates.
 */
typedef DiagnosticOptions = WorkDoneProgressOptions & {
	/**
	 * An optional identifier under which the diagnostics are
	 * managed by the client.
	 */
	var ?identifier:String;

	/**
	 * Whether the language has inter-file dependencies meaning that
	 * editing code in one file can result in a different diagnostic
	 * set in another file.
	 */
	var interFileDependencies:Bool;

	/**
	 * The server provides support for workspace diagnostics as well.
	 */
	var workspaceDiagnostics:Bool;
}

/**
 * Registration options for diagnostic support.
 */
typedef DiagnosticRegistrationOptions = TextDocumentRegistrationOptions &
	DiagnosticOptions &
	StaticRegistrationOptions & {}

/**
 * A notebook document filter denotes a notebook document by different properties.
 * The properties work together to create flexible matching rules for notebook documents.
 *
 * The type supports three different filter combinations:
 * 1. notebookType + optional scheme and pattern
 * 2. scheme + optional notebookType and pattern
 * 3. pattern + optional notebookType and scheme
 *
 * At least one of notebookType, scheme, or pattern must be provided.
 *
 * For example, to match all Jupyter notebooks stored on disk:
 * {
 *     notebookType: "jupyter-notebook",
 *     scheme: "file"
 * }
 *
 * @since 3.17.0
 */
typedef NotebookDocumentFilter = {
	/**
	 * The type of notebook. This can match against the notebook type
	 * defined by the client. For example, "jupyter-notebook" or "custom-notebook".
	 */
	var ?notebookType:String;

	/**
	 * A Uri scheme, like `file` or `untitled`. This helps distinguish
	 * between notebooks stored in different locations (e.g., on disk vs in memory).
	 */
	var ?scheme:String;

	/**
	 * A glob pattern to match against the notebook path. Glob patterns can use:
	 * - `*` to match one or more characters in a path segment
	 * - `?` to match one character in a path segment
	 * - `**` to match any number of path segments
	 * - `{}` to group conditions (e.g. `**​/*.{ipynb,nnb}`)
	 * - `[]` to declare a range of characters to match
	 * - `[!...]` to negate a range of characters
	 */
	var ?pattern:String;
}

/**
 * A filter that is used to identify a notebook cell document is different from a
 * regular document filter. The filtering is based on the containing notebook's
 * properties and the cell's language.
 *
 * @since 3.17.0
 */
typedef NotebookCellTextDocumentFilter = {
	/**
	 * A filter that matches against the notebook containing the notebook cell.
	 * If a string value is provided, it matches against the notebook type.
	 * For example, "jupyter-notebook" would match only Jupyter notebooks.
	 */
	var notebook:Either<String, NotebookDocumentFilter>;

	/**
	 * A language id like `python`. Will be matched against the language id of
	 * the notebook cell document. '*' matches every language.
	 */
	var ?language:String;
}

/**
 * A document filter describes a set of documents by properties like language, schema, or pattern.
 * These filters are used to determine which documents a language feature applies to.
 * For example, a TypeScript language server might use this to only process .ts files.
 */
typedef DocumentFilter = {
	/**
	 * A language id, like `typescript` or `haxe`. This field helps identify
	 * documents based on their programming language.
	 */
	var ?language:String;

	/**
	 * A Uri scheme, like `file` or `untitled`. This helps distinguish between
	 * documents from different sources (e.g., files on disk vs unsaved documents).
	 */
	var ?scheme:String;

	/**
	 * A glob pattern, like `*.{ts,js}`. Glob patterns can have the following syntax:
	 * - `*` to match one or more characters in a path segment
	 * - `?` to match one character in a path segment
	 * - `**` to match any number of path segments, including none
	 * - `{}` to group conditions (e.g., `*.{ts,js}` matches all TypeScript and JavaScript files)
	 * - `[]` to declare a range of characters to match
	 * - `[!...]` to negate a range of characters
	 */
	var ?pattern:String;
}

/**
 * A document selector is the combination of one or more document filters.
 * The selector is used during registration to describe for which documents
 * a language feature should be active. If for example a language server
 * supports both TypeScript and JavaScript files, it would register with
 * a document selector matching both file types.
 */
typedef DocumentSelector = Array<DocumentFilter>;

/**
 * General text document registration options. These options are used when
 * dynamically registering for language features. They tell the client
 * which documents the registered capability should be active for.
 *
 * This type is frequently used as part of other registration options.
 * For example, CompletionRegistrationOptions extends these options to
 * specify which documents should have code completion support.
 */
typedef TextDocumentRegistrationOptions = {
	/**
	 * A document selector to identify the scope of the registration. A null
	 * value indicates that the document selector provided on the client side
	 * should be used.
	 *
	 * For example, a Haxe language server might use:
	 * documentSelector: [
	 *     { scheme: "file", language: "haxe" },
	 *     { scheme: "file", pattern: "*.hx" }
	 * ]
	 *
	 * This would activate the capability for both:
	 * - Documents explicitly identified as Haxe
	 * - Any file with a .hx extension
	 */
	var documentSelector:Null<DocumentSelector>;
}

/**
 * A legend defining the meaning of semantic token types and modifiers.
 * This acts as a mapping between numeric indices and semantic meanings,
 * allowing efficient transfer of semantic tokens between client and server.
 *
 * For example, a server might define:
 * {
 *     tokenTypes: ["class", "interface", "enum"],
 *     tokenModifiers: ["declaration", "static", "abstract"]
 * }
 *
 * Then when sending tokens, it can use indices into these arrays instead
 * of sending the strings each time.
 *
 * @since 3.16.0
 */
typedef SemanticTokensLegend = {
	/**
	 * The token types a server uses. A token type identifies what kind of
	 * symbol a token represents, like 'class', 'function', 'variable', etc.
	 *
	 * When encoding semantic tokens, these types are referenced by their index
	 * in this array. The index must not exceed 2^16.
	 */
	var tokenTypes:Array<String>;

	/**
	 * The token modifiers a server uses. Modifiers provide additional classification
	 * for tokens, like 'static', 'readonly', 'abstract', etc.
	 *
	 * When encoding semantic tokens, modifiers are encoded as bit flags using
	 * their index in this array. The index must not exceed 2^16.
	 */
	var tokenModifiers:Array<String>;
}

/**
 * A semantic token edit represents a change in semantic tokens relative to
 * a previous result. This allows efficient updates when small changes are
 * made to a document.
 */
typedef SemanticTokensEdit = {
	/**
	 * The start offset of the edit in the previous tokens array
	 */
	var start:Int;

	/**
	 * The number of elements to remove from the previous tokens array
	 */
	var deleteCount:Int;

	/**
	 * The new tokens to insert. If empty, this just removes tokens.
	 */
	var ?data:Array<Int>;
}

/**
 * A semantic tokens delta represents the difference between the current state
 * and a previous result identified by the resultId.
 */
typedef SemanticTokensDelta = {
	var resultId:String;
	var edits:Array<SemanticTokensEdit>;
}

/**
 * A semantic token and its position in a document. This is a high-level
 * representation used when processing tokens, before encoding them for
 * transmission.
 */
typedef SemanticToken = {
	var line:Int;
	var character:Int;
	var length:Int;
	var tokenType:Int;
	var tokenModifiers:Int;
}
