package loreline;

import Type.ValueType;
import haxe.ds.StringMap;
import loreline.Lexer;
import loreline.Node;

/**
 * A state during the runtime execution of a loreline script
 */
class RuntimeState {

    /**
     * If set to a value > 0, that means this state is temporary and linked to a scope.
     * Everytime we are entering a new node, we are entering a new scope identified by a unique integer value.
     * When exiting that scope, the related states are destroyed
     */
    public var scope:Int = -1;

    /**
     * Fields of this state
     */
    public final fields:Any;

    public function new(?fields:Any) {
        this.fields = fields ?? new Map<String,Any>();
    }

}

/**
 * Runtime state variant specifically used for character states
 */
class RuntimeCharacter extends RuntimeState {

    public function new() {
        super();
    }

}

enum RuntimeAccess {

    FieldAccess(pos:Position, obj:Any, name:String);

    ArrayAccess(pos:Position, array:Array<Any>, index:Int);

    CharacterAccess(pos:Position, name:String);

    FunctionAccess(pos:Position, name:String);

}

/**
 * Everytime we are entering a new node, we are entering a new scope identified with a unique integer value.
 * When exiting that scope, the related temporary states associated to it are destroyed
 */
@:structInit
class Scope {

    /**
     * The scope id, a unique integer value in the stack
     */
    public var id:Int = -1;

    /**
     * The parent beat where this scope is located. Can be either
     * a top level beat or a nested beat
     */
    public var beat:NBeatDecl;

    /**
     * The node where this scope is attached
     */
    public var node:AstNode;

    /**
     * The nested beat declarations, if any, found in this scope
     */
    public var beats:Map<String, NBeatDecl> = null;

    /**
     * The temporary state associated with this scope, if any
     */
    public var state:RuntimeState = null;

}

@:structInit
class TextTag {
    public var closing:Bool;
    public var value:String;
    public var offset:Int;
}

class EvalNext {
    public var sync:Bool = true;
    public var cb:()->Void = null;
    public function new() {}
}

@:structInit
class ChoiceOption {
    public var text:String;
    public var tags:Array<TextTag>;
    public var enabled:Bool;
}

/**
 * Handler type for text output with callback
 */
typedef DialogueHandler = (interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void)->Void;

/**
 * Handler type for choice presentation with callback
 */
typedef ChoiceHandler = (interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void)->Void;

/**
 * Handler type to be called when the execution finishes
 */
typedef FinishHandler = (interpreter:Interpreter)->Void;

/**
 * Runtime error during script execution
 */
class RuntimeError extends Error {

}

/**
 * Main interpreter class for Loreline scripts
 */
class Interpreter {

    /**
     * The script being executed
     */
    final script:Script;

    /**
     * User-defined dialogue handler,
     * which takes care of displaying the dialogues.
     */
    final handleDialogue:DialogueHandler;

    /**
     * User-defined choice handler,
     * which takes care of displaying the choices and
     * providing a response to the interpreter.
     */
    final handleChoice:ChoiceHandler;

    /**
     * User-defined finish handler,
     * which is called when the current execution has finished
     */
    final handleFinish:FinishHandler;

    /**
     * The top level state, which is shared across the whole script execution.
     */
    final topLevelState:RuntimeState = new RuntimeState();

    /**
     * Top level characters can be referenced and their state
     * can also be modified from anywhere in the script.
     */
    final topLevelCharacters:Map<String, RuntimeCharacter> = new Map();

    /**
     * All the top level beats available, by beat name (their identifier in the script)
     */
    final topLevelBeats:Map<String, NBeatDecl> = new Map();

    /**
     * States associated to a specific node id. These are persistent, like the top level state,
     * but are only available from where they have been declared and the sub-scopes.
     * If some state fields already existed in a parent scope, the parent ones will be shadowed by the child ones.
     */
    final nodeStates:Map<Int, RuntimeState> = new Map();

    /**
     * Characters associated to a specific node id. These are persistent, like the tope level characters,
     * but are only available from where they have been declared and the sub-scopes.
     * When using a character name identical to one used in a parent node, it will extend the existing
     * character with those new fields, within that scope and the sub-scopes. If some fields already
     * existed in a parent scope, the parent ones will be shadowed by the child ones.
     */
    final nodeCharacters:Map<Int, RuntimeCharacter> = new Map();

    /**
     * Top level function available by default in this script
     */
    final topLevelFunctions:Map<String, Any> = new Map();

