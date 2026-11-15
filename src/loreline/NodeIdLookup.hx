package loreline;

import haxe.ds.Vector;
import loreline.Node.NodeId;

/**
 * A map from node ids to values for lookups only: set, get and exists, no
 * iteration and no removal. It is `NodeIdMap` with another hash.
 *
 * `Int64Map` xors the two halves of a key before mixing them: the halves of
 * node ids are small numbers that cancel out, so many ids share a hash and
 * the probes get long (a script of 10 000 lines has 34 000 nodes and 2 500
 * distinct values of that xor). On JS its products are also doubles that
 * aren't wrapped to 32 bits, which loses the low bits of the hash. A lookup in
 * a map of the nodes of a large script then costs more the larger it is.
 *
 * `Int64Map` keeps its hash: its iteration order follows it, and the order of
 * some of its maps shows (the save data of the interpreter). This one can't
 * be iterated, so its hash shows nowhere.
 */
class NodeIdLookup<V> {

    static inline var INITIAL_SIZE = 16; // Must be power of 2
    static inline var LOAD_FACTOR = 0.75;

    var keys1:Vector<Int> = null;
    var keys2:Vector<Int> = null;

    #if cs
    var values:Vector<Any> = null;
    #else
    var values:Vector<V> = null;
    #end

    /** Which slots hold an entry (see `Int64Map._used` for why not null values) */
    var used:Vector<Bool> = null;

    var size:Int = 0;
    var mask:Int = 0;

    public function new() {
        resize(INITIAL_SIZE);
    }

    function resize(newCapacity:Int) {
        final oldK1 = keys1;
        final oldK2 = keys2;
        final oldVals = values;
        final oldUsed = used;

        keys1 = new Vector(newCapacity);
        keys2 = new Vector(newCapacity);
        values = new Vector(newCapacity);
        used = new Vector(newCapacity);
        for (i in 0...newCapacity) used[i] = false;
        mask = newCapacity - 1;

        if (oldK1 != null) {
            size = 0;
            for (i in 0...oldK1.length) {
                if (oldUsed[i]) {
                    setCoords(oldK1[i], oldK2[i], oldVals[i]);
                }
            }
        }
    }

    /**
     * The hash of a key. The two halves are not mixed with a plain xor as in
     * `Int64Map`: the halves of node ids (section and branch, block and node)
     * are small numbers that cancel out, and a large script has more than ten
     * ids for each value of their xor. The high half goes through a
     * multiplication first, then the whole through the finalizer of
     * MurmurHash3. The products wrap to 32 bits on every target.
     */
    inline function hashCoords(high:Int, low:Int):Int {
        var h = mul(high, 0x9e3779b1) ^ low;
        h = mul(h ^ (h >>> 16), 0x85ebca6b);
        h = mul(h ^ (h >>> 13), 0xc2b2ae35);
        return h ^ (h >>> 16);
    }

    #if js
    static inline function mul(a:Int, b:Int):Int {
        return js.Syntax.code('Math.imul({0}, {1})', a, b);
    }
    #elseif (cpp || cs || java || hl)
    static inline function mul(a:Int, b:Int):Int {
        return a * b;
    }
    #else
    // Targets whose ints are wider than 32 bits, or become floats (PHP): the
    // product of the 16-bit halves, kept to 31 bits
    static inline function mul(a:Int, b:Int):Int {
        final aLo = a & 0xFFFF;
        final aHi = (a >>> 16) & 0xFFFF;
        final bLo = b & 0xFFFF;
        final bHi = (b >>> 16) & 0xFFFF;
        return (aLo * bLo + (((aLo * bHi + aHi * bLo) & 0xFFFF) << 16)) & 0x7FFFFFFF;
    }
    #end

    public inline function set(key:NodeId, value:V):Void {
        final k = key.toInt64();
        setCoords(k.high, k.low, value);
    }

    public inline function get(key:NodeId):Null<V> {
        final k = key.toInt64();
        return getCoords(k.high, k.low);
    }

    public inline function exists(key:NodeId):Bool {
        final k = key.toInt64();
        return existsCoords(k.high, k.low);
    }

    function setCoords(high:Int, low:Int, value:V):Void {
        if (size >= (mask + 1) * LOAD_FACTOR) {
            resize((mask + 1) << 1);
        }
        var index = hashCoords(high, low) & mask;
        while (true) {
            if (!used[index]) {
                keys1[index] = high;
                keys2[index] = low;
                values[index] = value;
                used[index] = true;
                size++;
                return;
            }
            if (keys1[index] == high && keys2[index] == low) {
                values[index] = value;
                return;
            }
            index = (index + 1) & mask;
        }
    }

    function getCoords(high:Int, low:Int):Null<V> {
        var index = hashCoords(high, low) & mask;
        while (true) {
            if (!used[index]) return null;
            if (keys1[index] == high && keys2[index] == low) return values[index];
            index = (index + 1) & mask;
        }
    }

    function existsCoords(high:Int, low:Int):Bool {
        var index = hashCoords(high, low) & mask;
        while (true) {
            if (!used[index]) return false;
            if (keys1[index] == high && keys2[index] == low) return true;
            index = (index + 1) & mask;
        }
    }

}
