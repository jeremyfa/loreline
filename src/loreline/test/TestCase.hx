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

    public function new(name:String, input:String, filePath:String, beatName:String, choices:Array<Int>, options:InterpreterOptions, expectedOutput:String) {
        super(name, input, expectedOutput);
        this.filePath = filePath;
        this.beatName = beatName;
        this.choices = choices != null ? [].concat(choices) : null;
        this.options = options;
    }

}