    /**
     * The current execution stack, which consists of scopes added on top of one another.
     * Each scope can have its own local beats and temporary states.
     */
    final stack:Array<Scope> = [];

    /**
     * Current scope associated with current execution state
     */
    var currentScope(get,never):Scope;
    function get_currentScope():Scope {
        return stack.length > 0 ? stack[stack.length - 1] : null;
    }

    /**
     * The next scope id to assign when pushing a new scope.
     * Everytime we reset the stack, this counter is also reset.
     */
    var nextScopeId:Int = 1;

    /**
     * List of pending callbacks that should be run synchronously
     */
    var syncCallbacks:Array<()->Void> = [];

    /**
     * Internal flag to know if we are currently flushing sync callbacks
     * (to prevent unexpected recursive flushs).
     */
    var flushing:Bool = false;

    /**
     * Keep track of which callback is the one that would trigger finish
     */
    var finishTrigger:EvalNext = null;

    public function new(script:Script, handleDialogue:DialogueHandler, handleChoice:ChoiceHandler, handleFinish:FinishHandler, ?functions:Map<String,Any>) {

        this.script = script;
        this.handleDialogue = handleDialogue;
        this.handleChoice = handleChoice;
        this.handleFinish = handleFinish;

        // Build beat lookup map
        for (decl in script.declarations) {
            if (decl is NBeatDecl) {
                // Add beat
                final beat:NBeatDecl = cast decl;
                initializeTopLevelBeat(beat);
            }
        }

        // Build character lookup map
        for (decl in script.declarations) {
            if (decl is NCharacterDecl) {
                // Add NCharacterDecl
                final character:NCharacterDecl = cast decl;
                initializeTopLevelCharacter(character);
            }
        }

        // Build default function
        initializeTopLevelFunctions(functions);

    }

    final cycleByNode:Map<Int,Int> = new Map();

    var _random:Random = null;
    function random():Float {
        if (_random == null) {
            _random = new Random();
        }
        return _random.next();
    }

    function initializeTopLevelFunctions(functions:Map<String,Any>) {

        topLevelFunctions.set('random', (min:Int, max:Int) -> {
            return Math.floor(min + random() * (max + 1 - min));
        });

        topLevelFunctions.set('chance', (n:Int) -> {
            return Math.floor(random() * n) == 0;
        });

        topLevelFunctions.set('wait', (seconds:Float) -> {
            return new Async(done -> {
                #if sys
                Sys.sleep(seconds);
                done();
                #else
                done();
                #end
            });
        });

        if (functions != null) {
            for (key => func in functions) {
                topLevelFunctions.set(key, func);
            }
        }

    }

    public function getCharacter(name:String):Any {

        return topLevelCharacters.get(name)?.fields;

    }

    public function getCharacterField(character:String, name:String):Any {

        final fields = topLevelCharacters.get(character)?.fields;
        if (fields != null) {
            return getField(fields, name);
        }
        return null;

    }

