package loreline;

import haxe.ds.Either;
import haxe.io.Path;
import loreline.Imports;
import loreline.AstUtils;
import loreline.Node;
import loreline.Position;

using StringTools;
using loreline.Utf8;

/**
 * Something worth pointing out in a when block, for editors.
 */
typedef WhenWarning = {
    /** Where it is */
    var pos:Position;
    /** What to tell the writer */
    var message:String;
    /** Whether it is likely a mistake (a warning), or just good to know (information) */
    var isWarning:Bool;
}

/**
 * Something about a name that is likely a mistake, for editors.
 */
typedef NameWarning = {
    /** Where it is */
    var pos:Position;
    /** What to tell the writer */
    var message:String;
}

class Reference<T:Node> {

    public var target:T;

    public var origin:Node;

    public function new(target:T, origin:Node) {
        this.target = target;
        this.origin = origin;
    }

}

class FuncLorscript {

    public var func(default, null):NFunctionDecl;

    public var codeToLorscript(default, null):CodeToLorscript;

    public var lorscript(default, null):String = null;

    public var expr(default, null):loreline.lorscript.Expr = null;

    public var error(default, null):loreline.Error = null;

    public function new(func:NFunctionDecl) {

        this.func = func;

        this.codeToLorscript = new CodeToLorscript();

        try {
            this.lorscript = codeToLorscript.process(func.code);
        }
        catch (e:Any) {
            if (e is Error) {
                this.error = e;
                this.error.pos = func.pos.withOffset(
                    codeToLorscript.inputText,
                    this.error.pos.offset,
                    this.error.pos.length,
                    func.pos.offset
                );
            }
            this.lorscript = codeToLorscript.output.toString();
        }

        try {
            final parser = new loreline.lorscript.Parser();
            parser.resumeErrors = false;
            parser.allowJSON = true;
            parser.allowTypes = true;
            this.expr = parser.parseString(lorscript, func.name ?? '?');
        }
        catch (e:Any) {
            if (this.error == null) {
                if (e is loreline.lorscript.Expr.Error) {
                    final lorscriptError:loreline.lorscript.Expr.Error = cast e;
                    this.error = new WrappedError(
                        lorscriptError,
                        switch lorscriptError.e {
                            case EInvalidChar(c): 'Invalid character: $c';
                            case EUnexpected(s): 'Unexpected: $s';
                            case EUnterminatedString: 'Unterminated string';
                            case EUnterminatedComment: 'Unterminated comment';
                            case EInvalidPreprocessor(msg): 'Invalid preprocessor: $msg';
                            case EUnknownVariable(v): 'Unknown variable: $v';
                            case EInvalidIterator(v): 'Invalid iterator: $v';
                            case EInvalidOp(op): 'Invalid operator: $op';
                            case EInvalidAccess(f): 'Invalid access: $f';
                            case ECustom(msg): msg;
                        },
                        codeToLorscript.toLorelinePos(func.pos, lorscriptError.pmin, lorscriptError.pmax)
                    );
                }
                else if (e is Error) {
                    this.error = cast e;
                    this.error.pos = func.pos.withOffset(
                        codeToLorscript.inputText,
                        this.error.pos.offset,
                        this.error.pos.length,
                        func.pos.offset
                    );
                }
            }

            try {
                final parser = new loreline.lorscript.Parser();
                parser.resumeErrors = true;
                parser.allowJSON = true;
                parser.allowTypes = true;
                this.expr = parser.parseString(lorscript, func.name ?? '?');
            }
            catch (e2) {}
        }

    }

}

@:structInit
class LorscriptCompletion {

    public var locals:Map<String, loreline.lorscript.Checker.TType> = null;

    public var completion:loreline.lorscript.Checker.Completion = null;

}

/**
 * Utility class for analyzing Loreline scripts without executing them.
 * Provides methods for finding nodes, variables, references, etc.
 */
/**
 * A clause `name is literal` a condition requires, see Lens.indexClausesOf.
 */
@:structInit
class WhenIndexClause {
    public var name:String;
    public var literal:NStringLiteral;
}

/**
 * A run of plain rules of a when block, see Lens.whenRun.
 */
@:structInit
class WhenRun {
    /** Index of the first rule of the run */
    public var start:Int;
    /** Index after the last rule of the run */
    public var end:Int;
    /** Whether every condition of the run is pure */
    public var pure:Bool;
    /** The indices of the run by decreasing criteria count, written order within a count */
    public var byScore:Array<Int>;
}

class Lens {
    /** The script being analyzed */
    final script:Script;

    /** Map of all nodes by their unique ID, built on first use, see buildNodeMaps */
    var nodesById:Null<NodeIdMap<Node>> = null;

    /** Map of node IDs to their parent nodes */
    final parentNodes:NodeIdMap<Node> = new NodeIdMap();

    /** Map of node IDs to their child nodes, built on first use, see buildNodeMaps */
    var childNodes:Null<NodeIdMap<Array<Node>>> = null;

    final lorscriptFunctions:NodeIdMap<FuncLorscript> = new NodeIdMap();

    /**
     * Results of findBeatByNameFromNode, by node then by name. The resolution is
     * lexical: it only depends on where the node is in the script, so a result
     * holds for the life of this lens. A miss is kept too, as a holder with a
     * null beat.
     */
    final beatsByNameFromNode:NodeIdMap<Map<String, {beat:Null<NBeatDecl>}>> = new NodeIdMap();

    /**
     * Criteria counts of when rules (AstUtils.whenRuleScore), computed once.
     */
    final whenRuleScores:NodeIdMap<Int> = new NodeIdMap();

    /**
     * The names a scope on the stack may hold, see isRootOnlyName. Built on
     * first use.
     */
    var scopedNames:Null<Map<String, Bool>> = null;

    /** Whether a condition is pure, see isPureCondition. */
    final pureConditions:NodeIdMap<Bool> = new NodeIdMap();

    /** The indexable clauses of conditions, see indexClausesOf. */
    final indexClauses:NodeIdMap<Array<WhenIndexClause>> = new NodeIdMap();

    /** The runs of plain rules of when blocks, by block then start index, see whenRun. */
    final whenRuns:NodeIdMap<Map<Int, WhenRun>> = new NodeIdMap();

    /** The when blocks of the script and its imports, see getWhenStatements. */
    final whenStatements:Array<NWhenStatement> = [];

    /** The beats named `_` outside imports, see getDefaultBeats. */
    final defaultBeats:Array<NBeatDecl> = [];

    /**
     * The states below the root or temporary, and the beats with parameters,
     * of the script and its imports: the nodes collectScopedNames reads.
     */
    final scopeNodes:Array<Node> = [];

    public function new(script:Script) {
        this.script = script;
        initialize();
    }

    /**
     * Initialize all the lookups and analysis data
     */
    function initialize() {
        // Only the parents are mapped here: the interpreter reads them all along.
        // The nodes by id and the children serve restores and editor tools, and
        // cost as much again on a large script: they are built on first use
        script.each((node, parent) -> {
            if (parent != null) {
                parentNodes.set(node.id, parent);
            }

            // Nodes some caches need, found here rather than by another walk
            if (node is NWhenStatement) {
                whenStatements.push(cast node);
            }
            else if (node is NStateDecl) {
                final state:NStateDecl = cast node;
                if (state.temporary || parent == null || !(parent is Script)) scopeNodes.push(node);
            }
            else if (node is NBeatDecl) {
                final beat:NBeatDecl = cast node;
                if (beat.params != null && beat.params.length > 0) scopeNodes.push(node);
                if (beat.name == '_' && !isImported(beat)) defaultBeats.push(beat);
            }
        });
    }

    /**
     * Whether a node comes from an imported script. Its parents are already
     * mapped when initialize visits it.
     */
    function isImported(node:Node):Bool {
        var current = parentNodes.get(node.id);
        while (current != null && !(current is Script)) {
            current = parentNodes.get(current.id);
        }
        return current != null && current != script;
    }

