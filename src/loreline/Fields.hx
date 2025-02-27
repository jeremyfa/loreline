package loreline;

/**
 * Base interface to hold loreline values
 */
interface Fields {

    /**
     * Called when the object has been created from an interpreter
     */
    function lorelineCreate(interpreter:Interpreter):Void;

    /**
     * Get the value associated to the given field key
     */
    function lorelineGet(interpreter:Interpreter, key:String):Any;

    /**
     * Set the value associated to the given field key
     */
    function lorelineSet(interpreter:Interpreter, key:String, value:Any):Void;

    /**
     * Check if a value exists for the given key
     */
    function lorelineExists(interpreter:Interpreter, key:String):Bool;

    /**
     * Get all the fields of this object
     */
    function lorelineFields(interpreter:Interpreter):Array<String>;

}
