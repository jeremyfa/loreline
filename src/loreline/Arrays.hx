package loreline;

class Arrays {

    public static function isArray(array:Any):Bool {

        #if cs
        if (isCsList(array)) {
            return true;
        }
        #end

        if (array is Array) {
            return true;
        }

        return false;

    }

    public static function arrayLength(array:Any):Int {

        #if cs
        if (isCsList(array)) {
            return csListLength(array);
        }
        #end

        final arr:Array<Any> = array;
        return arr.length;

    }

    public static function arrayGet(array:Any, index:Int):Any {

        final i:Int = Std.int(index);

        #if cs
        if (isCsList(array)) {
            return csListGet(array, index);
        }
        #end

        final arr:Array<Any> = array;
        return if (i >= 0 && i < arr.length) {
            arr[i];
        }
        else {
            null;
        }

    }

    public static function arraySet(array:Any, index:Int, value:Any):Void {

        final i:Int = Std.int(index);

        #if cs
        if (isCsList(array)) {
            return csListSet(array, index, value);
        }
        #end

        final arr:Array<Any> = array;
        arr[i] = value;

    }

    public static function createArray():Any {
        #if (cs && loreline_use_cs_types)
        return untyped __cs__('new System.Collections.Generic.List<object>()');
        #else
        final arr:Array<Dynamic> = [];
        return arr;
        #end
    }

    public static function arrayPush(array:Any, value:Any):Void {

        #if cs
        if (isCsList(array)) {
            return csListPush(array, value);
        }
        #end

        final arr:Array<Any> = array;
        arr.push(value);
    }

    #if cs

    static function isCsList(array:Any):Bool {
        return untyped __cs__('{0} is global::System.Collections.IList', array);
    }

    static function csListLength(array:Any):Int {
        untyped __cs__('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        return untyped __cs__('list.Count');
    }

    static function csListGet(array:Any, index:Int):Any {
        untyped __cs__('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        return untyped __cs__('list[{0}]', index);
    }

    static function csListSet(array:Any, index:Int, value:Any):Void {
        untyped __cs__('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        untyped __cs__('int len = list.Count;
        while (len < {0}) {
            list.Add(default(object));
            len++;
        }', index);
        untyped __cs__('list[{0}] = {1}', index, value);
    }

    static function csListPush(array:Any, value:Any):Void {
        untyped __cs__('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        untyped __cs__('list.Add({1})', index, value);
    }

    #end

}
