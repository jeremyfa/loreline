package loreline;

/**
 * Base interface for objects that hold Loreline values.
 * It lets you map Loreline object fields to game-specific objects.
 */
#if js
@:expose
#end
interface Fields {

    /**
     * Called when the object has been created from an interpreter
     */
    function lorelineCreate(interpreter:Interpreter):Void;

    /**
     * Gets the value associated with the given field key
     */
    function lorelineGet(interpreter:Interpreter, key:String):Any;

    /**
     * Sets the value associated with the given field key
     */
    function lorelineSet(interpreter:Interpreter, key:String, value:Any):Void;

    /**
     * Removes the field associated with the given key
     */
    function lorelineRemove(interpreter:Interpreter, key:String):Bool;

    /**
     * Check if a value exists for the given key
     */
    function lorelineExists(interpreter:Interpreter, key:String):Bool;

    /**
     * Get all the fields of this object
     */
    function lorelineFields(interpreter:Interpreter):Array<String>;

}
