package loreline.test;

import loreline.Interpreter;
import loreline.Loreline;
import loreline.Node;

/**
 * Tests of the hash of Int64Map (the map of every NodeIdMap, the node states of
 * the interpreter among them) and of the saves across a change of that hash.
 *
 * The saves of SaveCompatData were recorded with the code of before the change
 * (a hash that xored the two halves of a key, saves whose node states came in the
 * order of the map). They must restore with the current code to the state they
 * restored to with that code: same output after the restore, and the same node
 * states in a save of the restored state. A save made by the current code holds
 * the same data as the old one, its node states in id order, and restores the
 * same way.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
@:access(loreline.Int64Map)
class SaveCompatTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'the hash is the same 32 bit value on every target', fn: () -> testHashValues()},
            {name: 'node ids that differ in every part get distinct hashes', fn: () -> testSpread()}
        ];
        for (record in SaveCompatData.RECORDS) {
            final label = record.script + ' at choice ' + record.choice;
            tests.push({name: 'a save of the old code restores: ' + label, fn: () -> testOldSave(record)});
            tests.push({name: 'a save of the current code restores: ' + label, fn: () -> testNewSave(record)});
        }

        for (test in tests) {
            try {
                test.fn();
                pass('save compatibility: ' + test.name);
            }
            catch (e:Any) {
                fail('save compatibility: ' + test.name, Std.string(e));
            }
        }

    }

    /**
     * Values of the murmur3 finalizer combination computed with unsigned 32 bit
     * arithmetic outside Haxe (BigInt on node), as signed 32 bit integers.
     */
    static final HASHES:Array<{high:Int, low:Int, hash:Int}> = [
        {high: 0, low: 0, hash: 0},
        {high: 1, low: 0, hash: 804215951},
        {high: 0, low: 1, hash: 1364076727},
        {high: -1, low: -1, hash: -835893607},
        {high: 2147483647, low: -2147483648, hash: 112974073},
        {high: -2147450879, low: -2147450879, hash: 1666825560},
        {high: -2147450879, low: -2147450878, hash: 185132997},
        {high: -2147418112, low: -2147483647, hash: -1540986995},
        {high: 123456789, low: -987654321, hash: -1362286655}
    ];

    static function testHashValues():Void {
        for (entry in HASHES) {
            final hash = Int64Map.hashCoords(entry.high, entry.low);
            if (hash != entry.hash) throw 'hash of (${entry.high}, ${entry.low}): expected ${entry.hash}, got $hash';
        }
    }

    static function testSpread():Void {
        // 10 000 ids over 4 sections, 10 branches, 25 blocks and 10 nodes: the old
        // hash gave them at most 512 distinct values (section ^ node, branch ^ block)
        final hashes = new Map<Int, Bool>();
        final slots = new Map<Int, Bool>();
        var count = 0;
        var distinct = 0;
        var distinctSlots = 0;
        for (section in 1...5) for (branch in 1...11) for (block in 1...26) for (node in 1...11) {
            final key = new NodeId(section, branch, block, node).toInt64();
            final hash = Int64Map.hashCoords(key.high, key.low);
            count++;
            if (!hashes.exists(hash)) {
                hashes.set(hash, true);
                distinct++;
            }
            final slot = hash & 16383;
            if (!slots.exists(slot)) {
                slots.set(slot, true);
                distinctSlots++;
            }
        }
        if (distinct < count - 10) throw 'only $distinct distinct hashes for $count ids';
        // About 7 470 expected for uniform hashes in 16 384 slots
        if (distinctSlots < 7000) throw 'only $distinctSlots distinct slots of 16384 for $count ids';
    }

    static function testOldSave(record:SaveCompatRecord):Void {
        final script = SaveCompatScripts.scriptOf(record.script);
        final resumed = SaveCompatScripts.resumeFrom(script, record.save, record.choices, record.choice);
        expectLines(record.after, resumed.lines, 'output after restoring the old save');
        // The restored node states are the saved ones (their order may differ:
        // compared once sorted). Only the node states: other parts of a save made
        // right after a restore differ from the first save on some targets (an
        // empty `beats` object in the stack on JS), with the old code too.
        expectSame(record.save, resumed.saveJson, 'node states of the restored state', 'nodeStates');
    }

    static function testNewSave(record:SaveCompatRecord):Void {
        final script = SaveCompatScripts.scriptOf(record.script);
        var saved:String = null;
        final lines = SaveCompatScripts.playAndSave(script, record.choices, record.choice, json -> saved = json);
        expectLines(record.before, lines, 'output of the uninterrupted run');
        if (saved == null) throw 'no save was made';
        expectSame(record.save, saved, 'new save compared to the old one');
        #if (js || php || python)
        // Targets where the fields of an object keep their order: node states in id order
        final ids = Reflect.fields(Reflect.field(haxe.Json.parse(saved), 'nodeStates'));
        final sorted = ids.copy();
        sorted.sort((a, b) -> {
            final x = NodeId.fromString(a);
            final y = NodeId.fromString(b);
            x.section != y.section ? x.section - y.section : x.branch != y.branch ? x.branch - y.branch : x.block != y.block ? x.block - y.block : x.node - y.node;
        });
        if (ids.join(' ') != sorted.join(' ')) throw 'node states not in id order: ' + ids.join(' ');
        #end
        final resumed = SaveCompatScripts.resumeFrom(SaveCompatScripts.scriptOf(record.script), saved, record.choices, record.choice);
        expectLines(record.after, resumed.lines, 'output after restoring the new save');
        expectSame(saved, resumed.saveJson, 'node states of the restored state', 'nodeStates');
    }

    static function expectLines(expected:Array<String>, actual:Array<String>, what:String):Void {
        if (expected.join('\n') != actual.join('\n')) {
            throw '$what differs.\nExpected:\n' + expected.join('\n') + '\nActual:\n' + actual.join('\n');
        }
    }

    static function expectSame(expectedJson:String, actualJson:String, what:String, ?field:String):Void {
        var expectedValue:Dynamic = haxe.Json.parse(expectedJson);
        var actualValue:Dynamic = haxe.Json.parse(actualJson);
        if (field != null) {
            expectedValue = Reflect.field(expectedValue, field);
            actualValue = Reflect.field(actualValue, field);
        }
        final expected = canonical(expectedValue);
        final actual = canonical(actualValue);
        if (expected != actual) throw '$what differs.\nExpected:\n$expected\nActual:\n$actual';
    }

    /** JSON text of a parsed value with the fields of objects sorted. */
    static function canonical(value:Dynamic):String {
        return switch Type.typeof(value) {
            case TNull: 'null';
            case TInt | TFloat | TBool: Std.string(value);
            case TClass(std.String): haxe.Json.stringify(value);
            case TClass(std.Array):
                final array:Array<Dynamic> = value;
                '[' + [for (item in array) canonical(item)].join(',') + ']';
            case _:
                final fields = Reflect.fields(value);
                fields.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
                '{' + [for (name in fields) haxe.Json.stringify(name) + ':' + canonical(Reflect.field(value, name))].join(',') + '}';
        }
    }

}

typedef SaveCompatRecord = {
    /** Name of the script (see SaveCompatTests.scriptOf) */
    var script:String;
    /** Choices answered, in order */
    var choices:Array<Int>;
    /** Index of the choice the save was made at, before answering it */
    var choice:Int;
    /** Output of the uninterrupted run */
    var before:Array<String>;
    /** The save, JSON */
    var save:String;
    /** Output of the run resumed from the save */
    var after:Array<String>;
}
