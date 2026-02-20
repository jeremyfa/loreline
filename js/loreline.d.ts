
/**
 * Handler function for loading file imports
 * @param path The path of the file to load
 * @param callback Function to call with the loaded file content
 */
export type ImportsFileHandler = (path: string, callback: (data: string) => void) => void;

/**
 * Handler function for import errors
 * @param error The error that occurred during import
 */
export type ImportsErrorHandler = (error: Error) => void;

/**
 * Tokens type
 */
export type Tokens = Array<any>;

/**
 * Opaque type for saved game data.
 */
export type SaveData = any;

/**
 * Opaque type for a translations map.
 * Obtained from `Loreline.extractTranslations()` and passed to `InterpreterOptions.translations`.
 */
export type Translations = any;

/**
 * Represents an error in the Loreline system.
 */
export interface Error {
    /**
     * The error message describing what went wrong.
     */
    message: string;

    /**
     * The position in the source code where the error occurred.
     */
    pos: Position;

    /**
     * The call stack of this error
     */
    stack: Array<any>;

    /**
     * Converts the error to a human-readable string.
     * @return Formatted error message with position
     */
    toString(): string;
}

/**
 * Represents a position within source code, tracking line number, column, and offset information.
 * Used throughout the compiler to pinpoint locations of tokens, nodes, and error messages.
 */
export interface Position {
    /**
     * The line number in the source code, starting from 1.
     */
    line: number;

    /**
     * The column number in the source code, starting from 1.
     * Represents the character position within the current line.
     */
    column: number;

    /**
     * The absolute character offset from the start of the source code.
     * Used for precise positioning and span calculations.
     */
    offset: number;

    /**
     * The length of the source text span this position represents.
     * A value of 0 indicates a point position rather than a span.
     */
    length: number;

    /**
     * Converts the position to a human-readable string.
     * @return Formatted position string
     */
    toString(): string;
}

/**
 * Represents a choice option presented to the user.
 */
export interface ChoiceOption {
    /**
     * The text of the choice option.
     */
    text: string;

    /**
     * Any tags associated with the choice text.
     */
    tags: Array<TextTag>;

    /**
     * Whether this choice option is currently enabled.
     */
    enabled: boolean;
}

/**
 * Represents a tag in text content, which can be used for styling or other purposes.
 */
export interface TextTag {
    /**
     * Whether this is a closing tag.
     */
    closing: boolean;

    /**
     * The value or name of the tag.
     */
    value: string;

    /**
     * The offset in the text where this tag appears.
     */
    offset: number;
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
export type DialogueHandler = (interpreter: Interpreter, character: string | null, text: string, tags: Array<TextTag>, callback: () => void) => void;

/**
 * Handler type for choice presentation with callback.
 * This is called when the script needs to present choices to the user.
 *
 * @param interpreter The interpreter instance
 * @param options The available choice options
 * @param callback Function to call with the index of the selected choice
 */
export type ChoiceHandler = (interpreter: Interpreter, options: Array<ChoiceOption>, callback: (index: number) => void) => void;

/**
 * Handler type to be called when the execution finishes.
 *
 * @param interpreter The interpreter instance
 */
export type FinishHandler = (interpreter: Interpreter) => void;

/**
 * Options used to configure the Loreline interpreter behavior
 */
export interface InterpreterOptions {
    /**
     * Optional map of additional functions to make available to the script
     */
    functions?: FunctionsMap;

    /**
     * Tells whether access is strict or not. If set to true,
     * trying to read or write an undefined variable will throw an error.
     */
    strictAccess?: boolean;

    /**
     * A custom instantiator to create fields objects.
     */
    customCreateFields?: (interpreter: Interpreter, type: string, node: Node) => any;

    /**
     * Optional translations map for localization.
     * Built from a parsed translation file using `Loreline.extractTranslations()`.
     */
    translations?: Translations;
}

/**
 * Map of function names to their implementations
 */
export type FunctionsMap = Record<string, Function>;

/**
 * The main public API for Loreline runtime.
 * Provides easy access to the core functionality for parsing and running Loreline scripts.
 */
export class Loreline {
    /**
     * Parses the given text input and creates an executable `Script` instance from it.
     *
     * This is the first step in working with a Loreline script. The returned
     * `Script` object can then be passed to methods `play()` or `resume()`.
     *
     * @param input The Loreline script content as a string (`.lor` format)
     * @param filePath Optional file path of the input being parsed. If provided, requires `handleFile` as well.
     * @param handleFile Optional file handler to read imports. If that handler is asynchronous, then `parse()` will return null and `callback` argument should be used
     * @param callback If provided, will be called with the resulting script as argument. Mostly useful when reading file imports asynchronously
     * @returns The parsed script as an AST `Script` instance (if loaded synchronously)
     * @throws If the script contains syntax errors or other parsing issues
     */
    static parse(input: string, filePath?: string, handleFile?: ImportsFileHandler, callback?: (script: Script) => void): Script | null;

    /**
     * Starts playing a Loreline script from the beginning or a specific beat.
     *
     * This function takes care of initializing the interpreter and starting execution
     * immediately. You'll need to provide handlers for dialogues, choices, and
     * script completion.
     *
     * @param script The parsed script (result from `parse()`)
     * @param handleDialogue Function called when dialogue text should be displayed
     * @param handleChoice Function called when player needs to make a choice
     * @param handleFinish Function called when script execution completes
     * @param beatName Optional name of a specific beat to start from (defaults to first beat)
     * @param options Additional options
     * @returns The interpreter instance that is running the script
     */
    static play(
        script: Script,
        handleDialogue: DialogueHandler,
        handleChoice: ChoiceHandler,
        handleFinish: FinishHandler,
        beatName?: string,
        options?: InterpreterOptions
    ): Interpreter;