    public function getField(fields:Any, name:String):Any {

        return if (fields is Fields) {
            (cast fields:Fields).lorelineGet(name);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).get(name);
        }
        else {
            Reflect.getProperty(fields, name);
        }

    }

    public function setField(fields:Any, name:String, value:Any):Void {

        if (fields is Fields) {
            (cast fields:Fields).lorelineSet(name, value);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).set(name, value);
        }
        else {
            Reflect.setProperty(fields, name, value);
        }

    }

    public function fieldExists(fields:Any, name:String):Bool {

        return if (fields is Fields) {
            (cast fields:Fields).lorelineExists(name);
        }
        else if (fields is StringMap) {
            (cast fields:StringMap<Any>).exists(name);
        }
        else {
            Reflect.hasField(fields, name);
        }

    }

    /**
     * Starts script execution from the beginning or a specific beat
     */
    public function start(?beatName:String) {

        // Initialize global state from declarations
        for (decl in script.declarations) {
            if (decl is NStateDecl) {
                final state = cast(decl, NStateDecl);
                initializeTopLevelState(state);
            }
        }

        // Start execution
        var resolvedBeat:NBeatDecl = null;
        if (beatName != null) {
            resolvedBeat = topLevelBeats.get(beatName);
            if (resolvedBeat == null) {
                throw new RuntimeError('Beat $beatName not found', script.pos);
            }
        }
        else {
            // Check if there is an implicit beat named "_"
            for (decl in script.declarations) {
                if (decl is NBeatDecl) {
                    final beat:NBeatDecl = cast decl;
                    if (beat.name == "_") {
                        resolvedBeat = beat;
                    }
                    break;
                }
            }

            if (resolvedBeat == null) {
                // Find first beat if there is no "_"
                for (decl in script.declarations) {
                    if (decl is NBeatDecl) {
                        resolvedBeat = cast decl;
                        break;
                    }
                }
            }

            if (resolvedBeat == null) {
                throw new RuntimeError("No beats found in script", script.pos);
            }
        }
        transitionToBeat(resolvedBeat);
        flush();

    }

    function wrapNext(cb:()->Void):EvalNext {

        final wrapped = new EvalNext();

        wrapped.sync = true;

        wrapped.cb = () -> {
            if (wrapped.sync) {
                if (syncCallbacks == null) {
                    syncCallbacks = [];
                }
                syncCallbacks.push(wrapped.cb);
            }
            else {
                cb();
                flush();
                wrapped.cb = null;
                if (finishTrigger == wrapped) {
                    finish();
                }
            }
        };

        return wrapped;

    }

    function flush() {

        if (flushing) return;
        flushing = true;

        if (syncCallbacks != null) {
            while (syncCallbacks.length > 0) {

                // Flush next synchronous callback to execute,
                // and allow to stack new callbacks that may
                // be triggered from that parent callback
                var cb = syncCallbacks.shift();
                var prevSyncCallbacks = syncCallbacks;
                syncCallbacks = null;

                cb();

                // If new callbacks were added during execution,
                // they get prepended to the existing queue
                if (syncCallbacks != null) {
                    for (i in 0...syncCallbacks.length) {
                        prevSyncCallbacks.unshift(syncCallbacks[i]);
                    }
                }
                syncCallbacks = prevSyncCallbacks;
            }
        }

        flushing = false;

    }

    function pop():Bool {

        if (stack.length > 0) {
            stack.pop();
            return true;
        }

        return false;

    }

    function push(scope:Scope):Void {

        scope.id = nextScopeId++;
        stack.push(scope);

    }

    function initializeTopLevelState(state:NStateDecl) {

        // Top level states cannot be temporary
        if (state.temporary) {
            throw new RuntimeError('Top level temporary states are not allowed', state.pos);
        }

        // Evaluate state values
        for (field in (state.fields.value:Array<NObjectField>)) {
            setField(topLevelState.fields, field.name, evaluateExpression(field.value));
        }

    }

    function initializeTopLevelBeat(beat:NBeatDecl) {

        // Look for duplicate entries
        if (topLevelBeats.exists(beat.name)) {
            throw new RuntimeError('Duplicate top level beat: ${beat.name}', beat.pos);
        }

        // Create new beat entry in mapping
        topLevelBeats.set(beat.name, beat);

    }

    function initializeTopLevelCharacter(character:NCharacterDecl) {

        // Look for duplicate entries
        if (topLevelCharacters.exists(character.name)) {
            throw new RuntimeError('Duplicate top level character: ${character.name}', character.pos);
        }

        // Create new character state
        final characterState = new RuntimeCharacter();
        topLevelCharacters.set(character.name, characterState);

        // Evaluate character properties
        for (field in character.properties) {
            setField(characterState.fields, field.name, evaluateExpression(field.value));
        }

    }


    function initializeState(state:NStateDecl, scope:Scope) {

        var runtimeState:RuntimeState = null;
        if (state.temporary) {
            if (scope.state == null) {
                scope.state = new RuntimeState();
            }
            runtimeState = scope.state;
        }
        else {
            runtimeState = nodeStates.get(scope.node.id);
            if (runtimeState == null) {
                runtimeState = new RuntimeState();
                nodeStates.set(scope.node.id, runtimeState);
            }
        }

        // Evaluate state values
        for (field in (state.fields.value:Array<NObjectField>)) {
            setField(runtimeState.fields, field.name, evaluateExpression(field.value));
        }

    }

    function finish():Void {

        finishTrigger = null;

        if (handleFinish != null) {
            handleFinish(this);
        }

    }

    function transitionToBeat(beat:NBeatDecl) {

        // Clear stack and temporary states
        while (pop()) {};

        // Reset scope id
        nextScopeId = 1;

        // Run beat
        final done = wrapNext(finish);

        // We now consider that finishing this beat
        // execution chain is the finish trigger
        finishTrigger = done;

        evalBeatRun(beat, done.cb);
        done.sync = false;

    }

    function evalNode(node:AstNode, next:()->Void) {

        switch (Type.getClass(node)) {

            case NBeatDecl:
                evalBeatDecl(cast node, next);
            case NStateDecl:
                evalStateDecl(cast node, next);
            case NTextStatement:
                evalText(cast node, next);
            case NDialogueStatement:
                evalDialogue(cast node, next);
            case NChoiceStatement:
                evalChoice(cast node, next);
            case NChoiceOption:
                evalChoiceOption(cast node, next);
            case NIfStatement:
                evalIf(cast node, next);
            case NAssign:
                evalAssignment(cast node, next);
            case NCall:
                evalCall(cast node, next);

            case NTransition:
                // When evaluating transition, we discard the
                // `next` callback because we are starting a new stack
                evalTransition(cast node);

            case _:
                throw new RuntimeError('Unsupported node type: ${Type.getClassName(Type.getClass(node))}', node.pos);
        }

    }

    function evalBeatDecl(beat:NBeatDecl, next:()->Void) {
        debug('eval beat decl name=${beat.name}');

        // Add beat to current scope.
        // It will be available as long as we don't leave that scope

        if (currentScope.beats == null) {
            currentScope.beats = new Map();
        }
        else if (currentScope.beats.exists(beat.name)) {
            throw new RuntimeError('Duplicate beat with name: ${beat.name}', beat.pos);
        }

        currentScope.beats.set(beat.name, beat);

        next();

    }

    function evalBeatRun(beat:NBeatDecl, next:()->Void) {
        debug('eval beat run name=${beat.name}');

        // Push new scope
        push({
            beat: beat,
            node: beat
        });

        // Then iterate through each direct child node in the beat
        var index = 0;
        var moveNext:()->Void = null;
        moveNext = () -> {

            // Check if we still have a node to evaluate
            if (index < beat.body.length) {

                // Yes, do it
                final childNode = beat.body[index];
                index++;
                final done = wrapNext(moveNext);
                evalNode(childNode, done.cb);
                done.sync = false;

            }
            else {

                // We are done, pop beat scope
                // and finish that beat evaluation
                pop();
                next();
            }

        }

        // Start evaluating the beat
        moveNext();

    }

    function evalNodeBody(node:AstNode, body:Array<AstNode>, next:()->Void) {
        debug('eval node body length=${body.length}');

        // Push new scope
        push({
            beat: currentScope.beat,
            node: node
        });

        // Then iterate through each child node in the body
        var index = 0;
        var moveNext:()->Void = null;
        moveNext = () -> {

            // Check if we still have a node to evaluate
            if (index < body.length) {

                // Yes, do it
                final childNode = body[index];
                index++;
                final done = wrapNext(moveNext);
                evalNode(childNode, done.cb);
                done.sync = false;

            }
            else {

                // We are done, pop node scope
                // and finish that node body evaluation
                pop();
                next();
            }

        }

        // Start evaluating the body
        moveNext();

    }

    function evalStateDecl(state:NStateDecl, next:()->Void) {
        debug('eval state decl fields=${[for (field in (state.fields.value:Array<NObjectField>)) field.name].join(',')}');

        // This will initialize the state if it's temporary
        // or the first time we encounter it, if it is a persistent one
        initializeState(
            state,
            currentScope
        );

        next();

    }

    function evalText(text:NTextStatement, next:()->Void) {
        debug('eval text content=${text.content}');

        // First evaluate the content from the given text
        final content = evaluateString(text.content);

        // Then call the user-defined dialogue handler.
        // The execution will be "paused" until the callback
        // is called, either synchronously or asynchronously
        handleDialogue(this, null, content.text, content.tags, next);

    }

    function evalDialogue(dialogue:NDialogueStatement, next:()->Void) {
        debug('eval dialogue content=${dialogue.content}');

        // First evaluate the content from the given dialogue
        final content = evaluateString(dialogue.content);

        // Then call the user-defined dialogue handler.
        // The execution will be "paused" until the callback
        // is called, either synchronously or asynchronously
        handleDialogue(this, dialogue.character, content.text, content.tags, next);

    }

    function evalChoice(choice:NChoiceStatement, next:()->Void) {
        debug('eval choice length=${choice.options.length}');

        // Compute choice contents
        final options:Array<ChoiceOption> = [];
        for (option in choice.options) {
            final enabled = option.condition == null || evaluateCondition(option.condition);
            final content = evaluateString(option.text);
            options.push({
                text: content.text,
                tags: content.tags,
                enabled: enabled
            });
        }

        // Then call the user-defined choice handler.
        // The execution will be "paused" until the callback
        // is called, either synchronously or asynchronously
        handleChoice(this, options, function(index) {

            if (index >= 0 && index < choice.options.length) {
                // Evaluate the chosen option
                evalChoiceOption(choice.options[index], next);
            }
            else {
                // Choice is invalid. In that situation, we suppose
                // the choice was cancelable and just continue evaluation
                next();
            }

        });

    }

    function evalChoiceOption(option:NChoiceOption, next:()->Void) {
        debug('eval choice option=${option.text}');

        // Evaluate child nodes of this choice option.
        // Child nodes will be evaluated in a child scope associated
        // with this options node
        evalNodeBody(option, option.body, next);

    }

    function evalIf(ifStmt:NIfStatement, next:()->Void) {
        debug('eval if');

        final isTrue = evaluateCondition(ifStmt.condition);

        final branch = isTrue ? ifStmt.thenBranch : ifStmt.elseBranch;

        if (branch != null && branch.body.length > 0) {
            evalNodeBody(branch, branch.body, next);
        }
        else {
            next();
        }

    }

    function evalAssignment(assign:NAssign, next:()->Void) {
        debug('eval assign');

        final target = resolveAssignmentTarget(assign.target);
        final value = evaluateExpression(assign.value);

        final currentValue = switch (assign.op) {
            case OpAssign: value;
            case OpPlusAssign: performOperation(OpPlus, readAccess(target), value, assign.pos);
            case OpMinusAssign: performOperation(OpMinus, readAccess(target), value, assign.pos);
            case OpMultiplyAssign: performOperation(OpMultiply, readAccess(target), value, assign.pos);
            case OpDivideAssign: performOperation(OpDivide, readAccess(target), value, assign.pos);
            case _: throw new RuntimeError('Invalid assignment operator', assign.pos);
        }

        writeAccess(target, currentValue);

        next();

    }

    function evalCall(call:NCall, next:()->Void) {

        // If target is a simple identifier, it might be a nested beat call
        if (call.target is NAccess) {
            final access:NAccess = cast call.target;
            if (access.target == null) {
                // Look for matching beat in current scope and parent scopes
                var beatName = access.name;
                var resolvedBeat:NBeatDecl = null;

                // Search through scopes from innermost to outermost
                var i = stack.length - 1;
                while (i >= 0) {
                    final scope = stack[i];
                    if (scope.beats != null && scope.beats.exists(beatName)) {
                        resolvedBeat = scope.beats.get(beatName);
                        break;
                    }
                    i--;
                }

                // If not found in scopes, check top level beats
                if (resolvedBeat == null && topLevelBeats.exists(beatName)) {
                    resolvedBeat = topLevelBeats.get(beatName);
                }

                // If beat found, evaluate it
                if (resolvedBeat != null) {
                    evalBeatRun(resolvedBeat, next);
                    return;
                }
            }
        }

        // In other situations, try a regular function call
        evaluateFunctionCall(call, next);

    }

    function evalTransition(transition:NTransition) {
        debug('eval transition target=${transition.target}');

        final beatName = transition.target;
        if (beatName == ".") {
            finish();
            return;
        }

        var resolvedBeat:NBeatDecl = null;

        // Look for matching beat in scopes recursively
        var i = stack.length - 1;
        while (i >= 0) {
            final scope = stack[i];
            if (scope.beats != null && scope.beats.exists(beatName)) {
                resolvedBeat = scope.beats.get(beatName);
                break;
            }
            i--;
        }

        // If no beat was found, look at top level beats
        if (resolvedBeat == null) {
            if (topLevelBeats.exists(transition.target)) {
                resolvedBeat = topLevelBeats.get(beatName);
            }
        }

        // If still nothing found, not good...
        if (resolvedBeat == null) {
            throw new RuntimeError('Beat $beatName not found', script.pos);
        }

        // Beat found, let's go!
        transitionToBeat(resolvedBeat);

    }

    function evaluateString(str:NStringLiteral):{text:String, tags:Array<TextTag>} {
        final buf = new StringBuf();
        final tags:Array<TextTag> = [];
        var offset = 0;

        for (part in str.parts) {
            switch (part.type) {
                case Raw(text):
                    offset += text.length;
                    buf.add(text);

                case Expr(expr):

                    if (expr is NAccess) {
                        // When providing a character object,
                        // implicitly read the character's `name` field
                        final access:NAccess = cast expr;
                        final resolved = resolveAccess(access, access.target, access.name);
                        switch resolved {
                            case CharacterAccess(_, name):
                                final characterFields = evaluateExpression(expr);
                                final value = getField(characterFields, 'name') ?? name;
                                final text = valueToString(value);
                                offset += text.length;
                                buf.add(text);

                            case _:
                                final value = evaluateExpression(expr);
                                final text = valueToString(value);
                                offset += text.length;
                                buf.add(text);
                        }
                    }
                    else {
                        final value = evaluateExpression(expr);
                        final text = valueToString(value);
                        offset += text.length;
                        buf.add(text);
                    }

                case Tag(closing, expr):
                    tags.push({
                        closing: closing,
                        value: evaluateString(expr).text,
                        offset: offset
                    });
            }
        }

        return {
            text: buf.toString(),
            tags: tags
        };

    }

    function evaluateCondition(expr:NExpr):Bool {

        final value:Any = evaluateExpression(expr);

        return if (value is String) {
            (value:String).length > 0;
        }
        else if (value is Array) {
            (value:Array<Any>).length > 0;
        }
        else {
            (value:Dynamic) == true;
        }

    }

    function evaluateFunctionCall(call:NCall, next:()->Void):Any {

        // If target is a simple identifier, it might be a nested beat call
        if (call.target is NAccess) {
            final access:NAccess = cast call.target;
            if (access.target == null) {
                // Handle standalone function calls
                final target = evaluateExpression(call.target);
                if (target != null) {
                    if (Reflect.isFunction(target)) {
                        final args = [for (arg in call.args) evaluateExpression(arg)];
                        final result:Any = Reflect.callMethod(null, target, args);
                        if (result != null && result is Async) {
                            if (next == null) {
                                throw new RuntimeError(
                                    'Cannot call async function in expression',
                                    call.pos
                                );
                            }
                            else {
                                final asyncResult:Async = cast result;
                                asyncResult.func(next);
                            }
                        }
                        else if (next != null) {
                            next();
                        }
                        return result;
                    }
                }

            }
            else {
                // Handle method calls (obj.method())
                final obj = evaluateExpression(access.target);
                final method = Reflect.getProperty(obj, access.name);
                if (Reflect.isFunction(method)) {
                    final args = [for (arg in call.args) evaluateExpression(arg)];
                    final result:Any = Reflect.callMethod(obj, method, args);
                    if (result != null && result is Async) {
                        if (next == null) {
                            throw new RuntimeError(
                                'Cannot call async function in expression',
                                call.pos
                            );
                        }
                        else {
                            final asyncResult:Async = cast result;
                            asyncResult.func(next);
                        }
                    }
                    else if (next != null) {
                        next();
                    }
                    return result;
                }
            }
        }

        // If we get here, the call target was invalid
        throw new RuntimeError(
            'Invalid call target: ${Type.getClassName(Type.getClass(call.target))}',
            call.pos
        );

    }

    function evaluateExpression(expr:NExpr):Any {

        return switch (Type.getClass(expr)) {

            case NLiteral:
                final lit:NLiteral = cast expr;
                switch (lit.type) {
                    case Number, Boolean, Null: lit.value;
                    case Array:
                        [for (elem in (lit.value:Array<Dynamic>)) evaluateExpression(elem)];
                    case Object:
                        final obj = new Map<String, Any>();
                        for (field in (lit.value:Array<NObjectField>)) {
                            obj.set(field.name, evaluateExpression(field.value));
                        }
                        obj;
                }

            case NStringLiteral:
                final str:NStringLiteral = cast expr;
                evaluateString(str).text;

            case NAccess:
                final access:NAccess = cast expr;
                final resolved = resolveAccess(access, access.target, access.name);
                readAccess(resolved);

            case NArrayAccess:
                final arrAccess:NArrayAccess = cast expr;
                final target = evaluateExpression(arrAccess.target);
                final index = evaluateExpression(arrAccess.index);

                if (target is Array && (index is Int || index is Float)) {
                    final i:Int = Std.int(index);
                    final arr:Array<Any> = target;
                    if (i >= 0 && i < arr.length) {
                        arr[i];
                    }
                    else {
                        throw new RuntimeError('Array index out of bounds: $i', arrAccess.pos);
                    }
                }
                else {
                    throw new RuntimeError('Invalid array access', arrAccess.pos);
                }

            case NBinary:
                final bin:NBinary = cast expr;
                final left = evaluateExpression(bin.left);
                final right = evaluateExpression(bin.right);
                performOperation(bin.op, left, right, bin.pos);

            case NUnary:
                final un:NUnary = cast expr;
                final operand:Any = evaluateExpression(un.operand);
                switch un.op {
                    case OpMinus if (operand is Int): {
                        final v:Int = operand;
                        -v;
                    }
                    case OpMinus if (operand is Float): {
                        final v:Float = operand;
                        -v;
                    }
                    case OpNot if (operand is Bool): {
                        final v:Bool = operand;
                        !v;
                    }
                    case _: throw new RuntimeError('Invalid unary operation', un.pos);
                }

            case NCall:
                evaluateFunctionCall(cast expr, null);

            case _:
                throw new RuntimeError('Unsupported expression type: ${Type.getClassName(Type.getClass(expr))}', expr.pos);
        }

    }

    function readAccess(access:RuntimeAccess):Any {

        return switch access {

            case FieldAccess(pos, obj, name):
                getField(obj, name);

            case ArrayAccess(pos, array, index):
                array[index];

            case CharacterAccess(pos, name):
                if (topLevelCharacters.exists(name)) {
                    topLevelCharacters.get(name).fields;
                }
                else {
                    throw new RuntimeError('Character not found: $name', pos);
                }

            case FunctionAccess(pos, name):
                if (topLevelFunctions.exists(name)) {
                    topLevelFunctions.get(name);
                }
                else {
                    throw new RuntimeError('Function not found: $name', pos);
                }

        }

    }

    function writeAccess(access:RuntimeAccess, value:Any):Void {

        switch access {
            case FieldAccess(pos, obj, name):
                setField(obj, name, value);

            case ArrayAccess(pos, array, index):
                array[index] = value;

            case CharacterAccess(pos, name):
                throw new RuntimeError('Cannot overwrite character: $name', pos);

            case FunctionAccess(pos, name):
                throw new RuntimeError('Cannot overwrite function: $name', pos);

        }

    }

    function resolveAssignmentTarget(target:NExpr):RuntimeAccess {

        return switch (Type.getClass(target)) {

            case NAccess:
                final access:NAccess = cast target;
                resolveAccess(access, access.target, access.name);

            case NArrayAccess:
                final arrAccess:NArrayAccess = cast target;
                final target = evaluateExpression(arrAccess.target);
                final index = evaluateExpression(arrAccess.index);

                if (target is Array && (index is Int || index is Float)) {
                    final i:Int = Std.int(index);
                    final arr:Array<Any> = target;
                    ArrayAccess(arrAccess.pos, arr, i);
                }
                else {
                    throw new RuntimeError('Invalid array access target', arrAccess.pos);
                }

            case _:
                throw new RuntimeError('Invalid assignment target', target.pos);
        }

    }

    function resolveAccess(access:NAccess, ?target:NExpr, name:String):RuntimeAccess {

        if (target != null) {
            final evaluated = evaluateExpression(target);
            return FieldAccess(target.pos, evaluated, name);
        }

        // Iterate through scopes to identify a matching state field or character name
        var i = stack.length - 1;
        while (i >= 0) {
            final scope = stack[i];

            // Check temporary state
            if (scope.state != null) {
                if (fieldExists(scope.state.fields, name)) {
                    return FieldAccess(
                        access?.pos ?? currentScope?.node?.pos ?? script.pos,
                        scope.state.fields,
                        name
                    );
                }
            }

            i--;
        }

        // Look for state fields
        if (fieldExists(topLevelState.fields, name)) {
            return FieldAccess(
                access?.pos ?? currentScope?.node?.pos ?? script.pos,
                topLevelState.fields,
                name
            );
        }

        // Look for characters
        if (topLevelCharacters.exists(name)) {
            return CharacterAccess(
                access?.pos ?? currentScope?.node?.pos ?? script.pos,
                name
            );
        }

        // Look for functions
        if (topLevelFunctions.exists(name)) {
            return FunctionAccess(
                access?.pos ?? currentScope?.node?.pos ?? script.pos,
                name
            );
        }

        throw new RuntimeError('Undefined variable: $name', access?.pos ?? currentScope?.node?.pos ?? script.pos);

    }

    /**
     * Helper for getting human-readable type names in errors
     */
    function getTypeName(t:ValueType):String {
        return switch t {
            case TNull: "Null";
            case TInt: "Int";
            case TFloat: "Float";
            case TBool: "Bool";
            case TObject: "Object";
            case TFunction: "Function";
            case TClass(c): Type.getClassName(c);
            case TEnum(e): Type.getEnumName(e);
            case TUnknown: "Unknown";
        }
    }

    function performOperation(op:TokenType, left:Dynamic, right:Dynamic, pos:Position):Any {
        // Get precise runtime types
        final leftType = Type.typeof(left);
        final rightType = Type.typeof(right);

        return switch op {
            case OpPlus:
                switch [leftType, rightType] {
                    // Number + Number
                    case [TInt | TFloat, TInt | TFloat]:
                        Std.parseFloat(Std.string(left)) + Std.parseFloat(Std.string(right));
                    // String + Any (allows string concatenation)
                    case [TClass(String), _] | [_, TClass(String)]:
                        Std.string(left) + Std.string(right);
                    case _:
                        throw new RuntimeError('Cannot add ${getTypeName(leftType)} and ${getTypeName(rightType)}', pos ?? currentScope?.node?.pos ?? script.pos);
                }

            case OpMinus | OpMultiply | OpDivide | OpModulo:
                switch [leftType, rightType] {
                    case [TInt | TFloat, TInt | TFloat]:
                        final leftNum = Std.parseFloat(Std.string(left));
                        final rightNum = Std.parseFloat(Std.string(right));
                        switch op {
                            case OpMinus: leftNum - rightNum;
                            case OpMultiply: leftNum * rightNum;
                            case OpDivide:
                                if (rightNum == 0) throw new RuntimeError('Division by zero', pos ?? currentScope?.node?.pos ?? script.pos);
                                leftNum / rightNum;
                            case OpModulo:
                                if (rightNum == 0) throw new RuntimeError('Modulo by zero', pos ?? currentScope?.node?.pos ?? script.pos);
                                leftNum % rightNum;
                            case _: throw "Unreachable";
                        }
                    case _:
                        final opName = switch op {
                            case OpMinus: "subtract";
                            case OpMultiply: "multiply";
                            case OpDivide: "divide";
                            case OpModulo: "modulo";
                            case _: "perform operation on";
                        }
                        throw new RuntimeError('Cannot ${opName} ${getTypeName(leftType)} and ${getTypeName(rightType)}', pos ?? currentScope?.node?.pos ?? script.pos);
                }

            case OpEquals | OpNotEquals:
                // Allow comparison between any types
                switch op {
                    case OpEquals: left == right;
                    case OpNotEquals: left != right;
                    case _: throw "Unreachable";
                }

            case OpGreater | OpGreaterEq | OpLess | OpLessEq:
                switch [leftType, rightType] {
                    case [TInt | TFloat, TInt | TFloat]:
                        final leftNum = Std.parseFloat(Std.string(left));
                        final rightNum = Std.parseFloat(Std.string(right));
                        switch op {
                            case OpGreater: leftNum > rightNum;
                            case OpGreaterEq: leftNum >= rightNum;
                            case OpLess: leftNum < rightNum;
                            case OpLessEq: leftNum <= rightNum;
                            case _: throw "Unreachable";
                        }
                    case _:
                        throw new RuntimeError('Cannot compare ${getTypeName(leftType)} and ${getTypeName(rightType)}', pos ?? currentScope?.node?.pos ?? script.pos);
                }

            case OpAnd | OpOr:
                switch [leftType, rightType] {
                    case [TBool, TBool]:
                        switch op {
                            case OpAnd: left && right;
                            case OpOr: left || right;
                            case _: throw "Unreachable";
                        }
                    case _:
                        throw new RuntimeError('Cannot perform logical operation on ${getTypeName(leftType)} and ${getTypeName(rightType)}', pos ?? currentScope?.node?.pos ?? script.pos);
                }

            case _:
                throw new RuntimeError('Invalid operation: $op', pos ?? currentScope?.node?.pos ?? script.pos);
        }
    }

    function valueToString(value:Any):String {

        return Std.string(value);

    }

    #if loreline_debug_interpreter
    public static dynamic function debug(message:String, ?pos:haxe.PosInfos) {
        trace(message);
    }
    #else
    macro static function debug(expr:haxe.macro.Expr) {
        return macro null;
    }
    #end

}