    /**
     * Builds the maps of the nodes by id and of their children.
     */
    function buildNodeMaps():Void {
        final byId = new NodeIdMap<Node>();
        final children = new NodeIdMap<Array<Node>>();
        script.each((node, parent) -> {
            byId.set(node.id, node);
            if (parent != null) {
                var list = children.get(parent.id);
                if (list == null) {
                    list = [];
                    children.set(parent.id, list);
                }
                list.push(node);
            }
        });
        nodesById = byId;
        childNodes = children;
    }

    /**
     * The when blocks of the script and its imports.
     */
    public function getWhenStatements():Array<NWhenStatement> {
        return whenStatements;
    }

    /**
     * The beats named `_` outside imports: the unnamed beat the parser wraps
     * top-level content in.
     */
    public function getDefaultBeats():Array<NBeatDecl> {
        return defaultBeats;
    }

    public function getNodeById(id:NodeId):Null<Node> {
        if (nodesById == null) buildNodeMaps();
        return nodesById.get(id);
    }

    /**
     * Gets the node at the given position
     * @param pos Position to check
     * @return Most specific node at that position, or null if none found
     */
    public function getNodeAtPosition(pos:Position):Null<Node> {
        var bestMatch:Null<Node> = null;

        script.eachExcludingImported((node, parent) -> {
            final nodePos = node.pos;
            if (nodePos.length > 0 &&
                nodePos.offset <= pos.offset &&
                nodePos.offset + nodePos.length >= pos.offset) {

                bestMatch = node;
            }
        });

        return bestMatch;
    }

    /**
     * Gets the closest node before or at the given position
     * @param pos Position to check
     * @return Most specific node at that position or before, or null if none found
     */
    public function getClosestNodeAtOrBeforePosition(pos:Position):Null<Node> {
        var bestMatch:Null<Node> = null;
        var bestDistance:Int = 999999999;

        script.eachExcludingImported((node, parent) -> {
            final nodePos = node.pos;
            final distance = pos.offset - nodePos.offset;
            if (distance >= 0 && distance < bestDistance) {
                bestDistance = distance;
                bestMatch = node;
            }
        });

        return bestMatch;
    }

    /**
     * Gets all nodes of a specific type
     * @param nodeType Class type to find
     * @return Array of matching nodes
     */
    public function getNodesOfType<T:Node>(nodeType:Class<T>, includeImported:Bool = false):Array<T> {
        final matches:Array<T> = [];
        traverse(script, (node, parent) -> {
            if (Std.isOfType(node, nodeType)) {
                matches.push(cast node);
            }
            return includeImported || node == script || !(node is NImportStatement || node is Script);
        });
        return matches;
    }

    /**
     * Collects the unique names of all characters that speak in a dialogue
     * anywhere within the given node's subtree (including dialogues nested in
     * choices, if branches, alternatives, etc.).
     * @param node Root of the subtree to scan
     * @return Unique speaker names, in first-seen order
     */
    public function getDialogueSpeakers(node:Node):Array<String> {
        final speakers:Array<String> = [];
        final seen = new Map<String, Bool>();
        traverse(node, (child, parent) -> {
            if (child is NDialogueStatement) {
                final dialogue:NDialogueStatement = cast child;
                if (dialogue.character != null && !seen.exists(dialogue.character)) {
                    seen.set(dialogue.character, true);
                    speakers.push(dialogue.character);
                }
            }
            return true;
        });
        return speakers;
    }

    /**
     * Gets the parent node of a given node
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getParentNode(node:Node):Null<Node> {
        return parentNodes.get(node.id);
    }

    /**
     * Gets the first parent node matching the given type
     * @param node Child node
     * @return Parent node or null if none found
     */
    public function getFirstParentOfType<T:Node>(node:Node, type:Class<T>):Null<T> {
        var current:Any = node;
        while (current != null) {
            current = getParentNode(current);
            if (current != null && Type.getClass(current) == type) {
                return current;
            }
        }
        return null;
    }

    /**
     * Returns the file path of the file containing the given node.
     * Walks up the parent chain through NImportStatement nodes to
     * resolve the full path. Returns rootPath if the node is in the root file.
     */
    public function getNodeFilePath(node:Node, rootPath:String):String {
        // Collect NImportStatements from innermost to outermost
        var importChain:Array<NImportStatement> = [];
        var current:Node = node;
        while (current != null) {
            final importStmt = getFirstParentOfType(current, NImportStatement);
            if (importStmt != null) {
                importChain.push(importStmt);
                current = cast importStmt;
            } else {
                break;
            }
        }

        if (importChain.length == 0) return rootPath;

        // Resolve paths from outermost to innermost
        var currentDir = Path.directory(rootPath);
        var ext = Imports.lorExtension(rootPath);
        var resolvedPath = rootPath;

        // Reverse: outermost first
        var i = importChain.length - 1;
        while (i >= 0) {
            final importStmt = importChain[i];
            final rawPath = switch importStmt.path.parts[0].partType {
                case Raw(text): text;
                case _: "";
            };
            resolvedPath = Imports.resolveImportPath(currentDir, rawPath, ext);
            currentDir = Path.directory(resolvedPath);
            i--;
        }

        return resolvedPath;
    }

    /**
     * Returns the chain of file paths from the node's own source file up to
     * the root script, with each Loreline extension stripped. Used by the
     * interpreter for hierarchical translation fallback through the import
     * ancestor chain.
     *
     * The order is most-specific first, root last:
     *   - node in root.lor                                -> ["."]
     *   - node in imports/foo.lor (imported by root)      -> ["imports/foo", "."]
     *   - node in imports/bar.lor (imported by foo.lor)   -> ["imports/bar", "imports/foo", "."]
     */
    public function getNodeAncestorFilePaths(node:Node):Array<String> {
        // Collect NImportStatements from innermost to outermost
        var importChain:Array<NImportStatement> = [];
        var current:Node = node;
        while (current != null) {
            final importStmt = getFirstParentOfType(current, NImportStatement);
            if (importStmt != null) {
                importChain.push(importStmt);
                current = cast importStmt;
            } else {
                break;
            }
        }

        final result:Array<String> = [];

        // Walk outermost -> innermost, building the chain incrementally.
        // Each step adds one more import resolution; we keep every intermediate
        // file path so callers can try them in fallback order.
        var resolved:String = null;
        var i = importChain.length - 1;
        while (i >= 0) {
            final importStmt = importChain[i];
            final importPath = switch importStmt.path.parts[0].partType {
                case Raw(text): text;
                case _: "";
            };
            if (resolved == null) {
                resolved = importPath;
            } else {
                resolved = Path.join([Path.directory(resolved), importPath]);
            }
            result.push(Imports.stripLorExtension(Path.normalize(resolved)));
            i--;
        }

        // We collected outermost -> innermost. Reverse so the node's own file
        // comes first.
        result.reverse();

        // Append root as the final fallback.
        result.push(".");

        return result;
    }

    /**
     * Returns the path of the node's source file relative to the root script,
     * with any Loreline extension (`.lor`/`.lor.txt`) stripped.
     * - Returns "." for nodes in the root script.
     * - Returns the import chain path joined and normalized for nodes in imported files
     *   (e.g. "imports/foo", "../bar").
     * Used by the interpreter to look up scoped translation keys.
     */
    public function getNodeRelativeFilePath(node:Node):String {
        // Collect NImportStatements from innermost to outermost
        var importChain:Array<NImportStatement> = null;
        var current:Node = node;
        while (current != null) {
            final importStmt = getFirstParentOfType(current, NImportStatement);
            if (importStmt != null) {
                if (importChain == null)
                    importChain = [];
                importChain.push(importStmt);
                current = cast importStmt;
            } else {
                break;
            }
        }

        if (importChain == null || importChain.length == 0) return ".";

        // Join the import path strings from outermost to innermost.
        // Each import path is relative to its parent's directory.
        var resolved:String = null;
        var i = importChain.length - 1;
        while (i >= 0) {
            final importStmt = importChain[i];
            final importPath = switch importStmt.path.parts[0].partType {
                case Raw(text): text;
                case _: "";
            };
            if (resolved == null) {
                resolved = importPath;
            } else {
                resolved = Path.join([Path.directory(resolved), importPath]);
            }
            i--;
        }
        return Imports.stripLorExtension(Path.normalize(resolved));
    }

