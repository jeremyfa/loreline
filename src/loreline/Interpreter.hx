package loreline;

import Type.ValueType;
import haxe.ds.StringMap;
import loreline.Arrays;
import loreline.Lexer;
import loreline.Node;
import loreline.Objects;
import loreline.SaveData;

using StringTools;
using loreline.Utf8;


/**
 * A state during the runtime execution of a loreline script.
 * States hold field values that can be accessed and modified during script execution.
 */
class RuntimeState {

    /**
     * If set to a value > 0, this state is temporary and linked to a scope.
     * Every time we enter a new block node, we enter a new scope identified by a unique integer value.
     * When exiting that scope, the related temporary states are destroyed.
     */
    public var scope:Int = -1;

    /**
     * Fields of this state. Contains the actual data being stored.
     */
    public var fields(default, null):Any;

    /**
     * Original field values, as they are initially declared in the script,
     * as long as they are not dependent on other state values.
     * Used for comparison when serializing to avoid storing unchanged values.
     */
    public var originalFields(default, null):Any;

    /**
     * Creates a new runtime state with optional initial field values.
     *
     * @param fields Initial field values, or null to create empty fields
     * @param originalFields Original field values for comparison, or null to create empty original fields
     */
    public function new(interpreter:Interpreter, node:Node, fields:Any, originalFields:Any) {
        if (fields != null) {
            this.fields = fields;
        }
        else {
            clear(interpreter, node);
        }

        if (originalFields != null) {
            this.originalFields = originalFields;
        }
        else {
            createOriginalFields();
        }
    }

    /**
     * Clears all fields in this state.
     */
    public function clear(interpreter:Interpreter, node:Node):Void {
        this.fields = Objects.createFields(interpreter, null, node);
    }

    /**
     * Creates empty original fields.
     */
    function createOriginalFields():Void {
        this.originalFields = Objects.createFields();
    }

}

/**
 * Runtime state variant specifically used for character states.
 * Characters are special entities in Loreline scripts that can have their own properties
 * and can be referenced in dialogue statements.
 */
class RuntimeCharacter extends RuntimeState {

    /**
     * Creates a new character runtime state with optional initial field values.
     */
    public function new(interpreter:Interpreter, node:AstNode, fields:Any, originalFields:Any) {
        super(interpreter, node, fields, originalFields);
    }

}

/**
 * Represents different ways to access runtime values in a Loreline script.
 * This is used internally by the interpreter to resolve variable accesses,
 * array accesses, character references, and function calls.
 */
enum RuntimeAccess {

    /**
     * Represents access to a field of an object.
     *
     * @param pos Position in the source code where this access occurs
     * @param obj The object being accessed
     * @param name The name of the field to access
     */
    FieldAccess(pos:Position, obj:Any, name:String);

    /**
     * Represents access to an array element by index.
     *
     * @param pos Position in the source code where this access occurs
     * @param array The array being accessed
     * @param index The index into the array
     */
    ArrayAccess(pos:Position, array:Any, index:Int);

    /**
     * Represents access to a character by name.
     *
     * @param pos Position in the source code where this access occurs
     * @param name The name of the character to access
     */
    CharacterAccess(pos:Position, name:String);

    /**
     * Represents access to a built-in or user-defined function.
     *
     * @param pos Position in the source code where this access occurs
     * @param name The name of the function to access
     */
    FunctionAccess(pos:Position, name:String);

}

/**
 * Represents a scope in the execution stack of a Loreline script.
 * Every time we enter a new block node, we enter a new scope identified with a unique integer value.
 * When exiting that scope, the related temporary states associated with it are destroyed.
 */
@:structInit
class RuntimeScope {

    /**
     * The scope id, a unique integer value in the stack.
     */
    public var id:Int = -1;

    /**
     * The parent beat where this scope is located.
     * Can be either a top level beat or a nested beat.
     */
    public var beat:NBeatDecl;

    /**
     * The node where this scope is attached.
     */
    public var node:AstNode;

    /**
     * The nested beat declarations, if any, found in this scope.
     */
    public var beats:Array<NBeatDecl> = null;

    /**
     * The temporary state associated with this scope, if any.
     */
    public var state:RuntimeState = null;

    /**
     * If applicable, the node this scope's "reading head" is at.
     * This is used to track the current execution position within the scope.
     */
    public var head:AstNode = null;

    /**
     * If this scope was created from an insertion, this is the insertion runtime data.
     */
    public var insertion:RuntimeInsertion = null;

    /**
     * Finds a nested beat declaration with the given name in this scope, if any.
     *
     * @param name The name of the beat to find
     * @return The beat declaration if found, null otherwise
     */
    public function beatByName(name:String):Null<NBeatDecl> {
        if (beats == null) return null;
        for (i in 0...beats.length) {
            final beat = beats[i];
            if (beat.name == name) {
                return beat;
            }
        }
        return null;
    }

}

/**
 * Fata that needs to be hold with a scope when
 * a beat is being inserted within a choice
 */
class RuntimeInsertion {

    /**
     * The insertion id, a unique integer value among all insertions.
     */
    public var id:Int;

    /**
     * The original node causing that insertion
     */
    public var origin:NInsertion;

    /**
     * The inserted choice options, or `null` if nothing is inserted yet
     */
    public var options:Array<ChoiceOption> = null;

    /**
     * The call stack of this insertion, which is used to resume
     * the execution at the correct location when a choice of it has been selected
     */
    public var stack:Array<RuntimeScope> = [];

    public function new(id:Int, origin:NInsertion) {
        this.id = id;
        this.origin = origin;
    }

}

/**
 * Represents a tag in text content, which can be used for styling or other purposes.
 */
@:structInit
#if cs
@:struct
#end
class TextTag {
    /**
     * Whether this is a closing tag.
     */
    public var closing:Bool;

    /**
     * The value or name of the tag.
     */
    public var value:String;

    /**
     * The offset in the text where this tag appears.
     */
    public var offset:Int;
}

/**
 * Represents a choice option presented to the user.
 */
@:structInit
#if cs
@:struct
#end
class ChoiceOption {
    /**
     * The text of the choice option.
     */
    public var text:String;

    /**
     * Any tags associated with the choice text.
     */
    public var tags:Array<TextTag>;

    /**
     * Whether this choice option is currently enabled.
     */
    public var enabled:Bool;

    /**
     * The related choice option node, only used internally
     */
    @:allow(loreline.Interpreter)
    private var node:NChoiceOption;

    /**
     * The related insertion of this option.
     * Needed to be able to resume execution if that choice option is chosen.
     */
    @:allow(loreline.Interpreter)
    private var insertion:RuntimeInsertion;

}

/**
 * Handler type for text output with callback.
 * This is called when the script needs to display text to the user.
 *
 * @param interpreter The interpreter instance
 * @param character The character speaking (null for narrator text)
 * @param text The text content to display
 * @param tags Any tags in the text
 * @param callback Function to call when the text has been displayed
 */
typedef DialogueHandler = (interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void)->Void;

/**
 * Handler type for choice presentation with callback.
 * This is called when the script needs to present choices to the user.
 *
 * @param interpreter The interpreter instance
 * @param options The available choice options
 * @param callback Function to call with the index of the selected choice
 */
typedef ChoiceHandler = (interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void)->Void;

/**
 * Handler type to be called when the execution finishes.
 *
 * @param interpreter The interpreter instance
 */
typedef FinishHandler = (interpreter:Interpreter)->Void;

/**
 * Runtime error that can occur during script execution.
 */
class RuntimeError extends Error {

}

/**
 * Helper class for managing the next evaluation step.
 * Used to control whether the next step should be executed synchronously or asynchronously.
 */
class EvalNext {
    /**
     * Whether the next step should be executed synchronously.
     */
    public var sync:Bool = true;

    /**
     * The callback to execute for the next step.
     */
    public var cb:()->Void = null;

    /**
     * Creates a new EvalNext instance.
     */
    public function new() {}
}

#if loreline_functions_map_dynamic_access
typedef FunctionsMap = haxe.DynamicAccess<Any>;
#else
typedef FunctionsMap = haxe.ds.Map<String,Any>;
#end

