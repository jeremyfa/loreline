package loreline;

import haxe.ds.StringMap;

/**
 * A map with string keys that iterates in insertion order, the same order on
 * every target.
 *
 * The iteration order of `StringMap` depends on the target (the order of a
 * JavaScript object on JS, the order of a hash table on C++), so anything
 * built by iterating one (a list of completion items, a list of names in a
 * message) comes in another order on node and on hxcpp. This map keeps its
 * keys in the order they were first set: setting a key again keeps its place,
 * removing a key and setting it again puts it last.
 *
 * `get`, `set`, `exists` and `remove` are O(1): a `StringMap` gives the slot
 * of a key in two arrays (keys and values). A removal leaves an empty slot;
 * the arrays are compacted when a key is added and more than half of the
 * slots are empty.
 *
 * It has the methods of `Map` (no array access). It can't be held by a
 * `Map<String, V>`: the compiler turns such a map into a `StringMap`.
 */
class OrderedStringMap<V> {

    /** Slot of each key in `slotKeys` and `slotValues` */
    var index:StringMap<Int>;

    /** Keys in insertion order, null for a removed entry */
    var slotKeys:Array<Null<String>>;

    var slotValues:Array<Null<V>>;

    /** Number of removed slots still in the arrays */
    var holes:Int = 0;

    public function new() {
        index = new StringMap();
        slotKeys = [];
        slotValues = [];
    }

    /** Number of entries */
    public var length(get, never):Int;
    inline function get_length():Int {
        return slotKeys.length - holes;
    }

    public function get(key:String):Null<V> {
        final slot = index.get(key);
        return slot == null ? null : slotValues[slot];
    }

    public function set(key:String, value:V):Void {
        final slot = index.get(key);
        if (slot != null) {
            slotValues[slot] = value;
        }
        else {
            // Compacted only when a key is added, never while removing, so
            // that removing the current key while iterating is safe
            if (holes > 8 && holes * 2 > slotKeys.length) compact();
            index.set(key, slotKeys.length);
            slotKeys.push(key);
            slotValues.push(value);
        }
    }

    public function exists(key:String):Bool {
        return index.exists(key);
    }

    public function remove(key:String):Bool {
        final slot = index.get(key);
        if (slot == null) return false;
        index.remove(key);
        slotKeys[slot] = null;
        slotValues[slot] = null;
        holes++;
        return true;
    }

    /** Removes the empty slots, keeping the order of the entries */
    function compact():Void {
        final keys:Array<Null<String>> = [];
        final values:Array<Null<V>> = [];
        for (i in 0...slotKeys.length) {
            final key = slotKeys[i];
            if (key != null) {
                index.set(key, keys.length);
                keys.push(key);
                values.push(slotValues[i]);
            }
        }
        slotKeys = keys;
        slotValues = values;
        holes = 0;
    }

    public function keys():Iterator<String> {
        return new OrderedStringMapKeyIterator(this);
    }

    public function iterator():Iterator<V> {
        return new OrderedStringMapValueIterator(this);
    }

    public function keyValueIterator():KeyValueIterator<String, V> {
        return new OrderedStringMapKeyValueIterator(this);
    }

    public function copy():OrderedStringMap<V> {
        final result = new OrderedStringMap<V>();
        for (i in 0...slotKeys.length) {
            final key = slotKeys[i];
            if (key != null) result.set(key, slotValues[i]);
        }
        return result;
    }

    public function clear():Void {
        index = new StringMap();
        slotKeys = [];
        slotValues = [];
        holes = 0;
    }

    public function toString():String {
        final buf = new StringBuf();
        buf.add('[');
        var first = true;
        for (i in 0...slotKeys.length) {
            final key = slotKeys[i];
            if (key == null) continue;
            if (!first) buf.add(', ');
            first = false;
            buf.add(key);
            buf.add(' => ');
            buf.add(Std.string(slotValues[i]));
        }
        buf.add(']');
        return buf.toString();
    }

    /** Slot after `slot` that holds an entry, or the number of slots */
    @:noCompletion public inline function nextSlot(slot:Int):Int {
        var next = slot + 1;
        while (next < slotKeys.length && slotKeys[next] == null) next++;
        return next;
    }

    @:noCompletion public inline function slotCount():Int {
        return slotKeys.length;
    }

    @:noCompletion public inline function keyAt(slot:Int):String {
        return slotKeys[slot];
    }

    @:noCompletion public inline function valueAt(slot:Int):V {
        return slotValues[slot];
    }

}

private class OrderedStringMapKeyIterator<V> {

    final map:OrderedStringMap<V>;

    var slot:Int;

    public inline function new(map:OrderedStringMap<V>) {
        this.map = map;
        slot = map.nextSlot(-1);
    }

    public inline function hasNext():Bool {
        return slot < map.slotCount();
    }

    public inline function next():String {
        final key = map.keyAt(slot);
        slot = map.nextSlot(slot);
        return key;
    }

}

private class OrderedStringMapValueIterator<V> {

    final map:OrderedStringMap<V>;

    var slot:Int;

    public inline function new(map:OrderedStringMap<V>) {
        this.map = map;
        slot = map.nextSlot(-1);
    }

    public inline function hasNext():Bool {
        return slot < map.slotCount();
    }

    public inline function next():V {
        final value = map.valueAt(slot);
        slot = map.nextSlot(slot);
        return value;
    }

}

private class OrderedStringMapKeyValueIterator<V> {

    final map:OrderedStringMap<V>;

    var slot:Int;

    public inline function new(map:OrderedStringMap<V>) {
        this.map = map;
        slot = map.nextSlot(-1);
    }

    public inline function hasNext():Bool {
        return slot < map.slotCount();
    }

    public inline function next():{key:String, value:V} {
        final result = {key: map.keyAt(slot), value: map.valueAt(slot)};
        slot = map.nextSlot(slot);
        return result;
    }

}
