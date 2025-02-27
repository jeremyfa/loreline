package loreline;

import haxe.Int64;
import haxe.ds.Vector;

@:allow(loreline.Int64MapIterator)
@:allow(loreline.Int64MapKeyIterator)
@:allow(loreline.Int64MapKeyValueIterator)
class Int64Map<V> {
    static inline var INITIAL_SIZE = 16; // Must be power of 2
    static inline var LOAD_FACTOR = 0.75;

    private var _keys1:Vector<Int> = null;
    private var _keys2:Vector<Int> = null;

    #if cs
    private var _values:Vector<Any> = null;
    #else
    private var _values:Vector<V> = null;
    #end

    private var size:Int = 0;
    private var mask:Int = 0;

    public function new() {
        resize(INITIAL_SIZE);
    }

    inline function resize(newCapacity:Int) {
        var oldK1 = _keys1;
        var oldK2 = _keys2;
        var oldVals = _values;

        _keys1 = new Vector(newCapacity);
        _keys2 = new Vector(newCapacity);
        _values = new Vector(newCapacity);
        mask = newCapacity - 1;

        if (oldK1 != null) {
            size = 0;
            for (i in 0...oldK1.length) {
                if (oldVals[i] != null) {
                    set(oldK1[i], oldK2[i], oldVals[i]);
                }
            }
        }
    }

    inline function hashCoords(high:Int, low:Int):Int {
        var h = high + (low << 16);
        h = (h ^ (h >>> 16)) * 0x85ebca6b;
        h = (h ^ (h >>> 13)) * 0xc2b2ae35;
        return h ^ (h >>> 16);
    }

    public function clear() {
        _keys1 = null;
        _keys2 = null;
        _values = null;
        resize(INITIAL_SIZE);
        size = 0;
    }

    public function copy():Int64Map<V> {
        final result = new Int64Map<V>();
        result._keys1 = _keys1.copy();
        result._keys2 = _keys2.copy();
        result._values = _values.copy();
        result.size = size;
        result.mask = mask;
        return result;
    }

    public extern inline overload function set(key:Int64, value:V) {
        _set(key.high, key.low, value);
    }

    public extern inline overload function set(high:Int, low:Int, value:V) {
        _set(high, low, value);
    }

    function _set(high:Int, low:Int, value:V) {
        if (size >= (mask + 1) * LOAD_FACTOR) {
            resize((mask + 1) << 1);
        }

        var hash = hashCoords(high, low);
        var index = hash & mask;

        while (true) {
            if (_values[index] == null) {
                _keys1[index] = high;
                _keys2[index] = low;
                _values[index] = value;
                size++;
                return;
            }
            if (_keys1[index] == high && _keys2[index] == low) {
                _values[index] = value;
                return;
            }
            index = (index + 1) & mask;
        }
    }

    public extern inline overload function get(key:Int64) {
        return _get(key.high, key.low);
    }

    public extern inline overload function get(high:Int, low:Int) {
        return _get(high, low);
    }

    function _get(high:Int, low:Int):Null<V> {
        var hash = hashCoords(high, low);
        var index = hash & mask;

        while (true) {
            if (_values[index] == null) return null;
            if (_keys1[index] == high && _keys2[index] == low) return _values[index];
            index = (index + 1) & mask;
        }
    }

    public extern inline overload function exists(key:Int64):Bool {
        return _exists(key.high, key.low);
    }

    public extern inline overload function exists(high:Int, low:Int):Bool {
        return _exists(high, low);
    }

    function _exists(high:Int, low:Int):Bool {
        var hash = hashCoords(high, low);
        var index = hash & mask;

        while (true) {
            if (_values[index] == null) return false;
            if (_keys1[index] == high && _keys2[index] == low) return true;
            index = (index + 1) & mask;
        }
    }

    public extern inline overload function remove(key:Int64):Bool {
        return _remove(key.high, key.low);
    }

    public extern inline overload function remove(high:Int, low:Int):Bool {
        return _remove(high, low);
    }

    function _remove(high:Int, low:Int):Bool {
        var hash = hashCoords(high, low);
        var index = hash & mask;

        while (true) {
            if (_values[index] == null) {
                return false;
            }
            if (_keys1[index] == high && _keys2[index] == low) {
                _values[index] = null;
                size--;

                // Re-insert any entries in the probe chain
                index = (index + 1) & mask;
                while (_values[index] != null) {
                    var k1 = _keys1[index];
                    var k2 = _keys2[index];
                    var v = _values[index];

                    _values[index] = null;
                    size--;

                    set(k1, k2, v);

                    index = (index + 1) & mask;
                }
                return true;
            }
            index = (index + 1) & mask;
        }
    }

    public function iterator():Int64MapIterator<V> {
        return new Int64MapIterator(this);
    }

    public function keyIterator():Int64MapKeyIterator<V> {
        return new Int64MapKeyIterator(this);
    }

    public function keyValueIterator():Int64MapKeyValueIterator<V> {
        return new Int64MapKeyValueIterator(this);
    }

    public inline function length():Int {
        return size;
    }
}

typedef Int64MapKeyVal<V> = {
    key: {
        high:Int,
        low:Int
    },
    value:V
}

typedef Int64MapKey = {
    high:Int,
    low:Int
}

private class Int64MapIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        return index < map._values.length;
    }

    public inline function next():V {
        var v = map._values[index];
        index++;
        skipNulls();
        return v;
    }
}

private class Int64MapKeyIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        return index < map._values.length;
    }

    public inline function next():Int64MapKey {
        var k1 = map._keys1[index];
        var k2 = map._keys2[index];
        index++;
        skipNulls();
        return {high: k1, low: k2};
    }
}

private class Int64MapKeyValueIterator<V> {
    var map:Int64Map<V>;
    var index:Int;

    public inline function new(map:Int64Map<V>) {
        this.map = map;
        this.index = 0;
        skipNulls();
    }

    inline function skipNulls() {
        while (index < map._values.length && map._values[index] == null) {
            index++;
        }
    }

    public inline function hasNext():Bool {
        return index < map._values.length;
    }

    public inline function next():Int64MapKeyVal<V> {
        var k1 = map._keys1[index];
        var k2 = map._keys2[index];
        var v = map._values[index];
        index++;
        skipNulls();
        return {
            key: {high: k1, low: k2},
            value: v
        };
    }
}