#if loreline_typedef_options
typedef InterpreterOptions = {
#else
@:structInit class InterpreterOptions {
#end

    #if cs
    /**
     * When using Loreline outside of Haxe, the interpreter can be wrapped by
     * an object more tailored for the host platform. This is that wrapper object.
     */
    public var wrapper:Any = null;
    #end

    /**
     * Optional map of additional functions to make available to the script
     */
    #if loreline_typedef_options @:optional #end
    public var functions:FunctionsMap #if !loreline_typedef_options = null #end;

    /**
     * Tells whether access is strict or not. If set to true,
     * trying to read or write an undefined variable will throw an error.
     */
    #if loreline_typedef_options @:optional #end
    public var strictAccess:Bool #if !loreline_typedef_options = false #end;

    /**
     * A custom instanciator to create fields objects.
     */
    #if loreline_typedef_options @:optional #end
    public var customCreateFields:(interpreter:Interpreter, type:String, node:Node)->Any #if !loreline_typedef_options = null #end;

}

/**
 * Main interpreter class for Loreline scripts.
 * This class is responsible for executing a parsed Loreline script,
 * managing the runtime state, and interacting with the host application
 * through handler functions.
 */
#if hscript
@:allow(loreline.HscriptInterp)
#end
#if js
@:expose
#end
@:keep class Interpreter {

    /**
     * The script being executed.
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
     * which is called when the current execution has finished.
     */
    final handleFinish:FinishHandler;

    /**
     * The top level state, which is shared across the whole script execution.
     */
    final topLevelState:RuntimeState;

    /**
     * Top level characters can be referenced and their state
     * can also be modified from anywhere in the script.
     */
    final topLevelCharacters:Map<String, RuntimeCharacter> = new Map();

    /**
     * All the top level beats available, by beat name (their identifier in the script).
     */
    final topLevelBeats:Map<String, NBeatDecl> = new Map();

    /**
     * States associated to a specific node id. These are persistent, like the top level state,
     * but are only available from where they have been declared and the sub-scopes.
     * If some state fields already existed in a parent scope, the parent ones will be shadowed by the child ones.
     */
    final nodeStates:NodeIdMap<RuntimeState> = new NodeIdMap();

    /**
     * Top level functions available by default in this script.
     */
    final topLevelFunctions:Map<String, Any> = new Map();

    /**
     * The current execution stack, which consists of scopes added on top of one another.
     * Each scope can have its own local beats and temporary states.
     */
    final stack:Array<RuntimeScope> = [];

    /**
     * The lens instance allowing to get more information about the AST.
     */
    final lens:Lens;

    /**
     * Tells whether access is strict or not. If set to true,
     * trying to read or write an undefined variable will throw an error.
     */
    final strictAccess:Bool;

    /**
     * Current scope associated with current execution state.
     */
    var currentScope(get,never):RuntimeScope;
    function get_currentScope():RuntimeScope {
        return stack.length > 0 ? stack[stack.length - 1] : null;
    }

    /**
     * Current insertion associated with current scope or a parent scope, with current execution state.
     */
    var currentInsertion(get,never):RuntimeInsertion;
    function get_currentInsertion():RuntimeInsertion {
        var i = stack.length - 1;
        while (i >= 0) {
            final scope = stack[i];
            if (scope.insertion != null) {
                return scope.insertion;
            }
            i--;
        }
        return null;
    }

    function removeCurrentInsertion() {
        var i = stack.length - 1;
        while (i >= 0) {
            final scope = stack[i];
            if (scope.insertion != null) {
                scope.insertion = null;
                break;
            }
            i--;
        }
    }

    /**
     * The next scope id to assign when pushing a new scope.
     * Every time we reset the stack, this counter is also reset.
     */
    var nextScopeId:Int = 1;

    /**
     * The next insertion id to assign when creating a new insertion.
     * Every time we reset the stack, this counter is also reset.
     */
    var nextInsertionId:Int = 1;

    /**
     * List of pending callbacks that should be run synchronously.
     */
    var syncCallbacks:Array<()->Void> = [];

    /**
     * Internal flag to know if we are currently flushing sync callbacks
     * (to prevent unexpected recursive flushes).
     */
    var flushing:Bool = false;

    /**
     * Keep track of which callback is the one that would trigger finish.
     */
    var finishTrigger:EvalNext = null;

    /**
     * When loading saved data and failing to restore a full stack of scope,
     * this contains the beat to resume as fallback.
     * That beat will always be a top level beat.
     */
    var beatToResume:NBeatDecl = null;

    /**
     * A custom instanciator to create fields objects.
     */
    var customCreateFields:(interpreter:Interpreter, type:String, node:Node)->Any;

    #if cs
    /**
     * When using Loreline outside of Haxe, the interpreter can be wrapped by
     * an object more tailored for the host platform. This is that wrapper object.
     */
    var wrapper:Any = null;
    #end

    /**
     * Creates a new Loreline script interpreter.
     *
     * @param script The parsed script to execute
     * @param handleDialogue Function to call when displaying dialogue text
     * @param handleChoice Function to call when presenting choices
     * @param handleFinish Function to call when execution finishes
     * @param options Additional options
     */
    public function new(script:Script, handleDialogue:DialogueHandler, handleChoice:ChoiceHandler, handleFinish:FinishHandler, ?options:InterpreterOptions) {

        this.script = script;
        this.handleDialogue = handleDialogue;
        this.handleChoice = handleChoice;
        this.handleFinish = handleFinish;

        this.lens = new Lens(script);

        this.strictAccess = options?.strictAccess ?? false;

        #if cs
        this.wrapper = options?.wrapper;
        #end

        this.topLevelState = new RuntimeState(this, script, null, null);

        // Build default function
        initializeTopLevelFunctions(options?.functions);

        // Init top level declarations
        for (decl in script) {
            switch Type.getClass(decl) {

                // State
                case NStateDecl:
                    initializeTopLevelState(cast decl);

                // Character
                case NCharacterDecl:
                    initializeTopLevelCharacter(cast decl);

                // Beat
                case NBeatDecl:
                    initializeTopLevelBeat(cast decl);

                // Function
                case NFunctionDecl:
                    initializeTopLevelFunction(cast decl);

                case _:
            }
        }

    }

    /**
     * Starts script execution from the beginning or a specific beat.
     *
     * @param beatName Optional name of the beat to start from. If null, execution starts from
     *                 the first beat or a beat named "_" if it exists.
     * @throws RuntimeError If the specified beat doesn't exist or if no beats are found in the script
     */
    public function start(?beatName:String) {

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
            for (decl in script) {
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
                for (decl in script) {
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

    /**
     * Saves the current state of the interpreter.
     * This includes all state variables, character states, and execution stack,
     * allowing execution to be resumed later from the exact same point.
     *
     * @return A SaveData object containing the serialized state
     */
    public function save():SaveData {

        final insertions:Dynamic<SaveDataInsertion> = {};

        final result:SaveData = {
            version: 1,
            stack: [
                for (scope in stack) serializeScope(scope, insertions)
            ],
            state: serializeState(topLevelState),
            characters: serializeCharacters(),
            nodeStates: serializeNodeStates()
        };

        if (Reflect.fields(insertions).length > 0) {
            result.insertions = insertions;
        }

        return result;

    }

    /**
     * Restores the interpreter state from a SaveData object.
     * This allows resuming execution from a previously saved state.
     *
     * @param saveData The SaveData object containing the serialized state
     * @throws RuntimeError If the save data version is incompatible
     */
    public function restore(saveData:SaveData):Void {

        // Verify version compatibility
        if (saveData.version != 1) {
            throw new RuntimeError("Unsupported save version: " + saveData.version, script.pos);
        }

        // Clear current state
        stack.resize(0);
        nodeStates.clear();
        nextScopeId = 1;
        nextInsertionId = 1;

        // Restore top level state
        restoreState(topLevelState, saveData.state);

        // Restore character states
        restoreCharacters(saveData.characters);

        // Restore node states
        restoreNodeStates(saveData.nodeStates);

        // Restore scope stack
        if (!restoreStack(saveData.stack)) {
            // If failed to restore stack, simply resolve last known top level beat as fallback
            beatToResume = restoreBeatToResume(saveData.stack);
        }

    }

    /**
     * Resumes execution after restoring state.
     * This should be called after restore() to continue execution.
     */
    public function resume() {

        // If there is no stack, simply start
        if (stack.length == 0) {
            start();
            return;
        }

        // Prepare to continue execution
        final done = wrapNext(finish);

        // We now consider that finishing this
        // execution chain is the finish trigger
        finishTrigger = done;

        // Resume from the top scope
        resumeNode(stack[0].node, 0, done.cb);
        done.sync = false;

        // Process any pending operations
        flush();

    }

    function resumeFromLevel(scopeLevel:Int, next:()->Void) {

        // Prepare to continue execution
        final done = wrapNext(next);

        // We now consider that finishing this
        // execution chain is the finish trigger
        finishTrigger = done;

        // Resume from the top scope
        resumeNode(stack[scopeLevel].node, scopeLevel, done.cb);
        done.sync = false;

    }

    /**
     * Gets a character by name.
     *
     * @param name The name of the character to get
     * @return The character's fields or null if the character doesn't exist
     */
    public function getCharacter(name:String):Any {

        return topLevelCharacters.get(name)?.fields;

    }

    /**
     * Gets a specific field of a character.
     *
     * @param character The name of the character
     * @param name The name of the field to get
     * @return The field value or null if the character or field doesn't exist
     */
    public function getCharacterField(character:String, name:String):Any {

        final fields = topLevelCharacters.get(character)?.fields;
        if (fields != null) {
            return Objects.getField(this, fields, name);
        }
        return null;

    }

    /**
     * Serializes a scope to save data.
     *
     * @param scope The scope to serialize
     * @return The serialized scope data
     */
    function serializeScope(scope:RuntimeScope, insertions:Dynamic<SaveDataInsertion>):SaveDataScope {

        final result:SaveDataScope = {
            id: scope.id
        };

        if (scope.beat != null) {
            result.beat = serializeBeatReference(scope.beat);
        }

        if (scope.node != null) {
            result.node = serializeNodeReference(scope.node);
        }

        if (scope.state != null) {
            result.state = serializeState(scope.state);
        }

        if (scope.beats != null) {
            result.beats = [for (beat in scope.beats) serializeBeatReference(beat)];
        }

        if (scope.head != null) {
            result.head = serializeNodeReference(scope.head);
        }

        if (scope.insertion != null) {
            result.insertion = serializeInsertion(scope.insertion, insertions);
        }

        return result;

    }

    function serializeInsertion(insertion:RuntimeInsertion, insertions:Dynamic<SaveDataInsertion>) {

        final key:String = Std.string(insertion.id);

        var serialized:SaveDataInsertion = Reflect.field(insertions, key);

        if (serialized == null) {
            serialized = {};

            if (insertion.options != null) {
                serialized.options = [for (opt in insertion.options) serializeChoiceOption(opt, insertions)];
            }

            if (insertion.origin != null) {
                serialized.origin = serializeNodeReference(insertion.origin);
            }

            if (insertion.stack != null) {
                serialized.stack = [for (scope in insertion.stack) serializeScope(scope, insertions)];
            }

            Reflect.setField(insertions, key, serialized);
        }

        return insertion.id;

    }

    function serializeChoiceOption(option:ChoiceOption, insertions:Dynamic<SaveDataInsertion>) {

        final result:SaveDataChoiceOption = {
            text: option.text
        };

        if (!option.enabled) {
            result.disabled = true;
        }

        if (option.tags != null) {
            result.tags = [for (tag in option.tags) serializeTextTag(tag)];
        }

        if (option.node != null) {
            result.node = serializeNodeReference(option.node);
        }

        if (option.insertion != null) {
            result.insertion = serializeInsertion(option.insertion, insertions);
        }

        return result;

    }

    function serializeTextTag(tag:TextTag) {

        final result:SaveDataTextTag = {
            value: tag.value,
            offset: tag.offset
        };

        if (tag.closing) {
            result.closing = true;
        }

        return result;

    }

    /**
     * Serializes a state to save data.
     *
     * @param state The state to serialize
     * @return The serialized state data
     */
    function serializeState(state:RuntimeState):SaveDataState {

        return serializeFields(state.fields, state.originalFields);

    }

    /**
     * Serializes all top-level characters to save data.
     *
     * @return Object mapping character names to their serialized states
     */
    function serializeCharacters():Dynamic<SaveDataCharacter> {

        final result:Dynamic<SaveDataCharacter> = {};
        for (name => character in topLevelCharacters) {
            final serialized = serializeCharacter(character);
            if (Reflect.fields(serialized.fields).length > 0) {
                Reflect.setField(result, name, serialized);
            }
        }
        return result;

    }

    /**
     * Serializes all node states to save data.
     *
     * @return Object mapping node IDs to their serialized states
     */
    function serializeNodeStates():Dynamic<SaveDataState> {

        final result:Dynamic<SaveDataState> = {};
        for (id => state in nodeStates) {
            final serialized = serializeState(state);
            if (Reflect.fields(serialized.fields).length > 0) {
                Reflect.setField(result, id.toString(), serialized);
            }
        }
        return result;

    }

    /**
     * Serializes a beat reference for save data.
     *
     * @param beat The beat to reference
     * @return The serialized beat reference
     */
    function serializeBeatReference(beat:NBeatDecl):SaveDataBeat {

        var path = beat.name;
        var parentBeat = beat;

        do {
            parentBeat = lens.getFirstParentOfType(parentBeat, NBeatDecl);
            if (parentBeat != null) {
                path = parentBeat.name + '.' + path;
            }
        }
        while (parentBeat != null);

        return {
            id: beat.id.toString(),
            path: beat.name
        };

    }

    /**
     * Serializes a node reference for save data.
     *
     * @param node The node to reference
     * @return The serialized node reference
     */
    function serializeNodeReference(node:AstNode):SaveDataNode {

        return {
            id: node.id.toString(),
            type: node.type()
        };

    }

    /**
     * Serializes a character for save data.
     *
     * @param character The character to serialize
     * @return The serialized character data
     */
    function serializeCharacter(character:RuntimeCharacter):SaveDataCharacter {

        return serializeFields(character.fields, character.originalFields);

    }

    /**
     * Serializes fields for save data.
     * Only fields that have changed from their original values are included.
     *
     * @param fields The fields to serialize
     * @param originalFields The original field values for comparison
     * @return The serialized fields data
     */
    function serializeFields(fields:Any, ?originalFields:Any):SaveDataFields {

        var type:String = null;
        final result:Dynamic = {};

        if (fields is Fields) {
            final cls = Type.getClass(fields);
            if (cls != null)
                type = Type.getClassName(cls);
            final fieldMap:Fields = cast fields;
            for (key in fieldMap.lorelineFields(this)) {
                Reflect.setField(result, key, serializeValue(fieldMap.lorelineGet(this, key)));
            }
        }
        else if (fields is StringMap) {
            final map:StringMap<Any> = cast fields;
            for (key in map.keys()) {
                final value = map.get(key);
                if (originalFields == null || !Objects.fieldExists(this, originalFields, key) || !Equal.equal(this, Objects.getField(this, originalFields, key), value)) {
                    Reflect.setField(result, key, serializeValue(value));
                }
            }
        }
        #if cs
        else if (Objects.isCsDict(fields)) {
            type = 'System.Collections.IDictionary';
            final keys = Objects.getCsDictKeys(fields);
            for (key in keys) {
                Reflect.setField(result, key, serializeValue(Objects.getCsDictField(fields, key)));
            }
        }
        #end
        else {
            final cls = Type.getClass(fields);
            if (cls != null)
                type = Type.getClassName(cls);
            for (field in Reflect.fields(fields)) {
                final value = Reflect.getProperty(fields, field);
                if (originalFields == null || !Objects.fieldExists(this, originalFields, field) || !Equal.equal(this, Objects.getField(this, originalFields, field), value)) {
                    Reflect.setField(result, field, serializeValue(value));
                }
            }
        }

        if (type != null) {
            return {
                type: type,
                fields: result
            };
        }
        else {
            return {
                fields: result
            };
        }

    }

    /**
     * Serializes a value for save data.
     * Handles recursive serialization of objects and arrays.
     *
     * @param value The value to serialize
     * @return The serialized value
     */
    function serializeValue(value:Any) {

        if (value == null) {
            return null;
        }

        // Handle basic types that can be directly serialized
        if (Std.isOfType(value, String) ||
            Std.isOfType(value, Float) ||
            Std.isOfType(value, Int) ||
            Std.isOfType(value, Bool)) {
            return value;
        }

        // Handle arrays
        if (Arrays.isArray(value)) {
            final arr = [];
            final len = Arrays.arrayLength(value);

            for (i in 0...len) {
                arr.push(serializeValue(Arrays.arrayGet(value, i)));
            }

            return arr;
        }

        // Handle objects/maps recursively
        return serializeFields(value);

    }

    /**
     * Core function that resumes execution from a given scope.
     * Works by recreating the execution flow as if we had been running from the beginning.
     *
     * @param node The node to resume from
     * @param scopeLevel The scope level to resume at
     * @param next Callback to call when the node execution completes
     * @throws RuntimeError If resuming from the node is not supported
     */
    function resumeNode(node:AstNode, scopeLevel:Int, next:()->Void):Void {

        // Resolve last level
        final lastLevel = stack.length - 1;

        // Is last node?
        final isLastNode = (scopeLevel >= stack.length);

        // Depending on the type of node, decide what to do
        if (!isLastNode) {
            switch Type.getClass(node) {

                case NBeatDecl:
                    resumeBeatRun(cast node, scopeLevel, next);
                case NChoiceOption:
                    resumeChoiceOption(cast node, scopeLevel, next);
                case NChoiceStatement:
                    resumeChoice(cast node, scopeLevel, next);
                case NIfStatement:
                    resumeIf(cast node, scopeLevel, next);
                case NCall if (isBeatCall(node, scopeLevel)):
                    resumeCall(cast node, scopeLevel, next);

                case _:
                    throw new RuntimeError('Resume execution not supported from node within stack: ${Type.getClassName(Type.getClass(node))}', node.pos);
            }
        }
        else {
            switch Type.getClass(node) {

                case NCall if (!isBeatCall(node)):
                    evalCall(cast node, next);
                case NChoiceStatement:
                    evalChoice(cast node, next);
                case NTextStatement:
                    evalText(cast node, next);
                case NDialogueStatement:
                    evalDialogue(cast node, next);

                case _:
                    throw new RuntimeError('Resume execution not supported from last node: ${Type.getClassName(Type.getClass(node))}', node.pos);
            }
        }

    }

    /**
     * Resumes execution of a node body.
     *
     * @param node The node containing the body
     * @param scopeLevel The scope level to resume at
     * @param body The body to execute
     * @param next Callback to call when the body execution completes
     * @throws RuntimeError If resuming the body is not possible
     */
    function resumeNodeBody(node:AstNode, scopeLevel:Int, body:Array<AstNode>, next:()->Void) {

        // Step in scope
        final currentScope = stack[scopeLevel];

        // If no head, then this should be the bottom of the stack
        var index = 0;
        var resumeIndex = -1;
        if (currentScope.head == null && scopeLevel < stack.length - 1) {
            throw new RuntimeError('Cannot resume through a body with a no-headed scope that is not at the bottom of the stack', node.pos);
        }

        // Ensure head is within this beat body, if any
        if (currentScope.head != null) {
            index = body.indexOf(currentScope.head);
            resumeIndex = index;
            if (index == -1) {
                throw new RuntimeError('Failed to resolve head in scope when resuming through body', node.pos);
            }
        }

        // Then iterate through each child node in the body
        var moveNext:()->Void = null;
        moveNext = () -> {

            // Check if we are in the resuming index
            if (index != -1 && index == resumeIndex) {

                // That's the one
                final childNode = body[index];
                index++;
                final done = wrapNext(moveNext);
                resumeNode(childNode, scopeLevel + 1, done.cb);
                done.sync = false;

            }
            // Or check if we still have a node to evaluate
            else if (index < body.length) {

                // Yes, do it
                final childNode = body[index];
                currentScope.head = childNode;
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

    /**
     * Resumes execution of a beat.
     *
     * @param beat The beat to resume
     * @param scopeLevel The scope level to resume at
     * @param next Callback to call when the beat execution completes
     */
    function resumeBeatRun(beat:NBeatDecl, scopeLevel:Int, next:()->Void) {

        resumeNodeBody(beat, scopeLevel, beat.body, next);

    }

    /**
     * Resumes execution of a choice option.
     *
     * @param option The choice option to resume
     * @param scopeLevel The scope level to resume at
     * @param next Callback to call when the option execution completes
     */
    function resumeChoiceOption(option:NChoiceOption, scopeLevel:Int, next:()->Void) {

        resumeNodeBody(option, scopeLevel, option.body, next);

    }

    /**
     * Resumes execution of a choice
     */
    function resumeChoice(choice:NChoiceStatement, scopeLevel:Int, next:()->Void) {

        // Step in scope
        final currentScope = stack[scopeLevel];

        if (currentScope.head == null) {
            evalChoice(choice, next);
        }
        else if (currentScope.head is NChoiceOption) {
            final option:NChoiceOption = cast currentScope.head;
            evalNodeBody(currentScope.beat, option, option.body, next);
        }
        else {
            throw new RuntimeError('Choice head is not a choice option', currentScope.head.pos);
        }

    }

    /**
     * Resumes execution of an if statement.
     *
     * @param ifStmt The if statement to resume
     * @param scopeLevel The scope level to resume at
     * @param next Callback to call when the if statement execution completes
     * @throws RuntimeError If resuming the if statement is not possible
     */
    function resumeIf(ifStmt:NIfStatement, scopeLevel:Int, next:()->Void) {

        // Step in scope
        final currentScope = stack[scopeLevel];

        // Ensure there is a head
        if (currentScope.head == null) {
            throw new RuntimeError('Failed to resolve head in scope when resuming through condition', ifStmt.pos);
        }

        // Check if scope head is part of then or else branch
        final isTrue = ifStmt.thenBranch.body.indexOf(currentScope.head) != -1;

        // Resolve the branch from that
        final branch = isTrue ? ifStmt.thenBranch : ifStmt.elseBranch;

        if (branch != null && branch.body.length > 0) {
            resumeNodeBody(branch, scopeLevel, branch.body, next);
        }
        else {
            throw new RuntimeError('Failed to resume condition: invalid scope', ifStmt.pos);
        }

    }

    /**
     * Resumes execution of a beat call.
     *
     * @param call The call node to resume
     * @param scopeLevel The scope level to resume at
     * @param next Callback to call when the call execution completes
     * @throws RuntimeError If resuming the call is not possible
     */
    function resumeCall(call:NCall, scopeLevel:Int, next:()->Void) {

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
                    final beatInScope = scope.beatByName(beatName);
                    if (beatInScope != null) {
                        resolvedBeat = beatInScope;
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
                    resumeBeatRun(resolvedBeat, scopeLevel, next);
                    return;
                }
            }
        }

        throw new RuntimeError('Cannot resume through a function call that is not at the bottom of the stack', call.pos);

    }

    /**
     * Restores the execution stack from saved data.
     *
     * @param savedStack The saved stack data
     * @return True if the stack was restored successfully, false otherwise
     */
    function restoreStack(savedStack:Array<SaveDataScope>):Bool {

        final result:Array<RuntimeScope> = [];

        var i = savedStack.length - 1;
        while (i >= 0) {
            final savedScope = savedStack[i];
            final beat:NBeatDecl = restoreBeat(savedScope.beat);

            if (beat == null) {
                // Failed to resolve beat,
                // can't restore stack
                return false;
            }

            final savedBeatId = NodeId.fromString(savedScope.beat.id);

            final savedNode = savedScope.node;
            final node:AstNode = if (savedNode != null) {
                restoreNode(
                    savedNode,
                    savedBeatId,
                    beat
                );
            }
            else {
                null;
            }

            if (savedNode != null && node == null) {
                // Failed to resolve node,
                // can't restore stack
                return false;
            }

            final beats:Array<NBeatDecl> = [];
            if (savedScope.beats != null) {
                for (savedBeat in savedScope.beats) {
                    final beatInScope = restoreBeat(savedBeat);
                    if (beatInScope == null) {
                        // Failed to resolve beat in scope,
                        // can't restore stack
                        return false;
                    }
                    beats.push(beatInScope);
                }
            }

            final savedState = savedScope.state;
            final state:RuntimeState = savedState != null ? restoreState(null, savedScope.state) : null;

            final savedHead = savedScope.head;
            final head:AstNode = if (savedHead != null) {
                restoreNode(
                    savedHead,
                    savedBeatId,
                    beat
                );
            }
            else {
                null;
            }

            if (savedHead != null && head == null) {
                // Failed to resolve head,
                // can't restore stack
                return false;
            }

            // Keep scope item
            result.push({
                beat: beat,
                node: node,
                state: state,
                beats: beats,
                head: head
            });

            i--;
        }

        // Add the items in the actual stack
        i = result.length - 1;
        while (i >= 0) {
            push(result[i]);
            i--;
        }

        return true;

    }

    /**
     * Finds the top-level beat to resume from if stack restoration fails.
     *
     * @param savedStack The saved stack data
     * @return The beat to resume from, or null if none can be found
     */
    function restoreBeatToResume(savedStack:Array<SaveDataScope>):NBeatDecl {

        var beat:NBeatDecl = null;

        if (savedStack.length > 0) {
            final savedScope = savedStack[0];
            beat = restoreBeat(savedScope.beat);

            // Ensure we get the top level beat from what has been resolved
            if (beat != null) {
                var parentBeat = beat;
                do {
                    parentBeat = lens.getFirstParentOfType(parentBeat, NBeatDecl);
                    if (parentBeat != null) {
                        beat = parentBeat;
                    }
                }
                while (parentBeat != null);
            }
        }

        return beat;

    }

    /**
     * Restores a node from a saved reference.
     *
     * @param savedNode The saved node reference
     * @param savedBeatId The ID of the beat in the saved data
     * @param beat The restored beat
     * @return The restored node, or null if it couldn't be found
     */
    function restoreNode(savedNode:SaveDataNode, savedBeatId:NodeId, beat:NBeatDecl):AstNode {

        // Resolve beat id offset, if any
        final sectionOffset = beat.id.section - savedBeatId.section;

        // Get node id
        var nodeId = NodeId.fromString(savedNode.id);

        // Check if that node id is actually the same as the beat id
        if (nodeId == savedBeatId) {
            // If so, return the resolved beat!
            return beat;
        }

        // From offset, find a the up to date target node id
        nodeId.section += sectionOffset;

        // Try resolve the node from that
        final node = lens.getNodeById(nodeId);
        if (node != null && node.type() == savedNode.type) {
            return cast node;
        }

        return null;

    }

    /**
     * Restores a beat from a saved reference.
     *
     * @param beatRef The saved beat reference
     * @return The restored beat, or null if it couldn't be found
     */
    function restoreBeat(beatRef:SaveDataBeat):NBeatDecl {

        return lens.findBeatByPathFromNode(beatRef.path, script);

    }

    /**
     * Restores a state from saved data.
     *
     * @param state The state to restore into, or null to create a new one
     * @param data The saved state data
     * @return The restored state
     */
    function restoreState(state:RuntimeState, data:SaveDataState):RuntimeState {

        final fields = restoreFields(state?.fields ?? null, data);

        if (state == null) {
            state = new RuntimeState(this, null, fields, null);
        }

        return state;

    }

    /**
     * Restores characters from saved data.
     *
     * @param data The saved character data
     */
    function restoreCharacters(data:Dynamic<SaveDataCharacter>):Void {

        for (name in Reflect.fields(data)) {
            final characterData:SaveDataCharacter = Reflect.field(data, name);
            if (topLevelCharacters.exists(name)) {
                restoreCharacter(topLevelCharacters.get(name), characterData);
            }
            else {
                // Character no longer exists in script, create it?
                final newCharacter = restoreCharacter(null, characterData);
                topLevelCharacters.set(name, newCharacter);
            }
        }

    }

    /**
     * Restores node states from saved data.
     *
     * @param data The saved node state data
     */
    function restoreNodeStates(data:Dynamic<SaveDataState>):Void {

        for (idStr in Reflect.fields(data)) {
            final id = NodeId.fromString(idStr);
            final stateData = Reflect.field(nodeStates, idStr);

            final nodeState = restoreState(null, stateData);
            nodeStates.set(id, nodeState);
        }

    }

    /**
     * Restores a character from saved data.
     *
     * @param character The character to restore into, or null to create a new one
     * @param data The saved character data
     * @return The restored character
     */
    function restoreCharacter(character:RuntimeCharacter, data:SaveDataCharacter):RuntimeCharacter {

        final fields = restoreFields(character?.fields ?? null, data);

        if (character == null) {
            character = new RuntimeCharacter(this, null, fields, null);
        }

        return character;

    }

    /**
     * Restores fields from saved data.
     *
     * @param target The target object to restore into, or null to create a new one
     * @param savedFields The saved field data
     * @return The object with restored fields
     */
    function restoreFields(target:Any, savedFields:SaveDataFields):Any {
        if (savedFields == null || savedFields.fields == null) return target;

        if (target == null) {
            target = Objects.createFields(this, savedFields.type);
        }

        final data = savedFields.fields;

        if (Objects.isFields(target)) {
            for (key in Reflect.fields(data)) {
                Objects.setField(this, target, key, restoreValue(Reflect.field(data, key)));
            }
        }
        else {
            // For plain objects
            for (field in Reflect.fields(data)) {
                Reflect.setField(target, field, restoreValue(Reflect.field(data, field)));
            }
        }

        return target;
    }

    /**
     * Restores a value from its saved form.
     * Handles recursive restoration of objects and arrays.
     *
     * @param value The saved value
     * @return The restored value
     */
    function restoreValue(value:Any):Any {
        if (value == null) {
            return null;
        }

        // Handle primitive types
        if (Std.isOfType(value, String) ||
            Std.isOfType(value, Float) ||
            Std.isOfType(value, Int) ||
            Std.isOfType(value, Bool)) {
            return value;
        }

        // Handle arrays
        if (Arrays.isArray(value)) {
            final len = Arrays.arrayLength(value);
            final arr = Arrays.createArray();
            for (i in 0...len) {
                Arrays.arrayPush(arr, restoreValue(Arrays.arrayGet(value, i)));
            }
            return arr;
        }

        return restoreFields(null, value);
    }

    /**
     * Gets a random number generator.
     * Creates one if it doesn't exist yet.
     *
     * @return A random number generator
     */
    var _random:Random = null;
    function random():Float {
        if (_random == null) {
            _random = new Random();
        }
        return _random.next();
    }

    /**
     * Initializes top-level functions available to the script.
     * This includes built-in functions and any user-provided functions.
     *
     * @param functions Optional map of additional functions to make available
     */
    function initializeTopLevelFunctions(functions:FunctionsMap) {

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

    function initializeTopLevelFunction(func:NFunctionDecl) {

        var list:Array<Dynamic> = [
          "carrot",
          1234,
          null,
          "potato",
        ];

        #if hscript
        if (func.name != null) {
            final codeToHscript = new CodeToHscript();
            try {
                final expr = codeToHscript.process(func.code);
                #if loreline_debug_functions
                final offsets = @:privateAccess codeToHscript.posOffsets;
                trace('\n'+func.code);
                trace('\n'+expr);
                trace(offsets.length + ' / ' + expr.uLength());
                trace(offsets.join(" "));
                var chars = [];
                var origChars = [];
                for (i in 0...expr.uLength()) {
                    chars.push(expr.uCharAt(i).replace("\n", " "));
                    origChars.push(func.code.uCharAt(i - offsets[i]).replace("\n", " "));
                }
                trace(origChars.join(" "));
                trace(chars.join(" "));
                #end
                final parser = new hscript.Parser();
                parser.allowJSON = true;
                parser.allowTypes = true;
                final ast = parser.parseString(expr);
                final interp = new HscriptInterp(this);
                final value:Dynamic = interp.execute(ast);
                topLevelFunctions.set(func.name, value);
            }
            catch (e:Any) {
                throw new RuntimeError('Failed to parse function code: $e', func.pos);
            }
        }
        else {
            throw new RuntimeError('Top level function must have a name', func.pos);
        }
        #else
        throw new RuntimeError('Hscript is required to parse this function', func.pos);
        #end

    }

    /**
     * Wraps a callback function to control whether it executes synchronously or asynchronously.
     * This is crucial for managing the execution flow of the script.
     *
     * @param cb The callback to wrap
     * @return An EvalNext object controlling the callback's execution
     */
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

    /**
     * Flushes all pending synchronous callbacks.
     * This ensures that all pending operations are completed before continuing.
     */
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

    /**
     * Pops the top scope from the execution stack.
     *
     * @return True if a scope was popped, false if the stack was already empty
     */
    function pop():Bool {

        if (stack.length > 0) {
            stack.pop();
            return true;
        }

        return false;

    }

    /**
     * Pushes a new scope onto the execution stack.
     *
     * @param scope The scope to push
     */
    function push(scope:RuntimeScope):Void {

        scope.id = nextScopeId++;
        stack.push(scope);

    }

    /**
     * Initializes a top-level state declaration.
     * Evaluates all fields and stores their values.
     *
     * @param state The state declaration to initialize
     * @throws RuntimeError If the state is marked as temporary
     */
    function initializeTopLevelState(state:NStateDecl) {

        // Top level states cannot be temporary
        if (state.temporary) {
            throw new RuntimeError('Top level temporary states are not allowed', state.pos);
        }

        // Evaluate state values
        for (field in state.fields) {
            final evaluated = evaluateExpression(field.value);
            Objects.setField(this, topLevelState.fields, field.name, evaluated);
            if (isOriginalScriptExpression(field.value)) {
                Objects.setField(this, topLevelState.originalFields, field.name, evaluated);
            }
        }

    }

    /**
     * Initializes a top-level beat declaration.
     * Registers the beat in the top-level beats map.
     *
     * @param beat The beat declaration to initialize
     * @throws RuntimeError If a beat with the same name already exists
     */
    function initializeTopLevelBeat(beat:NBeatDecl) {

        // Look for duplicate entries
        if (topLevelBeats.exists(beat.name)) {
            throw new RuntimeError('Duplicate top level beat: ${beat.name}', beat.pos);
        }

        // Create new beat entry in mapping
        topLevelBeats.set(beat.name, beat);

    }

    /**
     * Initializes a top-level character declaration.
     * Creates a new character state and evaluates all fields.
     *
     * @param character The character declaration to initialize
     * @throws RuntimeError If a character with the same name already exists
     */
    function initializeTopLevelCharacter(character:NCharacterDecl) {

        // Look for duplicate entries
        if (topLevelCharacters.exists(character.name)) {
            throw new RuntimeError('Duplicate top level character: ${character.name}', character.pos);
        }

        // Create new character state
        final characterState = new RuntimeCharacter(this, character, null, null);
        topLevelCharacters.set(character.name, characterState);

        // Evaluate character values
        for (field in character.fields) {
            final evaluated = evaluateExpression(field.value);
            Objects.setField(this, characterState.fields, field.name, evaluated);
            if (isOriginalScriptExpression(field.value)) {
                Objects.setField(this, characterState.originalFields, field.name, evaluated);
            }
        }

    }

    /**
     * Initializes a state declaration within a scope.
     * Evaluates all fields and stores their values.
     *
     * @param state The state declaration to initialize
     * @param scope The scope in which to initialize the state
     */
    function initializeState(state:NStateDecl, scope:RuntimeScope) {

        var runtimeState:RuntimeState = null;
        if (state.temporary) {
            if (scope.state == null) {
                scope.state = new RuntimeState(this, state, null, null);
            }
            runtimeState = scope.state;
        }
        else {
            runtimeState = nodeStates.get(scope.node.id);
            if (runtimeState == null) {
                runtimeState = new RuntimeState(this, state, null, null);
                nodeStates.set(scope.node.id, runtimeState);
            }
        }

        // Evaluate state values
        for (field in state.fields) {
            final evaluated = evaluateExpression(field.value);
            Objects.setField(this, runtimeState.fields, field.name, evaluated);
            if (!state.temporary && isOriginalScriptExpression(field.value)) {
                Objects.setField(this, runtimeState.originalFields, field.name, evaluated);
            }
        }

    }

    /**
     * Finishes script execution and calls the finish handler.
     */
    function finish():Void {

        finishTrigger = null;

        if (handleFinish != null) {
            handleFinish(this);
        }

    }

    /**
     * Transitions to a new beat, clearing the current execution stack.
     *
     * @param beat The beat to transition to
     */
    function transitionToBeat(beat:NBeatDecl) {

        // Clear stack and temporary states
        while (pop()) {};

        // Reset scope id
        nextScopeId = 1;

        // Reset insertion id
        nextInsertionId = 1;

        // Run beat
        final done = wrapNext(finish);

        // We now consider that finishing this beat
        // execution chain is the finish trigger
        finishTrigger = done;

        evalBeatRun(beat, done.cb);
        done.sync = false;

    }

    /**
     * Evaluates a node, dispatching to the appropriate handler based on node type.
     *
     * @param node The node to evaluate
     * @param next Callback to call when evaluation completes
     * @throws RuntimeError If the node type is not supported
     */
    function evalNode(node:AstNode, next:()->Void) {

        switch Type.getClass(node) {

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

            // TODO NInsertion

            case _:
                throw new RuntimeError('Unsupported node type: ${Type.getClassName(Type.getClass(node))}', node.pos);
        }

    }

    /**
     * Evaluates a beat declaration.
     * Adds the beat to the current scope so it can be referenced by other nodes.
     *
     * @param beat The beat declaration to evaluate
     * @param next Callback to call when evaluation completes
     * @throws RuntimeError If a beat with the same name already exists in the current scope
     */
    function evalBeatDecl(beat:NBeatDecl, next:()->Void) {

        // Add beat to current scope.
        // It will be available as long as we don't leave that scope

        if (currentScope.beats == null) {
            currentScope.beats = [];
        }
        else if (currentScope.beatByName(beat.name) != null) {
            throw new RuntimeError('Duplicate beat with name: ${beat.name}', beat.pos);
        }

        currentScope.beats.push(beat);

        next();

    }

    /**
     * Evaluates a node body by creating a new scope and executing each node in sequence.
     *
     * @param beat The parent beat
     * @param node The node containing the body
     * @param body The body to execute
     * @param insertion If any, the insertion related to this evaluation
     * @param next Callback to call when execution completes
     */
    function evalNodeBody(beat:NBeatDecl, node:AstNode, body:Array<AstNode>, ?insertion:RuntimeInsertion, next:()->Void) {

        // Push new scope
        push({
            beat: beat,
            node: node,
            insertion: insertion
        });

        // Then iterate through each child node in the body
        var index = 0;
        var moveNext:()->Void = null;
        final currentInsertion = this.currentInsertion;
        moveNext = () -> {

            if (currentInsertion?.options != null) {
                // At each iteration, check if we are within an insertion with completed choice options.
                // If that's the case, we should pause this stack execution for now and return
                pop();
                next();

            }
            else {
                // Check if we still have a node to evaluate
                if (index < body.length) {

                    // Yes, do it
                    final childNode = body[index];
                    currentScope.head = childNode;
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

        }

        // Start evaluating the body
        moveNext();

    }

    /**
     * Evaluates a beat by executing its body.
     *
     * @param beat The beat to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalBeatRun(beat:NBeatDecl, next:()->Void) {

        evalNodeBody(beat, beat, beat.body, next);

    }

    /**
     * Evaluates a state declaration.
     * Initializes the state fields with their evaluated values.
     *
     * @param state The state declaration to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalStateDecl(state:NStateDecl, next:()->Void) {

        // This will initialize the state if it's temporary
        // or the first time we encounter it, if it is a persistent one
        initializeState(
            state,
            currentScope
        );

        next();

    }

    /**
     * Evaluates a text statement by evaluating the content and calling the dialogue handler.
     *
     * @param text The text statement to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalText(text:NTextStatement, next:()->Void) {

        // First evaluate the content from the given text
        final content = evaluateString(text.content);

        // Then call the user-defined dialogue handler.
        // The execution will be "paused" until the callback
        // is called, either synchronously or asynchronously
        handleDialogue(this, null, content.text, content.tags, next);

    }

    /**
     * Evaluates a dialogue statement by evaluating the content and calling the dialogue handler.
     *
     * @param dialogue The dialogue statement to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalDialogue(dialogue:NDialogueStatement, next:()->Void) {

        // First evaluate the content from the given dialogue
        final content = evaluateString(dialogue.content);

        // Then call the user-defined dialogue handler.
        // The execution will be "paused" until the callback
        // is called, either synchronously or asynchronously
        handleDialogue(this, dialogue.character, content.text, content.tags, next);

    }

    /**
     * Evaluates a choice statement by evaluating the options and calling the choice handler.
     *
     * @param choice The choice statement to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalChoice(choice:NChoiceStatement, next:()->Void) {

        final options:Array<ChoiceOption> = [];
        final optionsDone = wrapNext(() -> {
            // Step 2

            // If we are within an insertion waiting for a choice block,
            // then we reached that choice block and should collect options
            final currentInsertion = this.currentInsertion;
            if (currentInsertion != null && currentInsertion.options == null) {
                // Copy the current stack so that we can restore it later
                currentInsertion.stack = [].concat(stack);

                // Fill in options
                currentInsertion.options = options;

                // No need to continue here, we won't display that choice
                // because instead we are collection the options for a parent one.
                next();
                return;
            }

            // Then call the user-defined choice handler.
            // The execution will be "paused" until the callback
            // is called, either synchronously or asynchronously
            var index:Int = -1;
            var choiceCallback = wrapNext(() -> {
                if (index >= 0 && index < options.length) {
                    // Evaluate the chosen option
                    final option = options[index];
                    if (option.insertion != null) {
                        final scopeLevel = stack.length;
                        while (stack.length > 0) stack.pop();
                        for (scope in option.insertion.stack) {

                            // Need to remove the insertion data now, as we are just back
                            // to normal execution flow now!
                            if (scope.insertion == option.insertion) {
                                scope.insertion = null;
                            }

                            stack.push(scope);
                        }
                        final lastScope = stack[stack.length-1];
                        push({
                            beat: lastScope.beat,
                            node: cast lens.getParentNode(option.node),
                            head: option.node
                        });
                        resumeFromLevel(scopeLevel, next);
                    }
                    else {
                        evalChoiceOption(option.node, next);
                    }
                }
                else {
                    // Choice is invalid. In that situation, we suppose
                    // the choice was cancelable and just continue evaluation
                    next();
                }
            });
            handleChoice(this, options, function(index_:Int) {
                index = index_;
                choiceCallback.cb();
            });
            choiceCallback.sync = false;

        });

        // Step 1
        evalChoiceOptionsAndInsertions(currentScope.beat, choice, options, optionsDone.cb);
        optionsDone.sync = false;

    }

    function evalChoiceOptionsAndInsertions(beat:NBeatDecl, choice:NChoiceStatement, result:Array<ChoiceOption>, next:()->Void) {

        // Get options
        final options = choice.options;

        // Then iterate through each child node in the body
        var index = 0;
        var moveNext:()->Void = null;
        var insertion:RuntimeInsertion = null;
        moveNext = () -> {

            // Look for collection options in previous step (from an insertion)
            if (insertion != null && insertion.options != null) {
                for (i in 0...insertion.options.length) {
                    final opt = insertion.options[i];
                    result.push(opt);
                }
                insertion = null;
            }

            // Check if we still have an option to evaluate
            if (index < options.length) {

                // Yes, do it
                final option = options[index];
                index++;
                final enabled = option.condition == null || evaluateCondition(option.condition);
                if (option.text != null) {
                    final done = wrapNext(moveNext);
                    final content = evaluateString(option.text);
                    result.push({
                        text: content.text,
                        tags: content.tags,
                        enabled: enabled,
                        node: option,
                        insertion: currentInsertion
                    });
                    done.cb();
                    done.sync = false;
                }
                else if (option.insertion != null) {
                    final done = wrapNext(moveNext);
                    insertion = new RuntimeInsertion(nextInsertionId, option.insertion);
                    evalInsertion(insertion, done.cb);
                    done.sync = false;
                }
                else {
                    throw new RuntimeError('Invalid choice option', option.pos);
                }

            }
            else {

                // We are done, finish that evaluation
                next();
            }

        }

        // Start evaluating the body
        moveNext();

    }

    function evalInsertion(insertion:RuntimeInsertion, next:()->Void) {

        final beatName = insertion.origin.target;
        var resolvedBeat:NBeatDecl = null;

        // Look for matching beat in scopes recursively
        var i = stack.length - 1;
        while (i >= 0) {
            final scope = stack[i];
            final beatInScope = scope.beatByName(beatName);
            if (beatInScope != null) {
                resolvedBeat = beatInScope;
                break;
            }
            i--;
        }

        // If no beat was found, look at top level beats
        if (resolvedBeat == null) {
            if (topLevelBeats.exists(beatName)) {
                resolvedBeat = topLevelBeats.get(beatName);
            }
        }

        // If still nothing found, not good...
        if (resolvedBeat == null) {
            throw new RuntimeError('Beat $beatName not found', script.pos);
        }

        evalNodeBody(resolvedBeat, resolvedBeat, resolvedBeat.body, insertion, next);

    }

    /**
     * Evaluates a choice option by executing its body.
     *
     * @param option The choice option to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalChoiceOption(option:NChoiceOption, next:()->Void) {

        // Evaluate child nodes of this choice option.
        // Child nodes will be evaluated in a child scope associated
        // with this options node
        evalNodeBody(currentScope.beat, option, option.body, next);

    }

    /**
     * Evaluates an if statement by evaluating the condition and executing the appropriate branch.
     *
     * @param ifStmt The if statement to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalIf(ifStmt:NIfStatement, next:()->Void) {

        final isTrue = evaluateCondition(ifStmt.condition);

        final branch = isTrue ? ifStmt.thenBranch : ifStmt.elseBranch;

        if (branch != null && branch.body.length > 0) {
            evalNodeBody(currentScope.beat, branch, branch.body, next);
        }
        else {
            next();
        }

    }

    /**
     * Evaluates an assignment by resolving the target, evaluating the value, and applying the assignment.
     *
     * @param assign The assignment to evaluate
     * @param next Callback to call when evaluation completes
     * @throws RuntimeError If the assignment operator is invalid
     */
    function evalAssignment(assign:NAssign, next:()->Void) {

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

    /**
     * Determines whether an expression is an "original script expression" - meaning it only
     * depends on values directly present in the script and not on runtime state.
     *
     * Original script expressions can be evaluated at parse time and safely stored as
     * default values, as they don't depend on dynamic context like variables or
     * function calls that might change during runtime.
     *
     * @param expr The expression to check
     * @return True if the expression only depends on literal values in the script
     */
    function isOriginalScriptExpression(expr:NExpr):Bool {

        // Check expression type
        switch Type.getClass(expr) {
            // Literals are pure expressions
            case NLiteral:
                final lit:NLiteral = cast expr;
                switch (lit.literalType) {
                    // Simple literals are always pure
                    case Number, Boolean, Null:
                        return true;

                    // For arrays, check each element recursively
                    case Array:
                        final arr:Array<Dynamic> = cast lit.value;
                        for (elem in arr) {
                            if (elem is NExpr && !isOriginalScriptExpression(cast elem)) {
                                return false;
                            }
                        }
                        return true;

                    // For objects, check each field value recursively
                    case Object(_):
                        final fields:Array<NObjectField> = cast lit.value;
                        for (field in fields) {
                            if (!isOriginalScriptExpression(field.value)) {
                                return false;
                            }
                        }
                        return true;
                }

            // String literals are pure if they don't contain interpolations
            case NStringLiteral:
                final str:NStringLiteral = cast expr;
                for (part in str.parts) {
                    switch (part.partType) {
                        case Raw(_):
                            // Raw text is fine
                            continue;
                        case Expr(_):
                            // Interpolated expressions make this impure
                            return false;
                        case Tag(_, content):
                            // Tags need to be checked recursively
                            if (!isOriginalScriptExpression(content)) {
                                return false;
                            }
                    }
                }
                return true;

            // Binary operations are pure if both operands are pure
            case NBinary:
                final bin:NBinary = cast expr;
                return isOriginalScriptExpression(bin.left) && isOriginalScriptExpression(bin.right);

            // Unary operations are pure if the operand is pure
            case NUnary:
                final un:NUnary = cast expr;
                return isOriginalScriptExpression(un.operand);

            // All the following expression types depend on external state or functions
            case NAccess, NArrayAccess, NCall:
                return false;
        }

        // Any other expression type is considered impure
        return false;

    }

    /**
     * Determines if a node is a beat call.
     * A beat call is a special function call that executes a beat instead of a normal function.
     *
     * @param node The node to check
     * @param scopeLevel Optional scope level to search in (defaults to current scope)
     * @return True if the node is a beat call
     */
    function isBeatCall(node:AstNode, scopeLevel:Int = -1):Bool {

        if (node is NCall) {
            return resolveBeatFromCall(cast node, scopeLevel) != null;
        }

        return false;

    }

    /**
     * Resolves a call node to a beat declaration if the call references a beat.
     * This allows handling beat calls differently from regular function calls.
     *
     * @param call The call node to resolve
     * @param scopeLevel Optional scope level to search in (defaults to current scope)
     * @return The beat declaration if found, null otherwise
     */
    function resolveBeatFromCall(call:NCall, scopeLevel:Int = -1):NBeatDecl {

        // If target is a simple identifier, it might be a nested beat call
        if (call.target is NAccess) {
            final access:NAccess = cast call.target;
            if (access.target == null) {
                // Look for matching beat in current scope and parent scopes
                var beatName = access.name;
                var resolvedBeat:NBeatDecl = null;

                // Search through scopes from innermost to outermost
                var i = scopeLevel == -1 ? stack.length - 1 : scopeLevel;
                while (i >= 0) {
                    final scope = stack[i];
                    final beatInScope = scope.beatByName(beatName);
                    if (beatInScope != null) {
                        resolvedBeat = beatInScope;
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
                    return resolvedBeat;
                }
            }
        }

        return null;

    }

    /**
     * Evaluates a call node.
     * If the call references a beat, it executes the beat.
     * Otherwise, it evaluates it as a regular function call.
     *
     * @param call The call node to evaluate
     * @param next Callback to call when evaluation completes
     */
    function evalCall(call:NCall, next:()->Void) {

        final resolvedBeat = resolveBeatFromCall(call);

        // If beat found, evaluate it
        if (resolvedBeat != null) {
            evalBeatRun(resolvedBeat, next);
            return;
        }

        // In other situations, try a regular function call
        evaluateFunctionCall(call, next);

    }

    /**
     * Evaluates a transition node.
     * Transitions cause execution to jump to a different beat,
     * clearing the current execution stack.
     *
     * @param transition The transition node to evaluate
     */
    function evalTransition(transition:NTransition) {

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
            final beatInScope = scope.beatByName(beatName);
            if (beatInScope != null) {
                resolvedBeat = beatInScope;
                break;
            }
            i--;
        }

        // If no beat was found, look at top level beats
        if (resolvedBeat == null) {
            if (topLevelBeats.exists(beatName)) {
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

    /**
     * Evaluates a string literal into text with tags.
     * This handles interpolation and tag processing.
     *
     * @param str The string literal to evaluate
     * @return Object containing the evaluated text and any tags
     */
    function evaluateString(str:NStringLiteral):{text:String, tags:Array<TextTag>} {
        final buf = new loreline.Utf8.Utf8Buf();
        final tags:Array<TextTag> = [];
        var offset = 0;

        var keepWhitespace = (str.quotes != Unquoted);
        var keepIndents = (str.quotes != Unquoted);
        var keepComments = (str.quotes != Unquoted);

        for (i in 0...str.parts.length) {
            final part = str.parts[i];

            switch (part.partType) {
                case Raw(text):
                    if (!keepWhitespace) {
                        text = text.ltrim();
                    }
                    if (!keepComments) {
                        text = stripStringComments(text);
                    }
                    if (!keepIndents) {
                        text = stripStringIndent(text);
                    }
                    final len = text.uLength();
                    if (len > 0) keepWhitespace = true;
                    var prevIsDollar:Bool = false;
                    var escaped:Bool = false;
                    for (i in 0...len) {
                        final c = text.uCharCodeAt(i);
                        if (escaped) {
                            if (c == "n".code) {
                                buf.addChar("\n".code);
                            }
                            else if (c == "r".code) {
                                buf.addChar("\r".code);
                            }
                            else if (c == "t".code) {
                                buf.addChar("\t".code);
                            }
                            else {
                                buf.addChar(c);
                            }
                            escaped = false;
                            prevIsDollar = false;
                        }
                        else if (c == "\\".code) {
                            escaped = true;
                            prevIsDollar = false;
                        }
                        else if (c == "$".code) {
                            if (prevIsDollar) {
                                buf.addChar(c);
                                prevIsDollar = false;
                            }
                            else {
                                prevIsDollar = true;
                            }
                        }
                        else {
                            buf.addChar(c);
                        }
                    }
                    offset += len;

                case Expr(expr):
                    keepWhitespace = true;
                    if (expr is NAccess) {
                        // When providing a character object,
                        // implicitly read the character's `name` field
                        final access:NAccess = cast expr;
                        final resolved = resolveAccess(access, access.target, access.name);
                        switch resolved {
                            case CharacterAccess(_, name):
                                final characterFields = evaluateExpression(expr);
                                final value = Objects.getField(this, characterFields, 'name') ?? name;
                                final text = valueToString(value);
                                offset += text.uLength();
                                buf.add(text);

                            case _:
                                final value = evaluateExpression(expr);
                                final text = valueToString(value);
                                offset += text.uLength();
                                buf.add(text);
                        }
                    }
                    else {
                        final value = evaluateExpression(expr);
                        final text = valueToString(value);
                        offset += text.uLength();
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

    function stripStringIndent(content:String):String {

        var minIndent:Int = -1;
        var currentIndent:Int = -1;

        final len:Int = content.uLength();
        var i:Int = 0;

        while (content.uCharCodeAt(i) == " ".code && i < len) {
            i++;
        }
        if (i > 0) {
            minIndent = i;
        }

        while (i < len) {
            final c = content.uCharCodeAt(i);
            if (c == "\n".code) {
                currentIndent = 0;
            }
            else if (currentIndent >= 0 && c == " ".code) {
                currentIndent++;
            }
            else if (currentIndent >= 0) {
                if (minIndent == -1 || minIndent > currentIndent) {
                    minIndent = currentIndent;
                }
                currentIndent = -1;
            }
            i++;
        }

        if (minIndent > 0) {
            final indentBuf = new Utf8Buf();
            for (_ in 0...minIndent) {
                indentBuf.addChar(" ".code);
            }
            content = content.replace("\n" + indentBuf.toString(), "\n");
        }

        return content;

    }

    function stripStringComments(content:String):String {

        final result = new Utf8Buf();
        final len:Int = content.uLength();
        var i:Int = 0;

        while (i < len) {
            final c = content.uCharCodeAt(i);

            // Check for line comment
            if (c == "/".code && i + 1 < len && content.uCharCodeAt(i + 1) == "/".code) {
                // Skip to the end of line or end of string
                while (i < len && content.uCharCodeAt(i) != "\n".code) {
                    i++;
                }
                continue;
            }

            // Check for multiline comment
            if (c == "/".code && i + 1 < len && content.uCharCodeAt(i + 1) == "*".code) {
                // Remember if we had a space before the comment
                final hadSpaceBefore = (i > 0 && content.uCharCodeAt(i - 1) == " ".code);

                // Skip the opening /*
                i += 2;

                // Find the end of multiline comment
                while (i + 1 < len && !(content.uCharCodeAt(i) == "*".code && content.uCharCodeAt(i + 1) == "/".code)) {
                    i++;
                }

                // Skip the closing */
                i += 2;

                // Check if there's a space after the comment
                final hasSpaceAfter = (i < len && content.uCharCodeAt(i) == " ".code);

                // If we had a space before and there's a space after, skip the space after
                // to avoid having double spaces
                if (hadSpaceBefore && hasSpaceAfter) {
                    i++;
                }

                // Add a single space in place of the comment if there wasn't one before
                // and there isn't one after
                if (!hadSpaceBefore && !hasSpaceAfter && i < len) {
                    result.addChar(" ".code);
                }

                continue;
            }

            // Normal character, add to result
            result.addChar(c);
            i++;
        }

        return result.toString();

    }

    /**
     * Evaluates a condition expression for an if statement or choice option.
     * Converts the result to a boolean according to Loreline's rules.
     *
     * @param expr The condition expression to evaluate
     * @return True if the condition evaluates to a truthy value
     */
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

    /**
     * Evaluates a function call in an expression context.
     * If next is provided, the function may execute asynchronously.
     * If next is null, the function must execute synchronously.
     *
     * @param call The function call node to evaluate
     * @param next Optional callback for asynchronous execution
     * @return The result of the function call
     * @throws RuntimeError if an async function is called in an expression context without a next callback
     */
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
                        try {
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
                        catch (e:Dynamic) {
                            #if hscript
                            if (e is hscript.Expr.Error) {
                                final hscriptErr:hscript.Expr.Error = cast e;
                                trace('${hscriptErr.pmin}-${hscriptErr.pmax} ${hscriptErr.e}');
                            }
                            #end
                            trace(Type.getClassName(Type.getClass(e)) + ' -> ' + e);
                            return null;
                        }
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

    /**
     * Evaluates an array literal to a runtime array.
     * Each element is evaluated recursively.
     *
     * @param expr The array literal expression to evaluate
     * @return The resulting array
     */
    function evaluateArrayLiteral(expr:Array<Dynamic>):Any {

        #if (cs && loreline_use_cs_types)
        untyped __cs__('System.Collections.Generic.List<object> result = new System.Collections.Generic.List<object>({0})', expr.length);
        for (elem in expr) {
            final val = evaluateExpression(elem);
            untyped __cs__('result.Add({0})', val);
        }
        return untyped __cs__('result');
        #else
        return [for (elem in expr) evaluateExpression(elem)];
        #end

    }

    /**
     * Evaluates an object literal to a runtime object.
     * Each field value is evaluated recursively.
     *
     * @param expr The object literal expression to evaluate
     * @return The resulting object
     */
    function evaluateObjectLiteral(expr:Array<NObjectField>):Any {

        #if (cs && loreline_use_cs_types)
        untyped __cs__('System.Collections.Generic.Dictionary<string,object> result = new System.Collections.Generic.Dictionary<string,object>()', expr.length);
        for (field in expr) {
            final val = evaluateExpression(field.value);
            untyped __cs__('result[{0}] = {1}', field.name, val);
        }
        return untyped __cs__('result');
        #else
        final obj = new Map<String, Any>();
        for (field in expr) {
            obj.set(field.name, evaluateExpression(field.value));
        }
        return obj;
        #end

    }

    /**
     * Evaluates an expression to its runtime value.
     * This is the core expression evaluation function that handles all expression types.
     *
     * @param expr The expression to evaluate
     * @return The runtime value of the expression
     * @throws RuntimeError if the expression can't be evaluated
     */
    function evaluateExpression(expr:NExpr):Any {

        return switch (Type.getClass(expr)) {

            case NLiteral:
                final lit:NLiteral = cast expr;
                switch (lit.literalType) {
                    case Number, Boolean, Null: lit.value;
                    case Array:
                        evaluateArrayLiteral(cast lit.value);
                    case Object(_):
                        evaluateObjectLiteral(cast lit.value);
                }

            case NStringLiteral:
                final str:NStringLiteral = cast expr;
                if (str.parts.length == 1 && str.quotes == Unquoted) {
                    switch str.parts[0].partType {
                        case Expr(expr):
                            // The literal is actually just an unquoted $... interpolation,
                            // so we can treat it as a normal expression in this context.
                            evaluateExpression(expr);
                        case _:
                            evaluateString(str).text;
                    }
                }
                else {
                    evaluateString(str).text;
                }

            case NAccess:
                final access:NAccess = cast expr;
                final resolved = resolveAccess(access, access.target, access.name);
                readAccess(resolved);

            case NArrayAccess:
                final arrAccess:NArrayAccess = cast expr;
                final target = evaluateExpression(arrAccess.target);
                final index = evaluateExpression(arrAccess.index);

                if (Arrays.isArray(target) && (index is Int || index is Float)) {
                    final i:Int = Std.int(index);
                    if (i < 0 || i >= Arrays.arrayLength(target)) {
                        throw new RuntimeError('Array index out of bounds: $i', arrAccess.pos);
                    }
                    else {
                        Arrays.arrayGet(target, i);
                    }
                }
                else if (index is String) {
                    Objects.getField(this, target, index);
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

    /**
     * Reads the value from a runtime access.
     * This handles field access, array access, character access, and function access.
     *
     * @param access The runtime access to read
     * @return The value at the access location
     * @throws RuntimeError if the access is invalid
     */
    function readAccess(access:RuntimeAccess):Any {

        return switch access {

            case FieldAccess(pos, obj, name):
                Objects.getField(this, obj, name);

            case ArrayAccess(pos, array, index):
                Arrays.arrayGet(array, index);

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

    /**
     * Writes a value to a runtime access location.
     * This handles field access and array access.
     * Character and function access cannot be written to.
     *
     * @param access The runtime access to write to
     * @param value The value to write
     * @throws RuntimeError if the access is invalid or not writable
     */
    function writeAccess(access:RuntimeAccess, value:Any):Void {

        switch access {
            case FieldAccess(pos, obj, name):
                Objects.setField(this, obj, name, value);

            case ArrayAccess(pos, array, index):
                Arrays.arraySet(array, index, value);

            case CharacterAccess(pos, name):
                throw new RuntimeError('Cannot overwrite character: $name', pos);

            case FunctionAccess(pos, name):
                throw new RuntimeError('Cannot overwrite function: $name', pos);

        }

    }

    /**
     * Resolves an assignment target to a runtime access.
     * This is used to determine where to write a value in an assignment.
     *
     * @param target The target expression to resolve
     * @return The runtime access to write to
     * @throws RuntimeError if the target is not assignable
     */
    function resolveAssignmentTarget(target:NExpr):RuntimeAccess {

        return switch (Type.getClass(target)) {

            case NAccess:
                final access:NAccess = cast target;
                resolveAccess(access, access.target, access.name);

            case NArrayAccess:
                final arrAccess:NArrayAccess = cast target;
                final target = evaluateExpression(arrAccess.target);
                final index = evaluateExpression(arrAccess.index);

                if (Arrays.isArray(target) && (index is Int || index is Float)) {
                    final i:Int = Std.int(index);
                    ArrayAccess(arrAccess.pos, target, i);
                }
                else {
                    throw new RuntimeError('Invalid array access target', arrAccess.pos);
                }

            case _:
                throw new RuntimeError('Invalid assignment target', target.pos);
        }

    }

    /**
     * Resolves an access expression to a runtime access.
     * This handles finding variables, character fields, and functions in the appropriate scopes.
     *
     * @param access The access expression to resolve
     * @param target Optional target object for field access
     * @param name The name to access
     * @return The resolved runtime access
     * @throws RuntimeError if the access cannot be resolved
     */
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
                if (Objects.fieldExists(this, scope.state.fields, name)) {
                    return FieldAccess(
                        access?.pos ?? currentScope?.node?.pos ?? script.pos,
                        scope.state.fields,
                        name
                    );
                }
            }

            if (scope.node != null) {

                // Check node state
                final stateInNode = nodeStates.get(scope.node.id);
                if (stateInNode != null) {
                    if (Objects.fieldExists(this, stateInNode.fields, name)) {
                        return FieldAccess(
                            access?.pos ?? currentScope?.node?.pos ?? script.pos,
                            stateInNode.fields,
                            name
                        );
                    }
                }
            }

            i--;
        }

        // Look for state fields
        if (Objects.fieldExists(this, topLevelState.fields, name)) {
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

        if (!strictAccess) {
            // When variable is not resolved, write to top level state
            return FieldAccess(
                access?.pos ?? currentScope?.node?.pos ?? script.pos,
                topLevelState.fields,
                name
            );
        }

        throw new RuntimeError('Undefined variable: $name', access?.pos ?? currentScope?.node?.pos ?? script.pos);

    }

    /**
     * Helper for getting human-readable type names in errors
     *
     * @param t The type to get a name for
     * @return A human-readable name for the type
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

    /**
     * Performs a binary operation on two values.
     * Handles arithmetic, comparison, and logical operations.
     *
     * @param op The operator to apply
     * @param left The left operand
     * @param right The right operand
     * @param pos The source position for error reporting
     * @return The result of the operation
     * @throws RuntimeError if the operation is invalid for the given types
     */
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

            case OpAnd(_) | OpOr(_):
                switch [leftType, rightType] {
                    case [TBool, TBool]:
                        switch op {
                            case OpAnd(_): left && right;
                            case OpOr(_): left || right;
                            case _: throw "Unreachable";
                        }
                    case _:
                        throw new RuntimeError('Cannot perform logical operation on ${getTypeName(leftType)} and ${getTypeName(rightType)}', pos ?? currentScope?.node?.pos ?? script.pos);
                }

            case _:
                throw new RuntimeError('Invalid operation: $op', pos ?? currentScope?.node?.pos ?? script.pos);
        }
    }

    /**
     * Converts a value to its string representation.
     * Used for string interpolation and output.
     *
     * @param value The value to convert to a string
     * @return The string representation of the value
     */
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