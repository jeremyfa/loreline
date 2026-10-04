package loreline.test;

import loreline.Node;

/**
 * Tests of NodeIdMap (over Int64Map) with every kind of value, primitive values
 * included: a slot must be told free whatever the value stored, false, 0 and the
 * empty string too. Many entries make the probe chains collide, then removes,
 * re-insertions and iteration go over them.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class NodeIdMapTests {

    static final COUNT = 300;

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'bool values', fn: () -> testValues([for (i in 0...COUNT) (i % 2 == 0 : Any)])},
            {name: 'int values, zero included', fn: () -> testValues([for (i in 0...COUNT) ((i % 7) : Any)])},
            {name: 'float values', fn: () -> testValues([for (i in 0...COUNT) ((i * 0.5) : Any)])},
            {name: 'string values, empty included', fn: () -> testValues([for (i in 0...COUNT) ((i % 5 == 0 ? '' : 'v$i') : Any)])},
            {name: 'object values', fn: () -> testValues([for (i in 0...COUNT) ({n: i} : Any)])}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('node id map: ' + test.name);
            }
            catch (e:Any) {
                fail('node id map: ' + test.name, Std.string(e));
            }
        }

    }

    /** Ids spread over sections, branches, blocks and nodes, like the ones of a script. */
    static function idOf(i:Int):NodeId {
        return new NodeId(1 + i % 3, 1 + (i >> 2) % 5, 1 + (i >> 4) % 11, 1 + i % 13);
    }

    static function testValues(values:Array<Any>):Void {

        final map = new NodeIdMap<Any>();

        // Distinct ids only: some of the formulas above may repeat
        final ids:Array<NodeId> = [];
        final seen = new Map<String, Bool>();
        for (i in 0...values.length) {
            final id = idOf(i * 7919 + 13);
            if (seen.exists(id.toString())) continue;
            seen.set(id.toString(), true);
            ids.push(id);
        }
        final count = ids.length;

        for (i in 0...count) map.set(ids[i], values[i]);
        expect(count, sizeOf(map), 'size after set');

        // A missing id must be told missing, not loop
        expect(false, map.exists(new NodeId(9, 9, 9, 9)), 'missing id');
        expect(null, map.get(new NodeId(9, 9, 9, 9)), 'missing value');

        for (i in 0...count) {
            expect(true, map.exists(ids[i]), 'exists $i');
            // Read into a local first: the C# generator copies an inline call
            // given to Std.string into both branches of its null check, which
            // declares its locals twice
            final value = map.get(ids[i]);
            expect(values[i], value, 'value $i');
        }

        // Remove every third entry: the others stay reachable
        var removed = 0;
        var i = 0;
        while (i < count) {
            map.remove(ids[i]);
            removed++;
            i += 3;
        }
        expect(count - removed, sizeOf(map), 'size after remove');
        for (i in 0...count) {
            expect(i % 3 != 0, map.exists(ids[i]), 'exists after remove $i');
        }

        // Iteration sees each remaining entry once
        var iterated = 0;
        for (value in map) iterated++;
        expect(count - removed, iterated, 'iterated values');
        var keys = 0;
        for (key in map.keys()) keys++;
        expect(count - removed, keys, 'iterated keys');

        // Removed ids can be set again
        var j = 0;
        while (j < count) {
            map.set(ids[j], values[j]);
            j += 3;
        }
        expect(count, sizeOf(map), 'size after set again');
        for (i in 0...count) {
            final value = map.get(ids[i]);
            expect(values[i], value, 'value again $i');
        }

    }

    static function sizeOf(map:NodeIdMap<Any>):Int {
        var size = 0;
        for (_ in map) size++;
        return size;
    }

    static function expect(expected:Any, actual:Any, what:String):Void {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ' + Std.string(expected) + ', got ' + Std.string(actual);
        }
    }

}
