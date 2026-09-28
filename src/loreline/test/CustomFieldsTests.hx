package loreline.test;

import haxe.ds.StringMap;
import loreline.Fields;
import loreline.Interpreter;
import loreline.Loreline;
import loreline.SaveData;
import loreline.Script;
import loreline.test.SpawnTests.FlowHost;

/**
 * Fields object handed out by the custom factory of the tests. Remembers
 * which interpreter created it.
 */
@:keep
class TestFields implements Fields {

    public var createdBy:String = null;

    final values:StringMap<Any> = new StringMap();

    public function new() {}

    public function lorelineCreate(interpreter:Interpreter):Void {}

    public function lorelineGet(interpreter:Interpreter, key:String):Any {
        return values.get(key);
    }

    public function lorelineSet(interpreter:Interpreter, key:String, value:Any):Void {
        values.set(key, value);
    }

    public function lorelineRemove(interpreter:Interpreter, key:String):Bool {
        return values.remove(key);
    }

    public function lorelineExists(interpreter:Interpreter, key:String):Bool {
        return values.exists(key);
    }

    public function lorelineFields(interpreter:Interpreter):Array<String> {
        return [for (key in values.keys()) key];
    }

}

/**
 * Tests of the `customCreateFields` interpreter option: the factory is used for
 * state and characters, survives save/restore, and spawned children call it
 * with themselves.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class CustomFieldsTests {

    static final SCRIPT = [
        'state',
        '  gold: 1',
        '',
        'character bob',
        '  name: Bob',
        '',
        'beat Main',
        '  state',
        '    visits: 0',
        '  visits = visits + 1',
        '  gold = gold + 1',
        '  bob.mood = "happy"',
        '',
        '  Main $$gold $$visits $$bob.mood',
        '',
        '  Main end',
        '',
        'beat Side',
        '  new state',
        '    local: 5',
        '',
        '  Side $$local'
    ].join('\n');

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'factory used for state and characters', fn: () -> testFactoryUsed()},
            {name: 'save and restore through the factory', fn: () -> testSaveRestore()},
            {name: 'spawned child calls the factory with itself', fn: () -> testSpawnedChild()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('custom fields: ' + test.name);
            }
            catch (e:Any) {
                fail('custom fields: ' + test.name, Std.string(e));
            }
        }

    }

    /**
     * Options whose factory records, for each created fields object, the
     * interpreter that asked for it and the requested type.
     */
    static function options(creators:Array<String>, types:Array<String>):InterpreterOptions {
        return ({
            customCreateFields: (interpreter:Interpreter, type:String, node:Node) -> {
                final fields = new TestFields();
                fields.createdBy = FlowHost.nameOf(interpreter);
                creators.push(fields.createdBy);
                if (type != null) types.push(type);
                fields;
            }
        } : InterpreterOptions);
    }

    static function parse():Script {
        final script = Loreline.parse(SCRIPT);
        if (script == null) throw 'Failed to parse script: ' + Loreline.lastError();
        return script;
    }

    static function expectEqual(expected:Any, actual:Any, what:String):Void {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ' + Std.string(expected) + ', got ' + Std.string(actual);
        }
    }

    static function expectTestFields(value:Any, what:String):TestFields {
        if (!(value is TestFields)) throw '$what: not created by the custom factory';
        return cast value;
    }

    static function testFactoryUsed():Void {

        final script = parse();
        final host = new FlowHost();
        final creators:Array<String> = [];
        final root = Loreline.play(script, host.dialogue, host.choice, host.finish, 'Main', options(creators, []));

        expectEqual('root: Main 2 1 happy', host.log[0], 'dialogue');
        expectTestFields(root.getCharacter('bob'), 'character bob');
        expectTestFields(@:privateAccess root.topLevelState.fields, 'top level state');
        expectEqual(2, root.getTopLevelStateField('gold'), 'gold');
        expectEqual('happy', root.getCharacterField('bob', 'mood'), 'bob.mood');
        if (creators.length == 0 || creators.indexOf('root') == -1) throw 'factory not called by the root';

    }

    static function testSaveRestore():Void {

        final script = parse();
        final host = new FlowHost();
        final root = Loreline.play(script, host.dialogue, host.choice, host.finish, 'Main', options([], []));
        final saveData:SaveData = haxe.Json.parse(haxe.Json.stringify(root.save()));

        final restoredHost = new FlowHost();
        final types:Array<String> = [];
        final restored = Loreline.resume(script, restoredHost.dialogue, restoredHost.choice, restoredHost.finish, saveData, null, options([], types));

        expectEqual('root: Main 2 1 happy', restoredHost.log[0], 'replayed dialogue');
        expectEqual('happy', restored.getCharacterField('bob', 'mood'), 'restored bob.mood');
        expectTestFields(restored.getCharacter('bob'), 'restored character bob');

        // The beat state is rebuilt from save data: the factory gets the saved type back
        final expectedType = Type.getClassName(TestFields);
        if (types.indexOf(expectedType) == -1) throw 'saved type not handed back to the factory: $types';

    }

    static function testSpawnedChild():Void {

        final script = parse();
        final host = new FlowHost();
        final creators:Array<String> = [];
        final root = Loreline.play(script, host.dialogue, host.choice, host.finish, 'Main', options(creators, []));
        final npc = root.spawn('npc', host.dialogue, host.choice, host.finish);
        npc.start('Side');

        expectEqual('npc: Side 5', host.log[host.log.length - 1], 'child dialogue');
        if (creators.indexOf('npc') == -1) throw 'factory not called with the child: $creators';

    }

}
