package loreline.test;

import loreline.Loreline;
import loreline.Node;
import loreline.Script;

/**
 * Tests of imports that the script files can't express: errors inside
 * imported files, which must name the file they come from, and cycles read
 * through a file handler that answers later.
 * Tests are referenced through lambdas, see SpawnTests.
 */
@:keep
class ImportsTests {

    public static function run(pass:(name:String)->Void, fail:(name:String, error:String)->Void):Void {

        final tests:Array<{name:String, fn:()->Void}> = [
            {name: 'an error in a nested import names its file', fn: () -> testNestedParseError()},
            {name: 'an error in a directly imported file names its file', fn: () -> testDirectParseError()},
            {name: 'a lexer error in an import names its file', fn: () -> testLexerError()},
            {name: 'a missing nested import is reported', fn: () -> testMissingNestedImport()},
            {name: 'a cycle read by a file handler that answers later', fn: () -> testDeferredCycle()}
        ];

        for (test in tests) {
            try {
                test.fn();
                pass('imports: ' + test.name);
            }
            catch (e:Any) {
                fail('imports: ' + test.name, Std.string(e));
            }
        }

    }

    /**
     * Parses `story.lor` from a set of files in memory. When `deferred` is
     * set, the file handler answers after `Loreline.parse` has returned, the
     * way an asynchronous host does.
     */
    static function parse(files:Map<String, String>, deferred:Bool):{script:Null<Script>, error:Null<loreline.Error>} {
        final pending:Array<()->Void> = [];
        var script:Null<Script> = null;
        var error:Null<loreline.Error> = null;
        final handleFile = (path:String, callback:(data:String)->Void) -> {
            final content = files.get(path);
            if (deferred) {
                pending.push(() -> callback(content));
            }
            else {
                callback(content);
            }
        };
        try {
            Loreline.parse(files.get('story.lor'), 'story.lor', handleFile, result -> script = result);
            while (pending.length > 0) pending.shift()();
        }
        catch (e:loreline.Error) {
            error = e;
        }
        if (script == null && error == null) error = Loreline.lastError();
        return {script: script, error: error};
    }

    static function expectError(files:Map<String, String>, filePath:String, line:Int, message:Null<String>):Void {
        final result = parse(files, false);
        if (result.error == null) throw 'Expected an error in $filePath, the script parsed';
        if (result.error.filePath != filePath) {
            throw 'Expected the error in $filePath, got ${result.error.filePath}: ${result.error.message}';
        }
        if (result.error.pos == null || result.error.pos.line != line) {
            throw 'Expected the error at line $line of $filePath, got ${result.error.pos}: ${result.error.message}';
        }
        if (message != null && result.error.message.indexOf(message) == -1) {
            throw 'Expected "$message", got "${result.error.message}"';
        }
    }

    static function testNestedParseError():Void {
        expectError([
            'story.lor' => 'import parts/a\n\nbeat Start\n  Hi.\n',
            'parts/a.lor' => 'import b\n\nbeat A\n  A line.\n',
            'parts/b.lor' => 'beat B\n  x = )\n'
        ], 'parts/b.lor', 2, null);
    }

    static function testDirectParseError():Void {
        expectError([
            'story.lor' => 'import parts/b\n\nbeat Start\n  Hi.\n',
            'parts/b.lor' => 'beat B\n  x = )\n'
        ], 'parts/b.lor', 2, null);
    }

    static function testLexerError():Void {
        expectError([
            'story.lor' => 'import parts/a\n\nbeat Start\n  Hi.\n',
            'parts/a.lor' => 'state\n  金币：10\n'
        ], 'parts/a.lor', 2, 'looks like ":"');
    }

    static function testMissingNestedImport():Void {
        expectError([
            'story.lor' => 'import parts/a\n\nbeat Start\n  Hi.\n',
            'parts/a.lor' => 'import missing\n\nbeat A\n  A line.\n'
        ], 'parts/a.lor', 1, 'parts/missing.lor');
    }

    static function testDeferredCycle():Void {
        final result = parse([
            'story.lor' => 'import parts/a\n\ncharacter king\n  name: Louis\n\nbeat Start\n  king: Hi.\n  -> A\n',
            'parts/a.lor' => 'import ../story\n\nbeat A\n  king: Back.\n'
        ], true);
        if (result.error != null) throw 'Unexpected error: ' + result.error;
        if (result.script == null) throw 'The script was never given to the callback';
        var starts = 0;
        var kings = 0;
        result.script.each((node, parent) -> {
            if (node is NBeatDecl && (cast node:NBeatDecl).name == 'Start') starts++;
            if (node is NCharacterDecl && (cast node:NCharacterDecl).name == 'king') kings++;
        });
        if (starts != 1 || kings != 1) throw 'Expected one Start beat and one king, got $starts and $kings';
    }

}