    public function getImportedPaths(rootPath:String):Array<String> {

        final result:Array<String> = [];
        // The root is not one of its own imports, even when a file imports it back
        _getImportedPaths(rootPath, script, result, [Imports.rootImportPath(rootPath) => true]);
        return result;

    }

    function _getImportedPaths(rootPath:String, script:Script, result:Array<String>, used:Map<String,Bool>):Array<String> {

        final rootDir = Path.directory(rootPath);

        if (script == null) {
            script = this.script;
        }

        final ext = Imports.lorExtension(rootPath);

        for (node in script.body) {
            if (node is NImportStatement) {
                final importNode:NImportStatement = cast node;

                final rawPath:String = switch importNode.path.parts[0].partType {
                    case Raw(text): text;
                    case _: "";
                };
                final importPath = Imports.resolveImportPath(rootDir, rawPath, ext);

                if (!used.exists(importPath)) {
                    used.set(importPath, true);
                    result.push(importPath);

                    if (importNode.script != null) {
                        _getImportedPaths(importPath, importNode.script, result, used);
                    }
                }
            }
        }

        return result;

    }

    public function resolveArrayAccess(access:NArrayAccess):Null<Node> {
        // First resolve the target array
        var targetNode:Null<Node> = null;

        // If target is itself an access expression, resolve it recursively
        if (access.target is NAccess) {
            targetNode = resolveAccess(cast access.target);
        }
        // If target is array access, resolve it recursively
        else if (access.target is NArrayAccess) {
            targetNode = resolveArrayAccess(cast access.target);
        }

        // If we couldn't resolve the target, we can't resolve the array access
        if (targetNode == null) {
            return null;
        }

        // Check what kind of node we got for the target
        switch Type.getClass(targetNode) {
            case NLiteral:
                final literal:NLiteral = cast targetNode;
                // Only arrays can be indexed
                if (literal.literalType == Array) {
                    final elements:Array<Dynamic> = cast literal.value;
                    // Try to resolve static numeric indices only
                    if (access.index is NLiteral) {
                        final indexLit:NLiteral = cast access.index;
                        if (indexLit.literalType == Number) {
                            final index:Int = Std.int(indexLit.value);
                            if (index >= 0 && index < elements.length) {
                                // Get the element at the index if it's a node
                                final element = elements[index];
                                if (Std.isOfType(element, Node)) {
                                    return cast element;
                                }
                            }
                        }
                    }
                }

            case NObjectField:
                // If the target resolves to an object field,
                // check if that field's value is an array
                final field:NObjectField = cast targetNode;
                if (field.value is NLiteral) {
                    final literal:NLiteral = cast field.value;
                    if (literal.literalType == Array) {
                        final elements:Array<Dynamic> = cast literal.value;
                        // Try to resolve static numeric indices only
                        if (access.index is NLiteral) {
                            final indexLit:NLiteral = cast access.index;
                            if (indexLit.literalType == Number) {
                                final index:Int = Std.int(indexLit.value);
                                if (index >= 0 && index < elements.length) {
                                    // Get the element at the index if it's a node
                                    final element = elements[index];
                                    if (Std.isOfType(element, Node)) {
                                        return cast element;
                                    }
                                }
                            }
                        }
                    }
                }

            case _:
                // Other node types cannot be indexed
        }

        return null;
    }

    /**
     * Resolves an identifier access to its corresponding node in the AST.
     * Resolution follows the same priority order as the interpreter:
     * 1. State fields in current scope and parent beats
     * 2. Top-level state fields
     * 3. Top-level character declarations
     * 4. Beat declarations
     *
     * @param access The access expression to resolve
     * @return The referenced node if found, null otherwise
     */
    public function resolveAccess(access:NAccess):Null<Node> {
        // First handle field access (obj.field)
        if (access.target != null) {
            // Recursively resolve the target object
            var targetNode = if (access.target is NAccess) {
                resolveAccess(cast access.target);
            }
            // If target is array access, resolve it recursively
            else if (access.target is NArrayAccess) {
                resolveArrayAccess(cast access.target);
            }
            else {
                null;
            }

            if (targetNode != null) {

                if (targetNode is NObjectField) {
                    targetNode = (cast targetNode:NObjectField).value;
                }

                switch Type.getClass(targetNode) {
                    case NCharacterDecl:
                        // If target is a character, look for field in its fields
                        final characterDecl:NCharacterDecl = cast targetNode;
                        for (prop in characterDecl.fields) {
                            if (prop.name == access.name) {
                                return prop;
                            }
                        }
                    case NLiteral:
                        // If target is a literal, check if it is an object
                        final literal:NLiteral = cast targetNode;
                        switch literal.literalType {
                            case Object(style):
                                final fields:Array<NObjectField> = cast literal.value;
                                for (field in fields) {
                                    if (field.name == access.name) {
                                        return field;
                                    }
                                }
                            case _:
                        }
                    case _:
                }
            }

            return null;
        }

        // Handle direct identifier resolution
        final name = access.name;
        if (name == null) return null;

        // 1. Look for state fields in current scope and parent beats
        var currentBeat = getFirstParentOfType(access, NBeatDecl);
        while (currentBeat != null) {
            // Check for state declarations in this beat
            var result:Null<Node> = null;
            traverse(currentBeat, (node, parent) -> {
                if (result != null) return false;

                if (node is NStateDecl) {
                    final stateDecl:NStateDecl = cast node;
                    for (field in stateDecl.fields) {
                        if (field.name == name) {
                            result = field;
                            return false;
                        }
                    }
                }
                return true;
            });

            if (result != null) {
                return result;
            }

            // Move up to parent beat
            currentBeat = getFirstParentOfType(currentBeat, NBeatDecl);
        }

        // 2. Look for fields in top-level state declarations
        var stateField:Null<Node> = null;
        traverse(script, (node, parent) -> {
            if (stateField != null) return false;

            if (node is NStateDecl) {
                final stateDecl:NStateDecl = cast node;
                for (field in stateDecl.fields) {
                    if (field.name == name) {
                        stateField = field;
                        return false;
                    }
                }
            }
            return (node is NImportStatement || node is Script);
        });
        if (stateField != null) {
            return stateField;
        }

        // 3. Look for a top-level character declaration
        final characterDecl = findCharacterByNameFromNode(name, access);
        if (characterDecl != null) {
            return characterDecl;
        }

        // 4. Look for a beat declaration
        final beatDecl = findBeatByNameFromNode(name, access);
        if (beatDecl != null) {
            return beatDecl;
        }

        // 5. Finally, look for a top-level function declaration
        final functionDecl = findFunctionByNameFromNode(name, access);
        if (functionDecl != null) {
            return functionDecl;
        }

        // Nothing found
        return null;
    }

    /**
     * Finds and returns the beat declaration referenced by the given call.
     * This method searches through the beat declarations to find a match based on the call's fields.
     * @param call The call object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findBeatFromAccess(access:NAccess):Null<NBeatDecl> {

        if (access.target == null && access.name != null) {
            return findBeatByNameFromNode(access.name, access);
        }

        return null;

    }

    /**
     * Finds the beat parameter referenced by the given bare access, if any.
     * Walks the enclosing beats from innermost to outermost (matching the
     * runtime scope precedence) and returns the first parameter whose name
     * matches the access.
     * @param access The access to resolve
     * @return The matching parameter and its owning beat, or null
     */
    public function findBeatParamFromAccess(access:NAccess):Null<{param:NBeatParam, beat:NBeatDecl}> {

        if (access.target != null || access.name == null) return null;

        var parentBeat = getFirstParentOfType(access, NBeatDecl);
        while (parentBeat != null) {
            if (parentBeat.params != null) {
                for (param in parentBeat.params) {
                    if (param.name == access.name) {
                        return {param: param, beat: parentBeat};
                    }
                }
            }
            parentBeat = getFirstParentOfType(parentBeat, NBeatDecl);
        }

        return null;

    }

