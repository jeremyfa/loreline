package loreline;

class Arrays {

    public static function isArray(array:Any):Bool {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return true;
        }
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            return javaListLength(array);
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            return javaListGet(array, index);
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            return javaListSet(array, index, value);
        }
        #end

        final arr:Array<Any> = array;
        arr[i] = value;

    }

    public static function createArray():Any {
        #if (loreline_jvm_api && loreline_use_jvm_types && !macro)
        return new java.util.ArrayList();
        #elseif (loreline_cs_api && loreline_use_cs_types && !macro)
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            return javaListPush(array, value);
        }
        #end

        final arr:Array<Any> = array;
        arr.push(value);
    }

    public static function arrayPop(array:Any):Any {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) return csListPop(array);
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) return javaListPop(array);
        #end

        final arr:Array<Any> = array;
        return arr.pop();

    }

    public static function arrayShift(array:Any):Any {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) return csListShift(array);
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) return javaListShift(array);
        #end

        final arr:Array<Any> = array;
        return arr.shift();

    }

    public static function arrayInsert(array:Any, index:Int, value:Any):Void {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) { csListInsert(array, index, value); return; }
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) { javaListInsert(array, index, value); return; }
        #end

        final arr:Array<Any> = array;
        arr.insert(index, value);

    }

    public static function arrayRemoveAt(array:Any, index:Int):Void {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) { csListRemoveAt(array, index); return; }
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) { javaListRemoveAt(array, index); return; }
        #end

        final arr:Array<Any> = array;
        arr.splice(index, 1);

    }

    public static function getIterator(array:Any):Iterator<Dynamic> {

        #if (loreline_cs_api && !macro)
        if (isCsList(array)) {
            return csListIterator(array);
        }
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            return javaListIterator(array);
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            final len = javaListLength(array);
            for (i in 1...len) {
                final key = javaListGet(array, i);
                var j = i - 1;
                while (j >= 0) {
                    final jVal = javaListGet(array, j);
                    if (cmp(jVal, key) <= 0) break;
                    javaListSet(array, j + 1, jVal);
                    j--;
                }
                javaListSet(array, j + 1, key);
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
        #elseif (loreline_jvm_api && !macro)
        if (isJavaList(array)) {
            var i = 0;
            var j = javaListLength(array) - 1;
            while (i < j) {
                final tmp = javaListGet(array, i);
                javaListSet(array, i, javaListGet(array, j));
                javaListSet(array, j, tmp);
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

    #elseif (loreline_jvm_api && !macro)

    static function isJavaList(array:Any):Bool {
        return Std.isOfType(array, java.util.List);
    }

    static function javaListLength(array:Any):Int {
        final list:java.util.List<Dynamic> = cast array;
        return list.size();
    }

    static function javaListGet(array:Any, index:Int):Any {
        final list:java.util.List<Dynamic> = cast array;
        final size = list.size();
        return if (index >= 0 && index < size) {
            list.get(index);
        }
        else {
            null;
        }
    }

    static function javaListSet(array:Any, index:Int, value:Any):Void {
        final list:java.util.List<Dynamic> = cast array;
        var size = list.size();
        while (size < index) {
            list.add(null);
            size++;
        }
        if (index < list.size()) {
            list.set(index, value);
        } else {
            list.add(value);
        }
    }

    static function javaListPush(array:Any, value:Any):Void {
        final list:java.util.List<Dynamic> = cast array;
        list.add(value);
    }

    static function javaListPop(array:Any):Any {
        final list:java.util.List<Dynamic> = cast array;
        final size = list.size();
        if (size == 0) return null;
        return list.remove(size - 1);
    }

    static function javaListShift(array:Any):Any {
        final list:java.util.List<Dynamic> = cast array;
        if (list.size() == 0) return null;
        return list.remove(0);
    }

    static function javaListInsert(array:Any, index:Int, value:Any):Void {
        final list:java.util.List<Dynamic> = cast array;
        list.add(index, value);
    }

    static function javaListRemoveAt(array:Any, index:Int):Void {
        final list:java.util.List<Dynamic> = cast array;
        list.remove(index);
    }

    static function javaListIterator(array:Any):Iterator<Dynamic> {
        return new JavaListIterator(array);
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
        this.length = @:privateAccess Arrays.csListLength(array);
    }

    public function hasNext():Bool {
        return index < length;
    }

    public function next():Dynamic {
        var value = @:privateAccess Arrays.csListGet(list, index);
        index++;
        return value;
    }
}
#elseif (loreline_jvm_api && !macro)
class JavaListIterator {
    private var list:Any;
    private var index:Int;
    private var length:Int;

    public function new(array:Any) {
        this.list = array;
        this.index = 0;
        this.length = @:privateAccess Arrays.javaListLength(array);
    }

    public function hasNext():Bool {
        return index < length;
    }

    public function next():Dynamic {
        var value = @:privateAccess Arrays.javaListGet(list, index);
        index++;
        return value;
    }
}
#end
