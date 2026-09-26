package loreline.test;

import loreline.Interpreter;

/**
 * Represents a Loreline test case
 */
class TestCase {

    /** Test name for identification */
    public final name:String;

    /** The input to test */
    public final input:String;

    /** The expected output */
    public final expectedOutput:String;

    public function new(name:String, input:String, expectedOutput:String) {
        this.name = name;
        this.input = input;
        this.expectedOutput = expectedOutput;
    }

}

/**
 * Represents a Loreline test case for the interpreter
 */
class InterpreterTestCase extends TestCase {

    /**
     * The file path of the script being loaded (needed when importing other files)
     */
    public final filePath:String;

    /**
     * Optional beat name that will be passed to the interpreter so that it starts fromt it
     */
    public final beatName:String;

    /**
     * The choices to make during execution (0-based indices, taking into account all choice options provided, including the disabled ones)
     */
    public final choices:Array<Int>;

    /**
     * Custom options to passe to the interpreter
     */
    public final options:InterpreterOptions;

    /**
     * Choice points (0-indexed) where to save and restore. At each of them, the test
     * saves the interpreter state, creates a new interpreter, restores the state and
     * resumes execution. Indices count the choices of an uninterrupted run.
     */
    public final saveAtChoice:Array<Int>;

    /**
     * Dialogue events (0-indexed) where to save and restore, same as saveAtChoice.
     * The dialogue is re-presented on restore.
     */
    public final saveAtDialogue:Array<Int>;

    /**
     * If set, contains the content of a modified script to use when restoring
     * (instead of the original parsed script). Used for testing node ID stability
     * when a script is modified between save and restore.
     */
    public final restoreInput:String;

    public function new(name:String, input:String, filePath:String, beatName:String, choices:Array<Int>, options:InterpreterOptions, saveAtChoice:Array<Int>, saveAtDialogue:Array<Int>, restoreInput:String, expectedOutput:String) {
        super(name, input, expectedOutput);
        this.filePath = filePath;
        this.beatName = beatName;
        this.choices = choices != null ? [].concat(choices) : null;
        this.options = options;
        this.saveAtChoice = saveAtChoice != null ? saveAtChoice : [];
        this.saveAtDialogue = saveAtDialogue != null ? saveAtDialogue : [];
        this.restoreInput = restoreInput;
    }

    /**
     * Reads a `saveAtChoice` / `saveAtDialogue` value from the test YAML: absent,
     * a single index, or a list of indices.
     */
    public static function saveIndices(raw:Any):Array<Int> {
        if (raw == null) return [];
        if (raw is Int) return [raw];
        if (raw is Array) {
            final list:Array<Any> = raw;
            final result:Array<Int> = [];
            for (item in list) {
                if (!(item is Int)) throw 'Invalid save index: ' + Std.string(item);
                result.push(item);
            }
            return result;
        }
        throw 'Invalid save indices: ' + Std.string(raw);
    }

}