    /**
     * When the given node is (part of) an argument of a call, beat call,
     * transition or insertion, returns the owner node and the argument index.
     * Only expression chains that terminate directly in an args array count;
     * the call target itself is not an argument.
     * @param node The node to check (typically the hovered node)
     * @return The owner node and argument index, or null
     */
    public function findCallArgument(node:Node):Null<{owner:Node, index:Int}> {

        var child:Node = node;
        var parent:Node = getParentNode(child);

        while (parent != null) {

            switch Type.getClass(parent) {

                case NCall:
                    final call:NCall = cast parent;
                    if (call.args != null) {
                        final index = call.args.indexOf(cast child);
                        if (index != -1) return {owner: parent, index: index};
                    }
                    return null;

                case NBeatCall:
                    final beatCall:NBeatCall = cast parent;
                    if (beatCall.args != null) {
                        final index = beatCall.args.indexOf(cast child);
                        if (index != -1) return {owner: parent, index: index};
                    }
                    return null;

                case NTransition:
                    final transition:NTransition = cast parent;
                    if (transition.args != null) {
                        final index = transition.args.indexOf(cast child);
                        if (index != -1) return {owner: parent, index: index};
                    }
                    return null;

                case NInsertion:
                    final insertion:NInsertion = cast parent;
                    if (insertion.args != null) {
                        final index = insertion.args.indexOf(cast child);
                        if (index != -1) return {owner: parent, index: index};
                    }
                    return null;

                case _:
                    // Keep climbing only through expressions (an argument can
                    // be a nested expression); stop at statement boundaries
                    if (!(parent is NExpr)) return null;
            }

            child = parent;
            parent = getParentNode(child);
        }

        return null;

    }

    /**
     * Finds and returns the beat declaration referenced by the given transition.
     * This method searches through the beat declarations to find a match based on the transition's fields.
     * @param transition The transition object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findBeatFromTransition(transition:NTransition):Null<NBeatDecl> {

        // Dynamic targets cannot be resolved statically
        if (transition.targetExpr != null) return null;

        return findBeatByNameFromNode(transition.target, transition);

    }

    /**
     * Finds and returns the beat declaration referenced by the given insertion.
     * This method searches through the beat declarations to find a match based on the insertion's fields.
     * @param insertion The insertion object containing the reference to search for
     * @return The referenced beat declaration if found, null otherwise
     */
    public function findBeatFromInsertion(insertion:NInsertion):Null<NBeatDecl> {

        // Dynamic targets cannot be resolved statically
        if (insertion.targetExpr != null) return null;

        return findBeatByNameFromNode(insertion.target, insertion);

    }

    public function findBeatByPathFromNode(path:String, node:Node):Null<NBeatDecl> {

        final parts = path.split('.');

        var beat = findBeatByNameFromNode(parts[0], node);

        var i = 1;
        while (beat != null && i < parts.length) {
            final name = parts[i];
            var foundBeat = null;
            traverse(beat, (node, parent) -> {
                if (node is NBeatDecl) {
                    final beat:NBeatDecl = cast node;
                    if (beat.name == name) {
                        foundBeat = beat;
                    }
                    return false;
                }
                else {
                    return foundBeat == null;
                }
            });
            beat = foundBeat;
            i++;
        }

        return beat;

    }

    public function isTopLevelNode(node:Node):Bool {

        if (node is AstNode) {
            final astNode:AstNode = cast node;
            return script.body.indexOf(astNode) != -1;
        }

        return false;

    }

    public function findTopLevelBeatFromNode(node:Node):Null<NBeatDecl> {

        if (isTopLevelNode(node)) {
            if (node is NBeatDecl) {
                return cast node;
            }
            else {
                return null;
            }
        }
        else {
            var resolved = getFirstParentOfType(node, NBeatDecl);
            while (resolved != null && !isTopLevelNode(resolved)) {
                resolved = getFirstParentOfType(resolved, NBeatDecl);
            }
            if (resolved != null && resolved is NBeatDecl) {
                return cast resolved;
            }
        }

        return null;

    }

    /**
     * The criteria count of a when rule, see AstUtils.whenRuleScore. It only
     * depends on the condition, so it is computed once.
     */
    public function whenRuleScore(rule:NWhenRule):Int {
        final cached = whenRuleScores.get(rule.id);
        if (cached != null) return cached;
        final score = AstUtils.whenRuleScore(rule);
        whenRuleScores.set(rule.id, score);
        return score;
    }

    /**
     * Whether no scope of the stack can hold a field of that name, so that the
     * name can only refer to the root state (or to a character, a function or a
     * beat). The scopes hold the fields of the states declared below the root
     * and of the temporary states, in any file, the parameters of beats, and the
     * fields the interpreter keeps on nodes. Everything else lives in the root
     * state, whatever beat is running or inserted.
     */
    public function isRootOnlyName(name:String):Bool {
        if (scopedNames == null) scopedNames = collectScopedNames();
        return !scopedNames.exists(name);
    }

    /**
     * Builds now the lookups this lens would otherwise build on first use and
     * that need a walk of the whole script, see Interpreter.prepareCaches.
     */
    public function prepareCaches():Void {
        if (scopedNames == null) scopedNames = collectScopedNames();
    }

    function collectScopedNames():Map<String, Bool> {
        final names = new Map<String, Bool>();
        for (node in scopeNodes) {
            if (node is NStateDecl) {
                final state:NStateDecl = cast node;
                for (field in state.fields) {
                    names.set(field.name, true);
                }
            }
            else {
                final beat:NBeatDecl = cast node;
                for (param in beat.params) {
                    names.set(param.name, true);
                }
            }
        }
        for (internal in ['_whenTick', '_played', '_lastPlayed']) {
            names.set(internal, true);
        }
        return names;
    }

    /**
     * Whether evaluating a condition can have no effect besides its value: it
     * calls nothing and assigns nothing. Only such a condition may be left
     * unevaluated when its value is known or cannot matter.
     */
    public function isPureCondition(expr:NExpr):Bool {
        final cached = pureConditions.get(expr.id);
        if (cached != null) return cached;
        var pure = !(expr is NCall || expr is NAssign);
        if (pure) {
            // Through the nodes themselves rather than traverse: a condition is
            // small, and a lookup of its children per node costs more than
            // visiting all of them
            expr.each((node, parent) -> {
                if (node is NCall || node is NAssign) pure = false;
            });
        }
        pureConditions.set(expr.id, pure);
        return pure;
    }

    /**
     * The clauses `x is "text"` (or `"text" is x`) a condition requires: the
     * clauses joined by `and` at its top level that compare a name only the
     * root state can hold (see isRootOnlyName) with a literal made of raw
     * text. When the fact is a string that differs from the literal, the
     * condition is false whatever the rest says.
     */
    public function indexClausesOf(condition:NExpr):Array<WhenIndexClause> {
        final cached = indexClauses.get(condition.id);
        if (cached != null) return cached;
        final result:Array<WhenIndexClause> = [];
        collectIndexClauses(condition, result);
        indexClauses.set(condition.id, result);
        return result;
    }

    function collectIndexClauses(expr:NExpr, result:Array<WhenIndexClause>):Void {
        if (!(expr is NBinary)) return;
        final binary:NBinary = cast expr;
        switch binary.op {
            case OpAnd(_) if (expr.parens == 0):
                collectIndexClauses(binary.left, result);
                collectIndexClauses(binary.right, result);
            case OpEquals(_):
                var clause = indexClauseOf(binary.left, binary.right);
                if (clause == null) clause = indexClauseOf(binary.right, binary.left);
                if (clause != null) result.push(clause);
            case _:
        }
    }

    function indexClauseOf(nameExpr:NExpr, literalExpr:NExpr):Null<WhenIndexClause> {
        if (!(nameExpr is NAccess) || !(literalExpr is NStringLiteral)) return null;
        final access:NAccess = cast nameExpr;
        if (access.target != null || !isRootOnlyName(access.name)) return null;
        final literal:NStringLiteral = cast literalExpr;
        if (literal.parts.length == 0) return null;
        for (part in literal.parts) {
            switch part.partType {
                case Raw(_):
                case _: return null;
            }
        }
        return {name: access.name, literal: literal};
    }

