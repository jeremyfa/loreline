package loreline;

import haxe.CallStack;

/**
 * Represents an error.
 */
class Error {

    /**
     * The error message describing what went wrong.
     */
    public var message:String;

    /**
     * The position in the source code where the error occurred.
     */
    public var pos:Position;

    /**
     * The call stack of this error
     */
    public var stack:Array<StackItem>;

    /**
     * Creates a new lexer error.
     * @param message The error message
     * @param pos The position where the error occurred
     */
    public function new(message:String, pos:Position) {
        this.message = message;
        this.pos = pos;
        this.stack = CallStack.callStack();
    }

    /**
     * Converts the error to a human-readable string.
     * @return Formatted error message with position
     */
    public function toString():String {
        return '$message at ${pos.toString()}';
    }

}
