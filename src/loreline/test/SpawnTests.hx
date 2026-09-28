package loreline.test;

import loreline.Interpreter;
import loreline.Loreline;
import loreline.SaveData;
import loreline.Script;

using StringTools;

/**
 * Host used by the spawn tests: records the events of every interpreter in a single
 * log, prefixed by the interpreter key ("root" for the root one), and keeps the pending
 * callbacks so that each test decides which flow moves forward, and when.
 */
class FlowHost {

    public final log:Array<String> = [];

    final dialogueCallbacks:Map<String, ()->Void> = new Map();

    final choiceCallbacks:Map<String, (index:Int)->Void> = new Map();

    /**
     * Optional hook called after a dialogue was logged.
     */
    public var afterDialogue:(interpreter:Interpreter, text:String)->Void = null;

    public function new() {}

    public static function nameOf(interpreter:Interpreter):String {
        return interpreter.key ?? "root";
    }

    public function dialogue(interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void):Void {
        final name = nameOf(interpreter);
        log.push('$name: ' + (character != null ? '$character: ' : '') + text);
        dialogueCallbacks.set(name, callback);
        if (afterDialogue != null) afterDialogue(interpreter, text);
    }

    public function choice(interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void):Void {
        final name = nameOf(interpreter);
        log.push('$name? ' + [for (o in options) (o.enabled ? '' : '-') + o.text].join(' | '));
        choiceCallbacks.set(name, callback);
    }

    public function finish(interpreter:Interpreter):Void {
        log.push(nameOf(interpreter) + ': <end>');
    }

    public function options():InterpreterOptions {
        final functions:FunctionsMap = #if loreline_functions_map_dynamic_access {} #else new Map<String, Any>() #end;
        functions.set("who", (interpreter:Interpreter, args:Array<Any>) -> nameOf(interpreter));
        functions.set("host_get", (interpreter:Interpreter, args:Array<Any>) -> interpreter.getStateField(args[0]));
        return ({functions: functions} : InterpreterOptions);
    }

    public function play(script:Script, ?beat:String):Interpreter {
        return Loreline.play(script, dialogue, choice, finish, beat, options());
    }

    public function resume(script:Script, saveData:SaveData):Interpreter {
        return Loreline.resume(script, dialogue, choice, finish, saveData, null, options());
    }

    public function spawn(parent:Interpreter, key:String):Interpreter {
        return parent.spawn(key, dialogue, choice, finish);
    }

    public function hasPendingDialogue(name:String):Bool {
        return dialogueCallbacks.exists(name);
    }

    public function next(name:String):Void {
        final cb = dialogueCallbacks.get(name);
        if (cb == null) throw 'No pending dialogue for $name';
        dialogueCallbacks.remove(name);
        cb();
    }

    public function choose(name:String, index:Int):Void {
        final cb = choiceCallbacks.get(name);
        if (cb == null) throw 'No pending choice for $name';
        choiceCallbacks.remove(name);
        cb(index);
    }

    /**
     * Log lines added since the given length.
     */
    public function since(length:Int):Array<String> {
        return log.slice(length);
    }

}

/**
 * Tests of child interpreters spawned from a root interpreter: shared state,
 * separate playheads, lifecycle, and save/restore of every playhead.
 * Tests are referenced through lambdas: a static method used as a value is
 * looked up by reflection on C#, which AOT trimming breaks.
 */
@:keep
class SpawnTests {

    static final SHARED_SCRIPT = [
        'state',
        '  gold: 0',
        '',
        'character bob',
        '  name: Bob',
        '  mood: calm',
        '',
        'function where()',
        '  return current_beat()',
        '',
        'beat Main',
        '  gold = gold + 1',
        '  Main gold $$gold',
        '',
        '  Main gold $$gold mood $$bob.mood',
        '',
        '  Main where $$where() visits $$beat_visits()',
        '',
        'beat Side',
        '  new state',
        '    local: 5',
        '  gold = gold + 10',
        '  bob.mood = "angry"',
        '  Side gold $$gold',
        '',
        '  Side where $$where() host $$who() local $$local',
        '',
        '  Side end'
    ].join('\n');