    /**
     * The run of plain rules (no insertion) of a when block starting at `start`:
     * where it ends, whether every condition in it is pure, and its indices by
     * decreasing criteria count, in written order within a count.
     */
    public function whenRun(when:NWhenStatement, start:Int):WhenRun {
        var runs = whenRuns.get(when.id);
        if (runs == null) {
            runs = new Map();
            whenRuns.set(when.id, runs);
        }
        final cached = runs.get(start);
        if (cached != null) return cached;
        var end = start;
        var pure = true;
        while (end < when.rules.length && when.rules[end].insertion == null) {
            final condition = when.rules[end].condition;
            if (condition != null && !isPureCondition(condition)) pure = false;
            end++;
        }
        // A counting sort by decreasing criteria count, written order within a
        // count: the counts are small, and a comparison sort would cost much
        // more on runs of thousands of rules
        final scores = [for (i in start...end) whenRuleScore(when.rules[i])];
        var maxScore = 0;
        for (score in scores) {
            if (score > maxScore) maxScore = score;
        }
        final offsets = [for (_ in 0...maxScore + 2) 0];
        for (score in scores) {
            offsets[maxScore - score + 1]++;
        }
        for (k in 1...offsets.length) {
            offsets[k] += offsets[k - 1];
        }
        final byScore = [for (_ in start...end) 0];
        for (i in start...end) {
            final slot = maxScore - scores[i - start];
            byScore[offsets[slot]] = i;
            offsets[slot]++;
        }
        final run:WhenRun = {start: start, end: end, pure: pure, byScore: byScore};
        runs.set(start, run);
        return run;
    }

    public function findBeatByNameFromNode(name:String, node:Node):Null<NBeatDecl> {

        var byName = beatsByNameFromNode.get(node.id);
        if (byName == null) {
            byName = new Map();
            beatsByNameFromNode.set(node.id, byName);
        }
        final cached = byName.get(name);
        if (cached != null) return cached.beat;

        final result = searchBeatByNameFromNode(name, node);
        byName.set(name, {beat: result});
        return result;

    }

    /**
     * The search behind findBeatByNameFromNode: the beats declared in the
     * enclosing beats, innermost first, then the top-level ones.
     */
    function searchBeatByNameFromNode(name:String, node:Node):Null<NBeatDecl> {

        var result:Null<NBeatDecl> = null;

        // Look for beats inside other beats, in parent scopes
        var parentBeat = getFirstParentOfType(node, NBeatDecl);
        while (parentBeat != null) {
            traverse(parentBeat, (child, parent) -> {
                if (result != null || child == node) {
                    return false;
                }
                else if (child is NBeatDecl) {
                    final beatDecl:NBeatDecl = cast child;
                    if (beatDecl.name == name) {
                        result = beatDecl;
                    }
                    return false;
                }
                return true;
            });
            parentBeat = getFirstParentOfType(parentBeat, NBeatDecl);
        }

        // If nothing found, look at
        // top level beat declarations
        if (result == null) {
            traverse(script, (child, parent) -> {
                if (result == null && (child is NBeatDecl)) {
                    final beatDecl:NBeatDecl = cast child;
                    if (beatDecl.name == name) {
                        result = beatDecl;
                    }
                }
                return (child is NImportStatement || child is Script);
            });
        }

        return result;

    }

    /**
     * Finds and returns the character declaration referenced by the given dialogue statement.
     * This method searches through the character declarations to find a match based on the
     * dialogue's character name.
     *
     * @param dialogue The dialogue statement containing the character reference
     * @return The referenced character declaration if found, null otherwise
     */
    public function findCharacterFromDialogue(dialogue:NDialogueStatement):Null<NCharacterDecl> {

        return findCharacterByNameFromNode(dialogue.character, dialogue);

    }

    public function findCharacterByNameFromNode(name:String, node:Node):Null<NCharacterDecl> {

        var result:Null<NCharacterDecl> = null;

        // Look at top-level character declarations
        traverse(script, (child, parent) -> {
            if (result == null && (child is NCharacterDecl)) {
                final characterDecl:NCharacterDecl = cast child;
                if (characterDecl.name == name) {
                    result = characterDecl;
                }
            }
            return (child is NImportStatement || child is Script);
        });

        return result;

    }

    /**
     * Things about the names of the script that are likely mistakes, for editors:
     * - a name that mixes Latin, Greek or Cyrillic letters, often a lookalike typo
     *   (`rаven` written with a Cyrillic `а`). Emoji in the name are not counted;
     * - a line of narration that starts with the name of a character and a
     *   full-width colon `：`, typed by Chinese and Japanese input methods: only
     *   the ASCII colon makes a dialogue line;
     * - a `$name` in a text that reads an emoji as part of the name, when the name
     *   without the emoji exists: `$coins💰` is meant to be `${coins}💰`.
     */
    public function getNameWarnings():Array<NameWarning> {

        final warnings:Array<NameWarning> = [];

        function checkLetters(name:Null<String>, pos:Null<Position>) {
            if (name == null || pos == null) return;
            final scripts = scriptsOf(name);
            if (scripts.length > 1) {
                final last = scripts.pop();
                warnings.push({
                    pos: pos,
                    message: 'This name mixes ' + scripts.join(', ') + ' and ' + last + ' letters: ' + name
                });
            }
        }

        script.eachExcludingImported((node, parent) -> {
            switch Type.getClass(node) {
                case NCharacterDecl:
                    final character:NCharacterDecl = cast node;
                    checkLetters(character.name, character.namePos ?? character.pos);
                case NBeatDecl:
                    final beat:NBeatDecl = cast node;
                    checkLetters(beat.name, beat.pos);
                    if (beat.params != null) {
                        for (param in beat.params) checkLetters(param.name, param.namePos);
                    }
                case NObjectField:
                    final field:NObjectField = cast node;
                    checkLetters(field.name, field.pos);
                case NFunctionDecl:
                    final func:NFunctionDecl = cast node;
                    checkLetters(func.name, func.pos);
                    if (func.args != null) {
                        for (arg in func.args) checkLetters(arg, func.pos);
                    }
                case NDialogueStatement:
                    final dialogue:NDialogueStatement = cast node;
                    checkLetters(dialogue.character, dialogue.characterPos);
                case NTransition:
                    final transition:NTransition = cast node;
                    checkLetters(transition.target, transition.targetPos);
                case NInsertion:
                    final insertion:NInsertion = cast node;
                    checkLetters(insertion.target, insertion.targetPos);
                case NAccess:
                    final access:NAccess = cast node;
                    checkLetters(access.name, access.pos);
                    if (access.target == null && parent is NStringPart) {
                        checkEmojiAfterName(access, warnings);
                    }
                case NTextStatement:
                    checkFullWidthColon(cast node, warnings);
                case _:
            }
        });

        return warnings;

    }

    /**
     * The alphabets with lookalike letters (Latin, Greek, Cyrillic) that a name
     * uses, in the order met.
     */
    static function scriptsOf(name:String):Array<String> {
        final scripts:Array<String> = [];
        var pos = 0;
        while (true) {
            final c = Identifiers.codeAt(name, pos);
            if (c == -1) break;
            final script = Identifiers.scriptOf(c);
            if (script != null && !scripts.contains(script)) scripts.push(script);
            pos += Identifiers.unitsAt(name, pos);
        }
        return scripts;
    }

    /**
     * A line of narration that starts with the name of a character followed by a
     * full-width colon `：`.
     */
    function checkFullWidthColon(text:NTextStatement, warnings:Array<NameWarning>):Void {
        if (text.content == null || text.content.parts.length == 0) return;
        switch text.content.parts[0].partType {
            case Raw(raw):
                final end = Identifiers.nameEnd(raw, 0);
                if (end == 0) return;
                var p = end;
                while (Identifiers.codeAt(raw, p) == " ".code || Identifiers.codeAt(raw, p) == "\t".code) p++;
                if (Identifiers.codeAt(raw, p) != 0xFF1A) return;
                final name = raw.uSubstr(0, end);
                if (findCharacterByNameFromNode(name, text) == null) return;
                warnings.push({
                    pos: text.pos,
                    message: '"：" looks like ":" but isn\'t, so this line is narration. Write $name: to make $name speak.'
                });
            case _:
        }
    }

