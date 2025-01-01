package loreline;

/**
 * Base interface to hold loreline values
 */
interface Fields {

    function lorelineGet(key:String):Any;

    function lorelineSet(key:String, value:Any):Void;

    function lorelineExists(key:String):Bool;

}
