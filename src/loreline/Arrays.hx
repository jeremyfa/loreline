package loreline;

class Arrays {

    public static function isArray(array:Any):Bool {

        #if (loreline_cs_api && !macro)
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

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return csListLength(array);
        }
        #end

        final arr:Array<Any> = array;
        return arr.length;

    }

    public static function arrayGet(array:Any, index:Int):Any {

        final i:Int = Std.int(index);

        #if (loreline_cs_api && !macro)
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

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return csListSet(array, index, value);
        }
        #end

        final arr:Array<Any> = array;
        arr[i] = value;

    }

    public static function createArray():Any {
        #if (loreline_cs_api && loreline_use_cs_types && !macro)
        return cs.Syntax.code('new System.Collections.Generic.List<object>()');
        #else
        final arr:Array<Dynamic> = [];
        return arr;
        #end
    }

    public static function arrayPush(array:Any, value:Any):Void {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return csListPush(array, value);
        }
        #end

        final arr:Array<Any> = array;
        arr.push(value);
    }

    public static function arrayPop(array:Any):Any {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) return csListPop(array);
        #end

        final arr:Array<Any> = array;
        return arr.pop();

    }

    public static function arrayShift(array:Any):Any {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) return csListShift(array);
        #end

        final arr:Array<Any> = array;
        return arr.shift();

    }

    public static function arrayInsert(array:Any, index:Int, value:Any):Void {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) { csListInsert(array, index, value); return; }
        #end

        final arr:Array<Any> = array;
        arr.insert(index, value);

    }

    public static function arrayRemoveAt(array:Any, index:Int):Void {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) { csListRemoveAt(array, index); return; }
        #end

        final arr:Array<Any> = array;
        arr.splice(index, 1);

    }

    public static function getIterator(array:Any):Iterator<Dynamic> {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return csListIterator(array);
        }
        #end

        return (array:Array<Dynamic>).iterator();

    }

    public static function arrayCopy(array:Any):Any {
        final len = arrayLength(array);
        final copy = createArray();
        for (i in 0...len) arrayPush(copy, arrayGet(array, i));
        return copy;
    }

    public static function arraySort(array:Any, cmp:(Any, Any) -> Int):Void {
        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            final len = csListLength(array);
            for (i in 1...len) {
                final key = csListGet(array, i);
                var j = i - 1;
                while (j >= 0) {
                    final jVal = csListGet(array, j);
                    if (cmp(jVal, key) <= 0) break;
                    csListSet(array, j + 1, jVal);
                    j--;
                }
                csListSet(array, j + 1, key);
            }
            return;
        }
        #end
        final len = arrayLength(array);
        for (i in 1...len) {
            final key = arrayGet(array, i);
            var j = i - 1;
            while (j >= 0 && cmp(arrayGet(array, j), key) > 0) {
                arraySet(array, j + 1, arrayGet(array, j));
                j--;
            }
            arraySet(array, j + 1, key);
        }
    }

    public static function arrayReverse(array:Any):Void {
        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            var i = 0;
            var j = csListLength(array) - 1;
            while (i < j) {
                final tmp = csListGet(array, i);
                csListSet(array, i, csListGet(array, j));
                csListSet(array, j, tmp);
                i++;
                j--;
            }
            return;
        }
        #end
        var i = 0;
        var j = arrayLength(array) - 1;
        while (i < j) {
            final tmp = arrayGet(array, i);
            arraySet(array, i, arrayGet(array, j));
            arraySet(array, j, tmp);
            i++;
            j--;
        }
    }

    public static function arrayJoin(array:Any, sep:String):String {
        final len = arrayLength(array);
        var buf = new StringBuf();
        for (i in 0...len) {
            if (i > 0) buf.add(sep);
            buf.add(Std.string(arrayGet(array, i)));
        }
        return buf.toString();
    }

    #if (loreline_cs_api && !macro)

    static function isCsList(array:Any):Bool {
        return cs.Syntax.code('{0} is global::System.Collections.IList', array);
    }

    static function csListLength(array:Any):Int {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        return cs.Syntax.code('list.Count');
    }

    static function csListGet(array:Any, index:Int):Any {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        return cs.Syntax.code('list[{0}]', index);
    }

    static function csListSet(array:Any, index:Int, value:Any):Void {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('int len = list.Count;
        while (len < {0}) {
            list.Add(default(object));
            len++;
        }', index);
        cs.Syntax.code('list[{0}] = {1}', index, value);
    }

    static function csListPush(array:Any, value:Any):Void {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('list.Add({0})', value);
    }

    static function csListPop(array:Any):Any {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('if (list.Count == 0) return null');
        cs.Syntax.code('object last = list[list.Count - 1]');
        cs.Syntax.code('list.RemoveAt(list.Count - 1)');
        return cs.Syntax.code('last');
    }

    static function csListShift(array:Any):Any {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('if (list.Count == 0) return null');
        cs.Syntax.code('object first = list[0]');
        cs.Syntax.code('list.RemoveAt(0)');
        return cs.Syntax.code('first');
    }

    static function csListInsert(array:Any, index:Int, value:Any):Void {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('list.Insert({0}, {1})', index, value);
    }

    static function csListRemoveAt(array:Any, index:Int):Void {
        cs.Syntax.code('global::System.Collections.IList list = (global::System.Collections.IList){0}', array);
        cs.Syntax.code('list.RemoveAt({0})', index);
    }

    static function csListIterator(array:Any):Iterator<Dynamic> {
        return new CSListIterator(array);
    }

    #end

}

#if (loreline_cs_api && !macro)
class CSListIterator {
    private var list:Any;
    private var index:Int;
    private var length:Int;

    public function new(array:Any) {
        this.list = array;
        this.index = 0;
        // Get the length using the already implemented csListLength method
        this.length = @:privateAccess Arrays.csListLength(array);
    }

    public function hasNext():Bool {
        return index < length;
    }

    public function next():Dynamic {
        // Use the already implemented csListGet method
        var value = @:privateAccess Arrays.csListGet(list, index);
        index++;
        return value;
    }
}
#end
