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
     * The file where the error is, when it isn't the root script: an imported
     * file. Null for the root script.
     */
    public var filePath:Null<String> = null;

    /**
     * The call stack of this error
     */
    public var stack:Array<StackItem>;

    /**
     * The English template the message was made from, when the tools can show
     * it in another language (see `loreline.i18n.I18n.errorText`). The message
     * itself is always in English.
     */
    public var template:Null<String> = null;

    /**
     * The parameters of the template, by name.
     */
    public var params:Null<Dynamic> = null;

    /**
     * Creates a new lexer error.
     * @param message The error message
     * @param pos The position where the error occurred
     */
    public function new(message:String, ?pos:Position) {
        this.message = message;
        this.pos = pos;
        this.stack = CallStack.callStack();
    }

    /**
     * An error from a text that the tools can show in another language: its
     * message is the English text, and it keeps its template and parameters.
     * @param text The text, made with `I18n.text`
     * @param pos The position where the error occurred
     */
    public static function of(text:loreline.i18n.I18nText, ?pos:Position):Error {
        return new Error(text.toString(), pos).keep(text);
    }

    /** Keeps the template and parameters of the text the message was made from */
    function keep(text:loreline.i18n.I18nText):Error {
        template = text.template;
        params = text.params;
        return this;
    }

    /**
     * Converts the error to a human-readable string.
     * @return Formatted error message with position
     */
    public function toString():String {
        return if (pos != null) {
            '$message at ${pos.toString()}';
        }
        else {
            message;
        }
    }

}