    static final COUNTER_SCRIPT = [
        'beat Counter',
        '  new state',
        '    n: 0',
        '  state',
        '    m: 0',
        '  n = n + 1',
        '  m = m + 1',
        '  count $$n shared $$m',
        '',
        '  n = n + 1',
        '  m = m + 1',
        '  count $$n shared $$m visits $$beat_visits()',
        '',
        'beat Idle',
        '  Idle',
        '',
        '  Idle again'
    ].join('\n');

    static final CHOICE_SCRIPT = [
        'state',
        '  picked: ""',
        '',
        'beat Main',
        '  Main starts',
        '',
        '  Main middle',
        '',
        '  Main sees $$picked',
        '',
        '  Main end',
        '',
        'beat Shop',
        '  choice',
        '    Buy bread',
        '      picked = "bread"',
        '    + Extras',
        '    - Buy once',
        '      picked = "once"',
        '  Bought $$picked',
        '',
        '  Shop end',
        '',
        'beat Extras',
        '  choice',
        '    Buy silk',
        '      picked = "silk"',
        '',
        'beat Once',
        '  choice',
        '    - Buy once',
        '      picked = "once"',
        '    Leave',
        '  Once end'
    ].join('\n');

    static final RANDOM_SCRIPT = [
        'beat Seed',
        '  seed_random(7)',
        '  a = random(1, 1000000)',
        '  Seed $$a',
        '',
        '',
        'beat Draw',
        '  b = random(1, 1000000)',
        '  Draw $$b'
    ].join('\n');

