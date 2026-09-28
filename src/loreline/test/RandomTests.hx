package loreline.test;

import loreline.Loreline;
import loreline.SaveData;
import loreline.Script;
import loreline.test.SpawnTests.FlowHost;

using StringTools;

/**
 * Tests of the random generator seen from the host: it is saved with the rest
 * of the state, and `seedRandom()` reseeds it for the whole context.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class RandomTests {

    static final SCRIPT = [
        'beat Main',
        '  seed_random(7)',
        '  First $$random(1, 1000000000)',
        '',
        '  Second $$random(1, 1000000000)',
        ''
    ].join('\n');

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'sequence continues after restore', fn: () -> testContinuesAfterRestore()},
            {name: 'seedRandom after restore', fn: () -> testSeedAfterRestore()},
            {name: 'seedRandom from a child reseeds the whole context', fn: () -> testSeedFromChild()},
            {name: 'seedRandom without a seed', fn: () -> testSeedFromClock()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('random: ' + test.name);
            }
            catch (e:Any) {
                fail('random: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse():Script {
        final script = Loreline.parse(SCRIPT);
        if (script == null) throw 'Failed to parse script: ' + Loreline.lastError();
        return script;
    }

    /** The number at the end of a logged line */
    static function valueOf(line:String):String {
        return line.substr(line.lastIndexOf(' ') + 1);
    }

    /**
     * Plays up to the first dialogue and saves there, through JSON.
     */
    static function saveAtFirst(script:Script):{host:FlowHost, save:SaveData} {
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        return {host: host, save: haxe.Json.parse(haxe.Json.stringify(root.save()))};
    }

    static function testContinuesAfterRestore():Void {

        final script = parse();
        final original = saveAtFirst(script);
        original.host.next('root');

        final restoredHost = new FlowHost();
        restoredHost.resume(script, original.save);
        restoredHost.next('root');

        if (restoredHost.log.join('\n') != original.host.log.join('\n')) {
            throw 'expected ' + original.host.log + ', got ' + restoredHost.log;
        }

    }

    static function testSeedAfterRestore():Void {

        final script = parse();
        final original = saveAtFirst(script);
        final first = valueOf(original.host.log[0]);

        // Same seed as the script: the next draw is the first one of the sequence again
        final restoredHost = new FlowHost();
        final restored = restoredHost.resume(script, original.save);
        restored.seedRandom(7);
        restoredHost.next('root');

        final second = valueOf(restoredHost.log[1]);
        if (second != first) throw 'expected $first after reseeding with 7, got $second';

    }

    static function testSeedFromChild():Void {

        final script = parse();
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        final first = valueOf(host.log[0]);

        final npc = host.spawn(root, 'npc');
        npc.seedRandom(7);
        host.next('root');

        final second = valueOf(host.log[1]);
        if (second != first) throw 'expected $first after reseeding the child with 7, got $second';

    }

    static function testSeedFromClock():Void {

        final script = parse();
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        root.seedRandom();
        host.next('root');

        final second = Std.parseInt(valueOf(host.log[1]));
        if (second == null || second < 1 || second > 1000000000) throw 'unexpected value: ' + host.log[1];
        if (root.save().random == null) throw 'generator missing from save data';

    }

}