    /**
     * A `$name` that reads an emoji as part of the name, when the name without
     * the emoji exists.
     */
    function checkEmojiAfterName(access:NAccess, warnings:Array<NameWarning>):Void {
        final name = access.name;
        var pos = 0;
        while (true) {
            final c = Identifiers.codeAt(name, pos);
            if (c == -1) return;
            if (Identifiers.isEmoji(c)) break;
            pos += Identifiers.unitsAt(name, pos);
        }
        if (pos == 0) return;
        final before = name.uSubstr(0, pos);
        final after = name.uSubstr(pos);
        if (isKnownName(name, access) || !isKnownName(before, access)) return;
        warnings.push({
            pos: access.pos,
            message: 'No name "$name" here. To show $before then $after, write $${$before}$after.'
        });
    }

    /**
     * Whether a name is declared for the given node: a state field, a character,
     * a beat, a function, or a parameter of an enclosing beat.
     */
    function isKnownName(name:String, node:Node):Bool {
        if (findCharacterByNameFromNode(name, node) != null) return true;
        if (findFunctionByNameFromNode(name, node) != null) return true;
        if (findBeatByNameFromNode(name, node) != null) return true;
        var known = false;
        script.each((child, parent) -> {
            if (!known && child is NStateDecl) {
                for (field in (cast child:NStateDecl).fields) {
                    if (field.name == name) known = true;
                }
            }
        });
        if (known) return true;
        var beat = getFirstParentOfType(node, NBeatDecl);
        while (beat != null) {
            if (beat.params != null) {
                for (param in beat.params) {
                    if (param.name == name) return true;
                }
            }
            beat = getFirstParentOfType(beat, NBeatDecl);
        }
        return false;
    }

    /**
     * Things worth pointing out in a when block, for editors:
     * - a strategy that is neither `first`, `pick` nor a function of the script;
     * - a `-` glued to the condition at the start of a rule, which is a minus sign,
     *   not the mark of a rule played once;
     * - thresholds with the default strategy: two rules comparing the same value
     *   with a number, with as many criteria, tie. The one played least recently
     *   wins, not the first that matches, which `when first` does.
     */
    public function getWhenWarnings(when:NWhenStatement):Array<WhenWarning> {

        final warnings:Array<WhenWarning> = [];

        final strategy = when.strategy;
        if (strategy != null && strategy != 'first' && strategy != 'pick' && findFunctionByNameFromNode(strategy, when) == null) {
            warnings.push({
                pos: when.strategyPos ?? when.pos,
                message: 'Unknown strategy: $strategy. Use first, pick, or the name of a function. A function provided by the host can be declared with `function $strategy(rules)`.',
                isWarning: true
            });
        }

        final comparedValues:Map<String, Bool> = new Map();
        var thresholdWarned = false;
        for (rule in when.rules) {
            if (rule.insertion != null || rule.condition == null) {
                continue;
            }

            final first = leftmostOperand(rule.condition);
            if (!rule.once && first is NUnary && first.pos.offset == rule.pos.offset) {
                switch (cast first:NUnary).op {
                    case OpMinus:
                        warnings.push({
                            pos: new Position(first.pos.line, first.pos.column, first.pos.offset, 1),
                            message: 'This `-` is a minus sign on the condition. To play this rule only once, write `- ` with a space after it.',
                            isWarning: true
                        });
                    case _:
                }
            }

            if (strategy == null && !thresholdWarned) {
                final score = AstUtils.whenRuleScore(rule);
                for (clause in topLevelClauses(rule.condition)) {
                    final value = comparedValue(clause);
                    if (value == null) continue;
                    final key = score + ':' + value;
                    if (comparedValues.exists(key)) {
                        warnings.push({
                            pos: clause.pos,
                            message: 'Rules comparing `$value` with a number, with as many criteria, tie with the default strategy: the one played least recently wins, not the first that matches. Use `when first` for thresholds.',
                            isWarning: true
                        });
                        thresholdWarned = true;
                        break;
                    }
                    comparedValues.set(key, true);
                }
            }
        }

        return warnings;

    }

    /** The first operand written in an expression, outside of parentheses. */
    static function leftmostOperand(expr:NExpr):NExpr {
        if (expr.parens == 0 && expr is NBinary) {
            return leftmostOperand((cast expr:NBinary).left);
        }
        return expr;
    }

    /** The clauses joined by an `and` at the top level of a condition. */
    static function topLevelClauses(expr:NExpr):Array<NExpr> {
        if (expr.parens == 0 && expr is NBinary) {
            final binary:NBinary = cast expr;
            switch binary.op {
                case OpAnd(_):
                    return topLevelClauses(binary.left).concat(topLevelClauses(binary.right));
                case _:
            }
        }
        return [expr];
    }

    /**
     * For a comparison of a value with a number (`gold > 10`, `3 <= level`),
     * the value as written, otherwise null.
     */
    static function comparedValue(expr:NExpr):Null<String> {
        if (!(expr is NBinary)) return null;
        final binary:NBinary = cast expr;
        switch binary.op {
            case OpGreater | OpGreaterEq | OpLess | OpLessEq:
            case _: return null;
        }
        final value = isNumberLiteral(binary.right) ? binary.left : isNumberLiteral(binary.left) ? binary.right : null;
        if (value == null || !(value is NAccess || value is NArrayAccess)) return null;
        final printer = new Printer();
        printer.enableComments = false;
        return printer.print(value).trim();
    }

    static function isNumberLiteral(expr:NExpr):Bool {
        if (!(expr is NLiteral)) return false;
        return switch (cast expr:NLiteral).literalType {
            case Number: true;
            case _: false;
        }
    }

    public function findFunctionByNameFromNode(name:String, node:Node):Null<NFunctionDecl> {

        var result:Null<NFunctionDecl> = null;

        // Look at top-level function declarations
        traverse(script, (child, parent) -> {
            if (result == null && (child is NFunctionDecl)) {
                final functionDecl:NFunctionDecl = cast child;
                if (functionDecl.name == name) {
                    result = functionDecl;
                }
            }
            return (child is NImportStatement || child is Script);
        });

        return result;

    }

    public function getVisibleCharacters():Array<NCharacterDecl> {

        final result:Array<NCharacterDecl> = [];

        for (node in script) {
            if (node is NCharacterDecl) {
                result.push(cast node);
            }
        }

        return result;

    }

    public function getVisibleFunctions():Array<NFunctionDecl> {

        final result:Array<NFunctionDecl> = [];

        for (node in script) {
            if (node is NFunctionDecl) {
                result.push(cast node);
            }
        }

        return result;

    }

    /**
     * The functions declared without a body, in the script and its imports: the
     * game must provide them.
     */
    public function getExternalFunctions():Array<NFunctionDecl> {

        return [for (func in getVisibleFunctions()) if (func.external && func.name != null) func];

    }

