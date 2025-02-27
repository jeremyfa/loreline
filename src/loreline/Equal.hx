package loreline;

import haxe.ds.IntMap;
import haxe.ds.StringMap;

class Equal {

    /**
     * Deep (recursive) equality check between two values.
     * Supports arrays, StringMap, IntMap and objects with fields.
     * @param interpreter Optional interpreter instance
     * @param a First value to compare
     * @param b Second value to compare
     * @return Bool True if values are deeply equal
     */
    public static function equal(interpreter:Interpreter, a:Dynamic, b:Dynamic):Bool {

        if (a == b)
            return true;

        if (Arrays.isArray(a)) {
            if (Arrays.isArray(b)) {
                return arrayEqual(interpreter, a, b);
            }
            return false;
        }
        else if (a is StringMap) {
            if (b is StringMap) {
                return stringMapEqual(interpreter, a, b);
            }
            return false;
        }
        else if (a is IntMap) {
            if (b is IntMap) {
                return intMapEqual(interpreter, a, b);
            }
            return false;
        }
        else if (Objects.isFields(a)) {
            if (Objects.isFields(b)) {
                return objectFieldsEqual(interpreter, a, b);
            }
            return false;
        }

        return false;

    }

    public static function objectFieldsEqual(interpreter:Interpreter, a:Any, b:Any):Bool {
        for (field in Objects.getFields(interpreter, a)) {
            if (!Objects.fieldExists(interpreter, b, field) || !equal(interpreter, Objects.getField(interpreter, a, field), Objects.getField(interpreter, b, field))) {
                return false;
            }
        }
        for (field in Objects.getFields(interpreter, b)) {
            if (!Objects.fieldExists(interpreter, a, field)) {
                return false;
            }
        }
        return true;
    }

    public static function arrayEqual(interpreter:Interpreter, a:Any, b:Any):Bool {

        var lenA = Arrays.arrayLength(a);
        var lenB = Arrays.arrayLength(b);
        if (lenA != lenB)
            return false;
        for (i in 0...lenA) {
            if (!equal(interpreter, Arrays.arrayGet(a, i), Arrays.arrayGet(b, i))) {
                return false;
            }
        }
        return true;

    }

    public static function stringMapEqual(interpreter:Interpreter, a:StringMap<Any>, b:StringMap<Any>):Bool {

        for (key => val in a) {
            if (!b.exists(key))
                return false;
            if (!equal(interpreter, b.get(key), val))
                return false;
        }

        for (key in b.keys()) {
            if (!a.exists(key))
                return false;
        }

        return true;

    }

    public static function intMapEqual(interpreter:Interpreter, a:IntMap<Any>, b:IntMap<Any>):Bool {

        for (key => val in a) {
            if (!b.exists(key))
                return false;
            if (!equal(interpreter, b.get(key), val))
                return false;
        }

        for (key in b.keys()) {
            if (!a.exists(key))
                return false;
        }

        return true;

    }

}