    static final INSERTION_SCRIPT = [
        'state',
        '  n: 0',
        '',
        'function bump()',
        '  n = n + 1',
        '  return n',
        '',
        'beat Main',
        '  Main line $$bump().',
        '',
        '  Main end with n $$n.',
        '',
        'beat Shop',
        '  choice',
        '    Local',
        '      Local picked.',
        '    + Extra',
        '  Shop epilogue.',
        '',
        'beat Extra',
        '  Extra intro.',
        '',
        '  choice',
        '    Extra option',
        '      Extra picked.',
        '  Extra epilogue.'
    ].join('\n');

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'shared state and characters', fn: () -> testSharedState()},
            {name: 'temporary state isolation', fn: () -> testTemporaryStateIsolation()},
            {name: 'shared once options', fn: () -> testSharedOnceOptions()},
            {name: 'shared random generator', fn: () -> testSharedRandom()},
            {name: 'synchronous spawn from a dialogue handler', fn: () -> testSpawnFromHandler()},
            {name: 'save from child equals save from root', fn: () -> testSaveFromChild()},
            {name: 'restore and resumeSpawn', fn: () -> testRestoreAndResumeSpawn()},
            {name: 'restore with child waiting on a choice with insertions', fn: () -> testRestoreChildAtInsertionChoice()},
            {name: 'spawn discards a pending restored flow', fn: () -> testSpawnDiscardsPendingFlow()},
            {name: 'spawn replaces a live child', fn: () -> testSpawnReplacesLiveChild()},
            {name: 'finished child is not saved', fn: () -> testFinishedChildNotSaved()},
            {name: 'finished root with running children', fn: () -> testFinishedRootWithChildren()},
            {name: 'restore on a child throws', fn: () -> testRestoreOnChildThrows()},
            {name: 'child saved while collecting insertion options', fn: () -> testChildSavedDuringCollection()},
            {name: 'child saved in the parent epilogue after an inserted option', fn: () -> testChildSavedInEpilogue()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('spawn: ' + test.name);
            }
            catch (e:Any) {
                fail('spawn: ' + test.name, Std.string(e));
            }
        }

    }

    static function parse(content:String):Script {
        final script = Loreline.parse(content);
        if (script == null) throw 'Failed to parse script: ' + Loreline.lastError();
        return script;
    }

    static function expectLines(expected:Array<String>, actual:Array<String>):Void {
        if (expected.join('\n') != actual.join('\n')) {
            throw '\n  expected:\n    ' + expected.join('\n    ') + '\n  got:\n    ' + actual.join('\n    ');
        }
    }

    static function expectEqual(expected:Any, actual:Any, what:String):Void {
        if (Std.string(expected) != Std.string(actual)) {
            throw '$what: expected ' + Std.string(expected) + ', got ' + Std.string(actual);
        }
    }

    static function expectThrows(fn:()->Void, what:String):Void {
        var threw = false;
        try {
            fn();
        }
        catch (e:Any) {
            threw = true;
        }
        if (!threw) throw '$what: expected an error';
    }

    static function jsonRoundTrip(saveData:SaveData):SaveData {
        return haxe.Json.parse(haxe.Json.stringify(saveData));
    }

    static function testSharedState():Void {

        final script = parse(SHARED_SCRIPT);
        final host = new FlowHost();

        final root = host.play(script, 'Main');
        final npc = host.spawn(root, 'npc');
        npc.start('Side');
        host.next('root');
        host.next('npc');
        host.next('root');
        host.next('npc');

        expectLines([
            'root: Main gold 1',
            'npc: Side gold 11',
            'root: Main gold 11 mood angry',
            'npc: Side where Side host npc local 5',
            'root: Main where Main visits 1',
            'npc: Side end'
        ], host.log);

        // Host API reads the shared state from any interpreter
        expectEqual(11, npc.getStateField('gold'), 'child getStateField');
        expectEqual(11, root.getTopLevelStateField('gold'), 'root getTopLevelStateField');
        expectEqual('angry', root.getCharacterField('bob', 'mood'), 'character field');
        expectEqual(false, npc.isRoot(), 'npc.isRoot');
        expectEqual(true, root.isRoot(), 'root.isRoot');

    }

    static function testTemporaryStateIsolation():Void {

        final script = parse(COUNTER_SCRIPT);
        final host = new FlowHost();

        final root = host.play(script, 'Counter');
        final npc = host.spawn(root, 'npc');
        npc.start('Counter');
        host.next('root');
        host.next('npc');

        // `new state` is per playhead, beat `state` and visit counts are shared
        expectLines([
            'root: count 1 shared 1',
            'npc: count 1 shared 2',
            'root: count 2 shared 3 visits 2',
            'npc: count 2 shared 4 visits 2'
        ], host.log);

    }

    static function testSharedOnceOptions():Void {

        final script = parse(CHOICE_SCRIPT);
        final host = new FlowHost();

        final root = host.play(script, 'Once');
        host.choose('root', 0);
        final npc = host.spawn(root, 'npc');
        npc.start('Once');

        expectLines([
            'root? Buy once | Leave',
            'root: Once end',
            'npc? -Buy once | Leave'
        ], host.log.filter(l -> !l.endsWith('<end>')));

    }

    static function testSharedRandom():Void {

        final script = parse(RANDOM_SCRIPT);
        final host = new FlowHost();

        final root = host.play(script, 'Seed');
        final npc = host.spawn(root, 'npc');
        npc.start('Draw');

        // A single interpreter drawing twice after the same seed gives the reference sequence
        final reference = new FlowHost();
        reference.play(parse(RANDOM_SCRIPT + '\n\nbeat Both\n  seed_random(7)\n  a = random(1, 1000000)\n  Seed $$a\n  b = random(1, 1000000)\n  Draw $$b'), 'Both');
        reference.next('root');

        expectLines(['root: ' + reference.log[0].substr('root: '.length), 'npc: ' + reference.log[1].substr('root: '.length)], host.log);

    }

    static function testSpawnFromHandler():Void {

        final script = parse(SHARED_SCRIPT);
        final host = new FlowHost();

        // The child is spawned and started while the root is inside its dialogue handler
        host.afterDialogue = (interpreter, text) -> {
            if (FlowHost.nameOf(interpreter) == 'root' && text == 'Main gold 1') {
                host.spawn(interpreter, 'npc').start('Side');
            }
        };
        host.play(script, 'Main');
        host.next('root');
        host.next('npc');

        expectLines([
            'root: Main gold 1',
            'npc: Side gold 11',
            'root: Main gold 11 mood angry',
            'npc: Side where Side host npc local 5'
        ], host.log);

    }

    static function testSaveFromChild():Void {

        final script = parse(SHARED_SCRIPT);
        final host = new FlowHost();

        final root = host.play(script, 'Main');
        final npc = host.spawn(root, 'npc');
        npc.start('Side');

        final fromRoot = haxe.Json.stringify(root.save());
        final fromChild = haxe.Json.stringify(npc.save());
        expectEqual(fromRoot, fromChild, 'save');

        final saveData = root.save();
        expectEqual(1, saveData.children.length, 'children count');
        expectEqual('npc', saveData.children[0].key, 'child key');

    }

    /**
     * Plays root and child to their end, one step each in turn, returning the log.
     * Used as the reference of an uninterrupted run.
     */
    static function driveToEnd(host:FlowHost, names:Array<String>):Void {
        var moved = true;
        while (moved) {
            moved = false;
            for (name in names) {
                if (host.hasPendingDialogue(name)) {
                    host.next(name);
                    moved = true;
                }
            }
        }
    }

    static function testRestoreAndResumeSpawn():Void {

        final script = parse(SHARED_SCRIPT);

        // Uninterrupted reference run
        final reference = new FlowHost();
        final refRoot = reference.play(script, 'Main');
        reference.spawn(refRoot, 'npc').start('Side');
        reference.next('root');
        final refMark = reference.log.length;
        driveToEnd(reference, ['root', 'npc']);
        final expected = reference.since(refMark);

        // Same run, saved at the same point then restored in a fresh root
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        host.spawn(root, 'npc').start('Side');
        host.next('root');
        final saveData = jsonRoundTrip(root.save());

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        expectLines(['npc'], restoredRoot.resumableSpawnKeys());
        final npc = restoredRoot.resumeSpawn('npc', restoredHost.dialogue, restoredHost.choice, restoredHost.finish);
        expectLines([], restoredRoot.resumableSpawnKeys());
        npc.resume();

        // Resuming replays the pending dialogues, then both flows continue
        final mark = restoredHost.log.length;
        driveToEnd(restoredHost, ['root', 'npc']);
        expectLines([
            'root: Main gold 11 mood angry',
            'npc: Side gold 11'
        ], restoredHost.log.slice(0, mark));
        expectLines(expected, restoredHost.since(mark));

    }

    static function testRestoreChildAtInsertionChoice():Void {

        final script = parse(CHOICE_SCRIPT);

        final host = new FlowHost();
        final root = host.play(script, 'Main');
        final npc = host.spawn(root, 'shop');
        npc.start('Shop');
        host.next('root');

        final saveData = jsonRoundTrip(npc.save());

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        final shop = restoredRoot.resumeSpawn('shop', restoredHost.dialogue, restoredHost.choice, restoredHost.finish);
        shop.resume();
        restoredHost.choose('shop', 1);
        restoredHost.next('root');

        expectLines([
            'root: Main middle',
            'shop? Buy bread | Buy silk | Buy once',
            'shop: Bought silk',
            'root: Main sees silk'
        ], restoredHost.log);

    }

    static function testSpawnDiscardsPendingFlow():Void {

        final script = parse(SHARED_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        host.spawn(root, 'npc').start('Side');
        final saveData = root.save();

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        final fresh = restoredHost.spawn(restoredRoot, 'npc');
        expectLines([], restoredRoot.resumableSpawnKeys());
        expectThrows(() -> restoredRoot.resumeSpawn('npc'), 'resumeSpawn after spawn');
        fresh.start('Side');
        expectEqual('npc: Side gold 21', restoredHost.log[restoredHost.log.length - 1], 'fresh child');

    }

    static function testSpawnReplacesLiveChild():Void {

        final script = parse(COUNTER_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Idle');
        final first = host.spawn(root, 'npc');
        first.start('Idle');
        final staleNext = @:privateAccess host.dialogueCallbacks.get('npc');

        final second = host.spawn(root, 'npc');
        expectThrows(() -> first.start('Idle'), 'start on disposed child');

        // The callback handed out by the disposed child does nothing
        final mark = host.log.length;
        staleNext();
        expectLines([], host.since(mark));

        second.start('Counter');
        final saveData = root.save();
        expectEqual(1, saveData.children.length, 'children count');
        expectEqual(1, saveData.children[0].stack.length > 0 ? 1 : 0, 'saved child stack');

    }

    static function testFinishedChildNotSaved():Void {

        final script = parse(COUNTER_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Idle');
        final npc = host.spawn(root, 'npc');
        npc.start('Idle');
        host.next('npc');
        host.next('npc');

        expectEqual('npc: <end>', host.log[host.log.length - 1], 'child finished');
        final saveData = root.save();
        expectEqual(null, saveData.children, 'children');

        // A finished child can run again
        npc.start('Idle');
        expectEqual(1, root.save().children.length, 'children after restart');

    }

    static function testFinishedRootWithChildren():Void {

        final script = parse(COUNTER_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Idle');
        host.spawn(root, 'npc').start('Idle');
        host.next('root');
        host.next('root');

        final saveData = jsonRoundTrip(root.save());
        expectEqual(true, saveData.finished, 'finished');

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        restoredRoot.resumeSpawn('npc').resume();
        restoredHost.next('npc');

        expectLines([
            'root: <end>',
            'npc: Idle',
            'npc: Idle again'
        ], restoredHost.log);

    }

    /**
     * The root waits on a dialogue whose interpolation has a side effect, while the
     * child waits on a dialogue shown during the collection of an insertion. After
     * a restore, both pending lines are re-presented as displayed (the side effect
     * doesn't run again) and the child goes on with its choice and epilogues.
     */
    static function testChildSavedDuringCollection():Void {

        final script = parse(INSERTION_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        host.spawn(root, 'shop').start('Shop');
        final saveData:SaveData = haxe.Json.parse(haxe.Json.stringify(root.save()));

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        restoredRoot.resumeSpawn('shop').resume();
        restoredHost.next('shop');
        restoredHost.choose('shop', 1);
        while (restoredHost.hasPendingDialogue('shop')) restoredHost.next('shop');
        restoredHost.next('root');

        expectLines([
            'root: Main line 1.',
            'shop: Extra intro.',
            'shop? Local | Extra option',
            'shop: Extra picked.',
            'shop: Extra epilogue.',
            'shop: Shop epilogue.',
            'shop: <end>',
            'root: Main end with n 1.'
        ], restoredHost.log);

    }

    static function testChildSavedInEpilogue():Void {

        final script = parse(INSERTION_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        host.spawn(root, 'shop').start('Shop');
        host.next('shop');
        host.choose('shop', 1);
        host.next('shop');
        host.next('shop');
        // The child now waits on its parent epilogue line
        if (host.log[host.log.length - 1] != 'shop: Shop epilogue.') throw 'unexpected log: ' + host.log;
        final saveData:SaveData = haxe.Json.parse(haxe.Json.stringify(root.save()));

        final restoredHost = new FlowHost();
        final restoredRoot = restoredHost.resume(script, saveData);
        restoredRoot.resumeSpawn('shop').resume();
        restoredHost.next('shop');

        expectLines([
            'root: Main line 1.',
            'shop: Shop epilogue.',
            'shop: <end>'
        ], restoredHost.log);

    }

    static function testRestoreOnChildThrows():Void {

        final script = parse(SHARED_SCRIPT);
        final host = new FlowHost();
        final root = host.play(script, 'Main');
        final npc = host.spawn(root, 'npc');
        final saveData = root.save();
        expectThrows(() -> npc.restore(saveData), 'restore on child');
        expectThrows(() -> root.spawn(null), 'spawn without key');
        expectThrows(() -> root.dispose(), 'dispose root');

    }

}