    /**
     * Resumes a previously saved Loreline script from its saved state.
     *
     * This allows you to continue a story from the exact point where it was saved,
     * restoring all state variables, choices, and player progress.
     *
     * @param script The parsed script (result from `parse()`)
     * @param handleDialogue Function called when dialogue text should be displayed
     * @param handleChoice Function called when player needs to make a choice
     * @param handleFinish Function called when script execution completes
     * @param saveData The saved game data (typically from `interpreter.save()`)
     * @param beatName Optional beat name to override where to resume from
     * @param options Optional options to configure interpreter behavior
     * @returns The interpreter instance that is running the script
     */
    static resume(
        script: Script,
        handleDialogue: DialogueHandler,
        handleChoice: ChoiceHandler,
        handleFinish: FinishHandler,
        saveData: SaveData,
        beatName?: string,
        options?: InterpreterOptions
    ): Interpreter;

    /**
     * Extracts translations from a parsed translation script.
     *
     * Given a translation file parsed with `parse()`, this returns a translations map
     * that can be passed as `options.translations` to `play()` or `resume()`.
     *
     * @param script The parsed translation script (result from `parse()` on a `.XX.lor` file)
     * @returns A translations map to pass as `InterpreterOptions.translations`
     */
    static extractTranslations(script: Script): Translations;

    /**
     * Prints a parsed script back into Loreline source code.
     *
     * @param script The parsed script (result from `parse()`)
     * @param indent The indentation string to use (defaults to two spaces)
     * @param newline The newline string to use (defaults to "\n")
     * @returns The printed source code as a string
     */
    static print(script: Script, indent?: string, newline?: string): string;
}

export class Interpreter {
    /**
     * Creates a new Loreline script interpreter.
     *
     * @param script The parsed script to execute
     * @param handleDialogue Function to call when displaying dialogue text
     * @param handleChoice Function to call when presenting choices
     * @param handleFinish Function to call when execution finishes
     * @param options Additional options
     */
    constructor(
        script: Script,
        handleDialogue: DialogueHandler,
        handleChoice: ChoiceHandler,
        handleFinish: FinishHandler,
        options?: InterpreterOptions
    );

    /**
     * Starts script execution from the beginning or a specific beat.
     *
     * @param beatName Optional name of the beat to start from. If null, execution starts from
     *                 the first beat or a beat named "_" if it exists.
     * @throws RuntimeError If the specified beat doesn't exist or if no beats are found in the script
     */
    start(beatName?: string): void;

    /**
     * Saves the current state of the interpreter.
     * This includes all state variables, character states, and execution stack,
     * allowing execution to be resumed later from the exact same point.
     *
     * @return A SaveData object containing the serialized state
     */
    save(): SaveData;

    /**
     * Restores the interpreter state from a SaveData object.
     * This allows resuming execution from a previously saved state.
     *
     * @param saveData The SaveData object containing the serialized state
     * @throws RuntimeError If the save data version is incompatible
     */
    restore(saveData: SaveData): void;

    /**
     * Resumes execution after restoring state.
     * This should be called after restore() to continue execution.
     */
    resume(): void;

    /**
     * Gets a character by name.
     *
     * @param name The name of the character to get
     * @return The character's fields or null if the character doesn't exist
     */
    getCharacter(name: string): any;

    /**
     * Gets a specific field of a character.
     *
     * @param character The name of the character
     * @param name The name of the field to get
     * @return The field value or null if the character or field doesn't exist
     */
    getCharacterField(character: string, name: string): any;
}

/**
 * An object to store a Int64 from two `high` and `low` number values.
 */
export interface Int64 {
    /**
     * High value of the Int64
     */
    high: number;

    /**
     * Low value of the Int64
     */
    low: number;
}

/**
 * Represents a unique identifier for a node within the AST.
 * Uses a structured ID system with section, branch, block, and node components.
 */
export interface NodeId {
    /**
     * Converts the NodeId to a string representation.
     * @returns String in the format "section.branch.block.node"
     */
    toString(): string;

    /**
     * Converts the NodeId to its Int64 representation.
     * @returns The Int64 value of this NodeId
     */
    toInt64(): Int64;
}

/**
 * Base class for all AST nodes. Contains position information and basic JSON conversion.
 */
export class Node {
    /**
     * A unique identifier for this node within the AST, used to distinguish
     * it from other nodes in the script.
     */
    id: NodeId;

    /**
     * Source code position where this node appears.
     */
    pos: Position;

    /**
     * Returns the type of this node.
     * @return String representation of node type
     */
    type(): string;

    /**
     * Converts the node to a JSON representation.
     * @return Object containing node type and position
     */
    toJson(): any;

    /**
     * Traverses all child nodes of this node.
     * @param handleNode Function to call for each child node
     */
    each(handleNode: (node: Node, parent: Node) => void): void;
}

/**
 * Represents the root node of a Loreline script AST.
 */
export class Script extends Node {
    /**
     * Array of top-level declarations in the script.
     */
    body:Array<Node>;
}

/**
 * Base interface to hold loreline values
 * This interface allows to map loreline object fields to game-specific objects.
 */
export interface Fields {
    /**
     * Called when the object has been created from an interpreter
     */
    lorelineCreate(interpreter: Interpreter): void;

    /**
     * Get the value associated to the given field key
     */
    lorelineGet(interpreter: Interpreter, key: string): any;

    /**
     * Set the value associated to the given field key
     */
    lorelineSet(interpreter: Interpreter, key: string, value: any): void;

    /**
     * Check if a value exists for the given key
     */
    lorelineExists(interpreter: Interpreter, key: string): boolean;

    /**
     * Get all the fields of this object
     */
    lorelineFields(interpreter: Interpreter): string[];
}