    /**
     * Gets all state fields visible from a given position.
     * This includes fields from both temporary and permanent states.
     */
    public function getVisibleStateFields(fromNode:Node):Array<NObjectField> {
        final fields:Array<NObjectField> = [];
        final seenFields = new NodeIdMap<Bool>();

        // Search through ancestor nodes
        var current = fromNode;
        while (current != null) {
            switch Type.getClass(current) {
                case NStateDecl:
                    final state:NStateDecl = cast current;
                    for (field in state.fields) {
                        if (!seenFields.exists(field.id)) {
                            seenFields.set(field.id, true);
                            fields.push(field);
                        }
                    }
                case _:
            }
            current = parentNodes.get(current.id);
        }

        // Add fields from top level states
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NStateDecl:
                    final state:NStateDecl = cast node;
                    if (parent is Script) { // Only consider top-level states
                        for (field in state.fields) {
                            if (!seenFields.exists(field.id)) {
                                seenFields.set(field.id, true);
                                fields.push(field);
                            }
                        }
                    }
                case _:
            }
        });

        return fields;
    }

    /**
     * Gets all beat declarations available from a given position.
     * This includes both top-level beats and nested beats that are in scope.
     */
    public function getVisibleBeats(fromNode:Node):Array<NBeatDecl> {
        final beats:Array<NBeatDecl> = [];
        final seenBeats = new Map<String, Bool>();

        // Search through ancestor nodes for nested beats
        var current = getParentNode(fromNode);
        while (current != null) {
            switch Type.getClass(current) {
                case NBeatDecl:
                    final parent = getParentNode(current);
                    if (parent != null) {
                        for (child in getNodesOfType(NBeatDecl)) {
                            if (!seenBeats.exists(child.name)) {
                                seenBeats.set(child.name, true);
                                beats.push(child);
                            }
                        }
                    }
                case _:
            }
            current = getParentNode(current);
        }

        // Add top-level beats
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NBeatDecl:
                    if (parent is Script) {
                        final beat:NBeatDecl = cast node;
                        if (!seenBeats.exists(beat.name)) {
                            seenBeats.set(beat.name, true);
                            beats.push(beat);
                        }
                    }
                case _:
            }
        });

        return beats;
    }

    /**
     * Gets all unique tags used in the script.
     * @return Array of unique tag strings
     */
    public function getAllTags():Array<String> {
        final tags = new Map<String, Bool>();

        // Traverse AST looking for hash comments
        script.each((node, parent) -> {
            final astNode:AstNode = Std.isOfType(node, AstNode) ? cast node : null;
            if (astNode != null && astNode.trailingComments != null) {
                for (comment in astNode.trailingComments) {
                    if (comment.isHash) {
                        tags.set(StringTools.trim(comment.content), true);
                    }
                }
            }
        });

        return [for (tag in tags.keys()) tag];
    }

    /**
     * Count every occurence of tags (hash comments)
     * @return Map of tag counts
     */
    public function countTags():Map<String,Int> {
        final tags = new Map<String, Int>();

        // Traverse AST looking for hash comments
        script.each((node, parent) -> {
            final astNode:AstNode = Std.isOfType(node, AstNode) ? cast node : null;
            if (astNode != null && astNode.trailingComments != null) {
                for (comment in astNode.trailingComments) {
                    if (comment.isHash) {
                        final text = StringTools.trim(comment.content);
                        final prevCount = tags.get(text) ?? 0;
                        tags.set(text, prevCount + 1);
                    }
                }
            }
        });

        return tags;
    }

    /**
     * Find the state field being accessed by a field access expression
     * @param access The field access to analyze
     * @return The matching state field, if any
     */
    function findStateField(access:NAccess):Null<NObjectField> {
        if (access.target != null) return null; // Only top-level fields

        // Search through visible state fields
        final stateFields = getVisibleStateFields(access);
        for (field in stateFields) {
            if (field.name == access.name) {
                return field;
            }
        }
        return null;
    }

    /**
     * Find all beats that can be reached from a given beat through transitions or calls.
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to reachable beats
     */
    public function findOutboundBeats(beatDecl:NBeatDecl):Array<Reference<NBeatDecl>> {
        final targetBeats:NodeIdMap<Reference<NBeatDecl>> = new NodeIdMap();

        // Traverse the beat's body looking for transitions and calls
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NTransition:
                    final transition:NTransition = cast node;
                    if (transition.targetExpr == null) {
                        final targetBeat = findBeatByNameFromNode(transition.target, transition);
                        if (targetBeat != null) {
                            targetBeats.set(targetBeat.id, new Reference(targetBeat, transition));
                        }
                    }

                case NInsertion:
                    final insertion:NInsertion = cast node;
                    if (insertion.targetExpr == null) {
                        final targetBeat = findBeatByNameFromNode(insertion.target, insertion);
                        if (targetBeat != null) {
                            targetBeats.set(targetBeat.id, new Reference(targetBeat, insertion));
                        }
                    }

                case NCall:
                    final call:NCall = cast node;
                    // Only check calls that could be beat references
                    if (call.target is NAccess) {
                        final access:NAccess = cast call.target;
                        // Only simple identifiers can be beat references
                        if (access.target == null) {
                            final targetBeat = findBeatFromAccess(access);
                            if (targetBeat != null) {
                                targetBeats.set(targetBeat.id, new Reference(targetBeat, call));
                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return [for (ref in targetBeats) ref];
    }

    /**
     * Finds all nodes that reference a specific beat declaration.
     * @param beatDecl The beat declaration to find references to
     * @return Array of references to this beat
     */
    public function findReferencesToBeat(beatDecl:NBeatDecl):Array<Reference<NBeatDecl>> {
        final references:Array<Reference<NBeatDecl>> = [];

        // Traverse full AST looking for references
        script.each((node, parent) -> {
            switch Type.getClass(node) {
                case NTransition:
                    final transition:NTransition = cast node;
                    if (transition.target == beatDecl.name) {
                        references.push(new Reference(beatDecl, transition));
                    }

                case NInsertion:
                    final insertion:NInsertion = cast node;
                    if (insertion.target == beatDecl.name) {
                        references.push(new Reference(beatDecl, insertion));
                    }

                case NCall:
                    final call:NCall = cast node;
                    // Only check calls that could be beat references
                    if (call.target is NAccess) {
                        final access:NAccess = cast call.target;
                        // Only simple identifiers can be beat references
                        if (access.target == null && access.name == beatDecl.name) {
                            final foundBeat = findBeatFromAccess(access);
                            if (foundBeat != null && foundBeat.id == beatDecl.id) {
                                references.push(new Reference(beatDecl, call));
                            }
                        }
                    }

                case _:
            }
        });

        return references;
    }

    /**
     * Finds all state fields that are modified within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to modified state fields
     */
    public function findModifiedStateFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final modifiedFields:Map<String, Reference<NObjectField>> = new Map();

        // Traverse the beat's body looking for assignments
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NAssign:
                    final assign:NAssign = cast node;

                    // Check target is a field access
                    if (assign.target is NAccess) {
                        final access:NAccess = cast assign.target;
                        final field = findStateField(access);
                        if (field != null) {
                            modifiedFields.set(field.name, new Reference(field, assign));
                        }
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by field name for consistency
        final refs = [for (ref in modifiedFields) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Finds all state fields that are read/accessed within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to read state fields
     */
    public function findReadStateFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final readFields:Map<String, Reference<NObjectField>> = new Map();

        // Traverse the beat's body looking for state field reads
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NAccess:
                    final access:NAccess = cast node;

                    // Skip if this access is a target of an assignment
                    if (parent is NAssign) {
                        final assign:NAssign = cast parent;
                        if (assign.target == node) return true;
                    }

                    // Check if it's a state field
                    final field = findStateField(access);
                    if (field != null) {
                        readFields.set(field.name, new Reference(field, access));
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by field name for consistency
        final refs = [for (ref in readFields) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Find all characters that have a presence in a given beat through:
     * - Field access to character state
     * - Dialogue statements
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to characters involved in the beat
     */
    public function findBeatCharacters(beatDecl:NBeatDecl):Array<Reference<NCharacterDecl>> {
        final characters:NodeIdMap<Reference<NCharacterDecl>> = new NodeIdMap();

        // Traverse beat looking for character usage
        traverse(beatDecl, (node, parent) -> {
            switch Type.getClass(node) {
                case NDialogueStatement:
                    // Look for dialogue statements (character: "text")
                    final dialogue:NDialogueStatement = cast node;
                    final character = findCharacterFromDialogue(dialogue);
                    if (character != null) {
                        characters.set(character.id, new Reference(character, dialogue));
                    }

                case NAccess:
                    // Look for character field access (character.field)
                    final access:NAccess = cast node;
                    if (access.target == null) {
                        final character = findCharacterByNameFromNode(access.name, access);
                        if (character != null) {
                            characters.set(character.id, new Reference(character, access));
                        }
                    }

                case _:
            }
            return true;
        });

        // Convert map to array, sorted by character name
        final refs = [for (ref in characters) ref];
        refs.sort((a, b) -> {
            final aName = a.target.name.toLowerCase();
            final bName = b.target.name.toLowerCase();
            return aName < bName ? -1 : aName > bName ? 1 : 0;
        });
        return refs;
    }

    /**
     * Finds all character fields that are modified within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to modified character fields
     */
    public function findModifiedCharacterFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final used:NodeIdMap<Bool> = new NodeIdMap();
        final refs:Array<Reference<NObjectField>> = [];

        // Traverse the beat's body looking for assignments
        traverse(beatDecl, (node, parent) -> {
            switch (Type.getClass(node)) {
                case NAssign:
                    final assign:NAssign = cast node;

                    // Check target is a field access
                    if (assign.target is NAccess) {
                        final access:NAccess = cast assign.target;

                        // Check if we got an object field,
                        // and if so, check if that object field
                        // belongs to a character
                        final resolved = resolveAccess(access);
                        if (resolved is NObjectField) {
                            if (!used.exists(resolved.id)) {
                                final parent = getParentNode(resolved);
                                if (parent is NCharacterDecl) {
                                    used.set(resolved.id, true);
                                    refs.push(new Reference(
                                        cast resolved, node
                                    ));
                                }

                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return refs;
    }

    /**
     * Finds all character fields that are read/accessed within a given beat
     * @param beatDecl The beat declaration to analyze
     * @return Array of references to read character fields
     */
    public function findReadCharacterFields(beatDecl:NBeatDecl):Array<Reference<NObjectField>> {
        final used:NodeIdMap<Bool> = new NodeIdMap();
        final refs:Array<Reference<NObjectField>> = [];

        // Traverse the beat's body looking for field reads
        traverse(beatDecl, (node, parent) -> {
            switch (Type.getClass(node)) {
                case NAccess:
                    final access:NAccess = cast node;

                    // Skip if this is an assign (modification)
                    final parent = getParentNode(access);
                    if (parent is NAssign) {
                        final assign:NAssign = cast parent;
                        if (assign.target == access) {
                            return true;
                        }
                    }

                    // Check if we got an object field,
                    // and if so, check if that object field
                    // belongs to a character
                    final resolved = resolveAccess(access);
                    if (resolved is NObjectField) {
                        if (!used.exists(resolved.id)) {
                            final parent = getParentNode(resolved);
                            if (parent is NCharacterDecl) {
                                used.set(resolved.id, true);
                                refs.push(new Reference(
                                    cast resolved, node
                                ));
                            }
                        }
                    }

                case _:
            }
            return true;
        });

        return refs;
    }

    public function traverse(node:Node, callback:(node:Node, parent:Node)->Bool):Void {

        if (childNodes == null) buildNodeMaps();
        final children = childNodes.get(node.id);
        if (children != null) {
            for (i in 0...children.length) {
                final child = children[i];
                if (callback(child, node)) {
                    traverse(child, callback);
                }
            }
        }

    }

    public function getFuncLorscript(func:NFunctionDecl):FuncLorscript {

        final id = func.id;

        var info = lorscriptFunctions.get(id);

        if (info == null) {
            info = new FuncLorscript(func);
            lorscriptFunctions.set(id, info);
        }

        return info;

    }

    public function getLorscriptExpr(func:NFunctionDecl, pos:Position):loreline.lorscript.Expr {

        final info = getFuncLorscript(func);

        if (info.expr == null) {
            return null;
        }

        final offset = pos.offset - func.pos.offset;

        var bestExpr:loreline.lorscript.Expr = null;

        var handler:(expr:loreline.lorscript.Expr)->Void = null;
        handler = expr -> {
            if (expr != null) {
                final min = info.codeToLorscript.inputPosFromProcessedPos(expr.pmin);
                final max = info.codeToLorscript.inputPosFromProcessedPos(expr.pmax);

                if (offset >= min && offset <= max) {
                    bestExpr = expr;
                }

                loreline.lorscript.Tools.iter(expr, handler);
            }
        };
        loreline.lorscript.Tools.iter(info.expr, handler);

        return bestExpr;

    }

    public function resolveLorscriptAccess(func:NFunctionDecl, expr:loreline.lorscript.Expr):Null<Node> {

        switch expr.e {

            case EIdent(name):

                // 1. Look for fields in top-level state declarations
                var stateField:Null<Node> = null;
                traverse(script, (node, parent) -> {
                    if (stateField != null) return false;

                    if (node is NStateDecl) {
                        final stateDecl:NStateDecl = cast node;
                        for (field in stateDecl.fields) {
                            if (field.name == name) {
                                stateField = field;
                                return false;
                            }
                        }
                    }
                    return (node is NImportStatement || node is Script);
                });
                if (stateField != null) {
                    return cast stateField;
                }

                // 2. Look for a top-level character declaration
                final characterDecl = findCharacterByNameFromNode(name, func);
                if (characterDecl != null) {
                    return cast characterDecl;
                }

                // 3. Finally, look for a beat declaration
                final beatDecl = findBeatByNameFromNode(name, func);
                if (beatDecl != null) {
                    return cast beatDecl;
                }

            case EField(e, f):
                // Recursively resolve the target object
                var targetNode = if (e != null) {
                    resolveLorscriptAccess(func, e);
                }
                else {
                    null;
                }

                if (targetNode != null) {

                    if (targetNode is NObjectField) {
                        targetNode = (cast targetNode:NObjectField).value;
                    }

                    switch Type.getClass(targetNode) {
                        case NCharacterDecl:
                            // If target is a character, look for field in its fields
                            final characterDecl:NCharacterDecl = cast targetNode;
                            for (prop in characterDecl.fields) {
                                if (prop.name == f) {
                                    return prop;
                                }
                            }
                        case NLiteral:
                            // If target is a literal, check if it is an object
                            final literal:NLiteral = cast targetNode;
                            switch literal.literalType {
                                case Object(style):
                                    final fields:Array<NObjectField> = cast literal.value;
                                    for (field in fields) {
                                        if (field.name == f) {
                                            return field;
                                        }
                                    }
                                case _:
                            }
                        case _:
                    }
                }

            case EArray(e, index):
                // TODO (but that's not the most useful here)

            case _:
        }

        return null;

    }

    public function isLorscriptExpr(input:Any):Bool {

        return input != null && Reflect.hasField(input, "e") && (Reflect.field(input, "e") is loreline.lorscript.Expr.ExprDef);

    }

    public function getLorscriptCompletion(func:NFunctionDecl, pos:Position):LorscriptCompletion {

        final info = getFuncLorscript(func);

        final inputPos = pos.offset - func.pos.offset + pos.length;
        final processedPos = info.codeToLorscript.processedPosFromInputPos(inputPos);

        var truncated = info.lorscript.uSubstring(0, Std.int(Math.min(processedPos, info.lorscript.uLength())));

        var fullLen = truncated.uLength();
        truncated = truncated.uSubstring(truncated.uIndexOf('{') + 1, fullLen);
        var truncatedLen = truncated.uLength();
        var spaces = new Utf8Buf();
        for (i in 0...(fullLen - truncatedLen)) {
            spaces.addChar(' '.code);
        }
        truncated = spaces.toString() + truncated;

        var completion:loreline.lorscript.Checker.Completion = null;
        var checker = new loreline.lorscript.Checker();
        try {
            @:privateAccess {
                checker.types.parser.allowJSON = true;
                checker.types.parser.allowTypes = true;
                checker.types.parser.resumeErrors = true;

                final expr = checker.types.parser.parseString(truncated);
                checker.check(expr, null, true);
            }
        }
        catch (e:Any) {
            if (e is loreline.lorscript.Checker.Completion) {
                completion = cast e;
            }
        }
        final locals = @:privateAccess checker.locals;

        return {
            locals: locals,
            completion: completion
        };

    }

    public function resolveAccessInFunction(func:NFunctionDecl, pos:Position):Null<Node> {

        final info = getFuncLorscript(func);
        if (info.expr == null) {
            return null;
        }

        final expr = getLorscriptExpr(func, pos);
        if (expr != null) {
            return resolveLorscriptAccess(func, expr);
        }

        return null;

    }

}