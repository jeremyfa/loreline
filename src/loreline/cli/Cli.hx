package loreline.cli;

import haxe.CallStack.StackItem;
import haxe.CallStack;
import haxe.Json;
import haxe.io.Path;
import loreline.AstUtils;
import loreline.Error;
import loreline.Interpreter;
import loreline.Lens;
import loreline.test.TestCase;
import loreline.test.TestRunner;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;
using loreline.Utf8;
using loreline.cli.CliColors;

enum CliCommand {

    PLAY;

    JSON;

}

@:structInit
class CliOptions {

}

class Cli {

    public static function main() {
        new Cli();
    }

    public static function lorelineVersion():String {
        #if !cppia
        static final fullVersion = '${CliMacros.lorelineVersion()}-${CliMacros.gitCommitShortHash()}';
        return fullVersion;
        #else
        return null;
        #end
    }

    var errorInStdOut:Bool = false;

    var typeDelay:Float = 0.005;

    var sentenceDelay:Float = 0.2;

    var showDisabled:Bool = false;

    var lastCharacter:String = null;

    var loadedSave:Bool = false;

    var hasFailedTest:Bool = false;

    var passCount:Int = 0;

    var failCount:Int = 0;

    function new() {

        #if loreline_debug_interpreter
        Interpreter.debug = (message, ?pos) -> {
            haxe.Log.trace(message.magenta(), pos);
            print('');
        };
        #end

        final args = [].concat(Sys.args());

        #if neko
        if (args.length > 0 && FileSystem.exists(args[args.length-1]) && FileSystem.isDirectory(args[args.length-1])) {
            Sys.setCwd(args.pop());
        }
        #end

        var i = 2;
        while (i < args.length) {
            if (args[i] == '--show-disabled') {
                showDisabled = true;
                args.splice(i, 1);
            }
            else {
                i++;
            }
        }

        if (args.length >= 1) {
            switch args[0] {

                case 'version':
                    print('v' + lorelineVersion());

                case 'play':
                    if (args.length >= 2)
                        play(args[1]);
                    else
                        fail('Missing file argument');

                case 'json':
                    if (args.length >= 2)
                        json(args[1]);
                    else
                        fail('Missing file argument');

                case 'ast':
                    if (args.length >= 2)
                        ast(args[1]);
                    else
                        fail('Missing file argument');

                case 'test':
                    if (args.length >= 2)
                        test(args[1]);
                    else
                        fail('Missing path argument');

                case 'test-cli':
                    if (args.length >= 2)
                        testCli(args[1]);
                    else
                        fail('Missing path argument');

                case 'format':
                    if (args.length >= 2)
                        format(args[1]);
                    else
                        fail('Missing file argument');

                case 'translate':
                    if (args.length >= 2)
                        translate(args[1], args);
                    else
                        fail('Missing file argument');

                case _:
                    help();
            }
        }
        else {
            help();
        }

    }

    function help() {

        print("  _                _ _            ".green());
        print((" | | ___  _ __ ___| (_)_ __   ___   v" + lorelineVersion()).green());
        print(" | |/ _ \\| '__/ _ \\ | | '_ \\ / _ \\".green());
        print(" | | (_) | | |  __/ | | | | |  __/".green());
        print(" |_|\\___/|_|  \\___|_|_|_| |_|\\___|".green());
        print("");
        print(" " + "USAGE".bold());
        print(" loreline " + "[".gray() + "play" + "|".gray() + "json" + "|".gray() + "ast" + "|".gray() + "format" + "|".gray() + "translate" + "]".gray() + " " + "story.lor".underline());
        print("");

    }

    function handleFile(path:String, cb:(content:String)->Void) {
        // Pass null for missing files (the contract Imports.resolve and
        // Loreline.loadLocale both expect). loadLocale silently skips
        // missing translation files; the parser surfaces missing imports
        // as a parse error.
        if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
            cb(File.getContent(path));
        } else {
            cb(null);
        }
    }

    function json(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(Json.stringify(script.toJson(), null, '  '));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function ast(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(new AstPrinter().print(script));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function test(path:String) {

        passCount = 0;
        failCount = 0;
        var fileCount = 0;
        var fileFailCount = 0;

        // Test fixtures exercise every supported translation format.
        Loreline.translationFormat("po", true);
        Loreline.translationFormat("xliff", true);
        Loreline.translationFormat("csv", true);

        if (FileSystem.exists(path) && FileSystem.isDirectory(path)) {
            var dir = path;
            for (file in FileSystem.readDirectory(dir)) {
                if (file.endsWith('.lor') && !~/\.\w{2}\.lor$/.match(file)) {
                    final filePath = Path.join([dir, file]);
                    fileCount++;
                    final failBefore = failCount;
                    testFile(filePath, false);
                    testFile(filePath, true);
                    if (failCount > failBefore) fileFailCount++;
                }
            }
        }
        else {
            fileCount++;
            final failBefore = failCount;
            testFile(path, false);
            testFile(path, true);
            if (failCount > failBefore) fileFailCount++;
        }

        print('');
        if (failCount > 0) {
            final total = passCount + failCount;
            print('  $failCount of $total tests failed ($fileFailCount of $fileCount files)'.red().bold());
        }
        else {
            print('  All $passCount tests passed ($fileCount files)'.green().bold());
        }
        print('');

        if (hasFailedTest) {
            Sys.exit(1);
        }
    }

    /**
     * Folder-based CLI integration test runner.
     *
     * Discovers immediate subdirectories of `dir` that contain a `spec.yml`
     * file and runs each as one integration test:
     *   1. Wipes and recreates `.tmp/cli-test-runs/<name>/` as the workspace.
     *   2. Copies `<test>/input/**` into the workspace.
     *   3. Spawns `neko run.n <spec.args>` with the workspace as cwd
     *      (achieved by appending the workspace path as the last arg, which
     *      the CLI's bootstrap interprets as the cwd to switch to).
     *   4. Applies the spec's assertions:
     *      - exit code matches `spec.exitCode` (default 0)
     *      - stdout contains `spec.stdoutContains` (if set)
     *      - stderr contains `spec.stderrContains` (if set)
     *      - every file under `<test>/expected/` exists in the workspace and
     *        matches byte-for-byte
     *      - every path in `spec.expectMissing` does NOT exist in the workspace
     *   5. On pass, deletes the workspace. On failure, keeps it so the
     *      developer can inspect the actual outputs.
     */
    function testCli(dir:String) {

        passCount = 0;
        failCount = 0;

        if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) {
            fail('Invalid test-cli directory: $dir');
        }

        final cwd = Sys.getCwd();
        final runNPath = Path.join([cwd, "run.n"]);
        if (!FileSystem.exists(runNPath)) {
            fail('Cannot find run.n at $runNPath — build the CLI first (e.g. `node run`).');
        }

        final runsRoot = Path.join([cwd, ".tmp", "cli-test-runs"]);
        createDirectoryRecursive(runsRoot);

        // Discover test-case folders (alphabetical for deterministic order).
        final testFolders:Array<{name:String, path:String}> = [];
        for (entry in FileSystem.readDirectory(dir)) {
            final folder = Path.join([dir, entry]);
            if (FileSystem.isDirectory(folder)
                && FileSystem.exists(Path.join([folder, "spec.yml"]))) {
                testFolders.push({ name: entry, path: folder });
            }
        }
        testFolders.sort((a, b) -> Reflect.compare(a.name, b.name));

        var fileCount = 0;
        var fileFailCount = 0;
        for (tf in testFolders) {
            fileCount++;
            final failBefore = failCount;
            // Run each fixture twice: once with LF line endings (as-authored),
            // once with CRLF (transformed at copy time). This mirrors the unit
            // test runner's LF/CRLF dual pass and catches line-ending bugs in
            // the parser, the generators, or the read/write pipeline.
            runOneCliTest(tf.name, tf.path, runNPath, runsRoot, false);
            runOneCliTest(tf.name, tf.path, runNPath, runsRoot, true);
            if (failCount > failBefore) fileFailCount++;
        }

        print('');
        if (failCount > 0) {
            final total = passCount + failCount;
            print('  $failCount of $total CLI test cases failed'.red().bold());
        }
        else if (fileCount == 0) {
            print('  No CLI test cases found under $dir'.gray());
        }
        else {
            print('  All $passCount CLI test cases passed'.green().bold());
        }
        print('');

        if (hasFailedTest) {
            Sys.exit(1);
        }
    }

    function runOneCliTest(name:String, testPath:String, runNPath:String, runsRoot:String, crlf:Bool):Void {

        final modeLabel = crlf ? "CRLF" : "LF";
        final displayName = name + " ~ " + modeLabel;
        final workspaceName = crlf ? (name + "__CRLF") : name;
        final workspace = Path.join([runsRoot, workspaceName]);
        // Wipe any leftover workspace from a prior run.
        if (FileSystem.exists(workspace)) {
            deleteDirectoryRecursive(workspace);
        }
        createDirectoryRecursive(workspace);

        // Copy input/ contents into the workspace. In CRLF mode, transform
        // text content's line endings to CRLF as we copy.
        final inputDir = Path.join([testPath, "input"]);
        if (FileSystem.exists(inputDir) && FileSystem.isDirectory(inputDir)) {
            copyDirectoryRecursive(inputDir, workspace, crlf);
        }

        // Read spec.yml.
        final specPath = Path.join([testPath, "spec.yml"]);
        final specContent = File.getContent(specPath);
        var spec:Dynamic;
        try {
            spec = Yaml.parse(specContent);
        } catch (e:Any) {
            recordCliFailure(displayName, workspace, 'failed to parse spec.yml: ' + Std.string(e));
            return;
        }
        if (spec == null || spec.args == null || !(spec.args is Array)) {
            recordCliFailure(displayName, workspace, 'spec.yml must define an `args` array.');
            return;
        }

        final argsList:Array<Dynamic> = cast spec.args;
        final stringArgs = [for (a in argsList) Std.string(a)];
        final expectedExitCode:Int = spec.exitCode != null ? (cast spec.exitCode:Int) : 0;
        final stdoutContains:String = spec.stdoutContains != null ? Std.string(spec.stdoutContains) : null;
        final stderrContains:String = spec.stderrContains != null ? Std.string(spec.stderrContains) : null;
        final expectMissingRaw:Array<Dynamic> = (spec.expectMissing != null && (spec.expectMissing is Array))
            ? cast spec.expectMissing
            : [];
        final expectMissing = [for (p in expectMissingRaw) Std.string(p)];

        // Spawn the CLI: `neko <abs-run.n> <spec.args...> <workspace>`.
        // Trailing workspace is the cwd-switch convention used by Cli.main.
        final processArgs = [runNPath].concat(stringArgs).concat([workspace]);
        var stdout = "";
        var stderr = "";
        var exitCode = -1;
        try {
            final proc = new Process("neko", processArgs);
            stdout = proc.stdout.readAll().toString();
            stderr = proc.stderr.readAll().toString();
            exitCode = proc.exitCode();
            proc.close();
        } catch (e:Any) {
            recordCliFailure(displayName, workspace, 'failed to spawn `neko ${processArgs.join(" ")}`: ' + Std.string(e));
            return;
        }

        var failures:Array<String> = [];

        if (exitCode != expectedExitCode) {
            failures.push('exit code: expected $expectedExitCode, got $exitCode');
        }
        if (stdoutContains != null && stdout.indexOf(stdoutContains) == -1) {
            failures.push('stdout missing expected substring: "$stdoutContains"');
        }
        if (stderrContains != null && stderr.indexOf(stderrContains) == -1) {
            failures.push('stderr missing expected substring: "$stderrContains"');
        }

        // Compare every file under expected/ to the workspace counterpart.
        // In CRLF mode the expected content is transformed the same way the
        // input was, since the CLI is expected to preserve the surrounding
        // line-ending style.
        final expectedDir = Path.join([testPath, "expected"]);
        if (FileSystem.exists(expectedDir) && FileSystem.isDirectory(expectedDir)) {
            final relExpectedFiles = listFilesRecursive(expectedDir, "");
            for (rel in relExpectedFiles) {
                final expectedFile = Path.join([expectedDir, rel]);
                final actualFile = Path.join([workspace, rel]);
                if (!FileSystem.exists(actualFile)) {
                    failures.push('expected file missing in workspace: $rel');
                    continue;
                }
                var expected = File.getContent(expectedFile);
                if (crlf) {
                    expected = expected.split("\r\n").join("\n").split("\n").join("\r\n");
                }
                final actual = File.getContent(actualFile);
                if (expected != actual) {
                    failures.push('file content mismatch: $rel\n' + formatDiff(expected, actual));
                }
            }
        }

        // Verify expectMissing.
        for (rel in expectMissing) {
            final p = Path.join([workspace, rel]);
            if (FileSystem.exists(p)) {
                failures.push('file expected to be missing but exists: $rel');
            }
        }

        if (failures.length == 0) {
            passCount++;
            print(('PASS'.green() + ' - ' + displayName.gray()));
            // Clean up on success.
            deleteDirectoryRecursive(workspace);
        }
        else {
            recordCliFailure(displayName, workspace, failures.join('\n'), stdout, stderr);
        }
    }

    function recordCliFailure(name:String, workspace:String, message:String, ?stdout:String, ?stderr:String):Void {
        failCount++;
        hasFailedTest = true;
        print(('FAIL'.red() + ' - ' + name + (' (workspace: ' + workspace + ')').gray()));
        for (line in message.split('\n')) {
            print('  ' + line);
        }
        if (stdout != null && stdout.length > 0) {
            print(('  --- stdout ---').gray());
            for (line in stdout.split('\n')) print('  ' + line);
        }
        if (stderr != null && stderr.length > 0) {
            print(('  --- stderr ---').gray());
            for (line in stderr.split('\n')) print('  ' + line);
        }
    }

    /**
     * Line-based unified diff: shows up to 30 differing lines as `- expected`
     * / `+ actual`. Trailing newline differences are surfaced explicitly.
     */
    function formatDiff(expected:String, actual:String):String {
        final exp = expected.split('\n');
        final act = actual.split('\n');
        final buf = new StringBuf();
        var shown = 0;
        final maxShown = 30;
        final maxLines = exp.length > act.length ? exp.length : act.length;
        for (i in 0...maxLines) {
            final e = i < exp.length ? exp[i] : null;
            final a = i < act.length ? act[i] : null;
            if (e == a) continue;
            if (shown >= maxShown) {
                buf.add('  ... (' + (maxLines - i) + ' more differing lines)\n');
                break;
            }
            if (e != null) buf.add('  - ' + e + '\n');
            if (a != null) buf.add('  + ' + a + '\n');
            shown++;
        }
        return buf.toString();
    }

    // ── Recursive file-system helpers ─────────────────────────────────

    function createDirectoryRecursive(path:String):Void {
        if (FileSystem.exists(path)) return;
        final parent = Path.directory(path);
        if (parent.length > 0 && parent != path && !FileSystem.exists(parent)) {
            createDirectoryRecursive(parent);
        }
        FileSystem.createDirectory(path);
    }

    function deleteDirectoryRecursive(path:String):Void {
        if (!FileSystem.exists(path)) return;
        if (FileSystem.isDirectory(path)) {
            for (entry in FileSystem.readDirectory(path)) {
                deleteDirectoryRecursive(Path.join([path, entry]));
            }
            FileSystem.deleteDirectory(path);
        } else {
            FileSystem.deleteFile(path);
        }
    }

    function copyDirectoryRecursive(src:String, dst:String, convertToCrlf:Bool = false):Void {
        if (!FileSystem.exists(dst)) FileSystem.createDirectory(dst);
        for (entry in FileSystem.readDirectory(src)) {
            final s = Path.join([src, entry]);
            final d = Path.join([dst, entry]);
            if (FileSystem.isDirectory(s)) {
                copyDirectoryRecursive(s, d, convertToCrlf);
            } else if (convertToCrlf) {
                final content = File.getContent(s);
                final converted = content.split("\r\n").join("\n").split("\n").join("\r\n");
                File.saveContent(d, converted);
            } else {
                File.copy(s, d);
            }
        }
    }

    /**
     * Returns every file (not directory) under `root`, as paths relative to
     * `root`. `prefix` is used internally to accumulate the path during
     * recursion; pass "" at the top level.
     */
    function listFilesRecursive(root:String, prefix:String):Array<String> {
        final result:Array<String> = [];
        final base = prefix.length == 0 ? root : Path.join([root, prefix]);
        for (entry in FileSystem.readDirectory(base)) {
            final relPath = prefix.length == 0 ? entry : prefix + "/" + entry;
            final fullPath = Path.join([base, entry]);
            if (FileSystem.isDirectory(fullPath)) {
                for (sub in listFilesRecursive(root, relPath)) result.push(sub);
            } else {
                result.push(relPath);
            }
        }
        return result;
    }

    function testFile(file:String, crlf:Bool) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            var content = File.getContent(file);
            if (crlf) {
                content = content.replace("\r\n", "\n").replace("\n", "\r\n");
            }
            else {
                content = content.replace("\r\n", "\n");
            }
            final script = Loreline.parse(content, file, handleFile);

            // Collect test items from <test> YAML blocks
            var testItems:Array<Dynamic> = [];
            var restoreInputs:Array<String> = [];
            script.eachComment((node, comment) -> {
                if (comment.multiline) {
                    final testStart = comment.content.uIndexOf('<test>');
                    if (testStart != -1) {
                        final testEnd = comment.content.uIndexOf('</test>', testStart + 6);
                        if (testEnd != -1) {
                            final testYml = Yaml.parse(comment.content.uSubstring(testStart + 6, testEnd).trim());
                            if (testYml != null && testYml is Array) {
                                for (item in (testYml:Array<Dynamic>)) {
                                    var restoreInput:String = null;
                                    if (item.restoreFile != null) {
                                        final restorePath = Path.join([Path.directory(file), item.restoreFile]);
                                        restoreInput = File.getContent(restorePath);
                                        if (crlf) {
                                            restoreInput = restoreInput.replace("\r\n", "\n").replace("\n", "\r\n");
                                        } else {
                                            restoreInput = restoreInput.replace("\r\n", "\n");
                                        }
                                    }
                                    testItems.push(item);
                                    restoreInputs.push(restoreInput);
                                }
                            }
                        }
                    }
                }
            });

            // Run each test case on the original script
            for (idx in 0...testItems.length) {
                final item = testItems[idx];
                final restoreInput = restoreInputs[idx];
                final saveAtChoice:Int = item.saveAtChoice != null ? item.saveAtChoice : -1;
                final saveAtDialogue:Int = item.saveAtDialogue != null ? item.saveAtDialogue : -1;
                var options:InterpreterOptions = null;
                if (item.translation != null) {
                    final lang:String = item.translation;
                    final translations = Loreline.loadLocale(lang, script, file, handleFile);
                    if (translations != null) {
                        options = ({translations: translations} : InterpreterOptions);
                    }
                }
                final testCase = new InterpreterTestCase(
                    file, content, file,
                    item.beat, item.choices, options,
                    saveAtChoice, saveAtDialogue, restoreInput, item.expected
                );
                final testRunner = new TestRunner(handleFile);
                testRunner.runTestCase(testCase, result -> {
                    final testCase:InterpreterTestCase = cast result.testCase;
                    final modeLabel = crlf ? 'CRLF' : 'LF';
                    final choicesLabel = testCase.choices != null && testCase.choices.length > 0 ? ' ~ '.gray() + '[${testCase.choices.join(',')}]'.gray() : '';
                    if (result.passed) {
                        passCount++;
                        print('PASS'.green().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + choicesLabel);
                    }
                    else {
                        failCount++;
                        hasFailedTest = true;
                        print('FAIL'.red().bold() + (result.error != null ? ' - ' + result.error : '') + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + choicesLabel);

                        if (TestRunner.compareOutput(testCase.expectedOutput, result.actualOutput) != -1) {

                            print('');

                            // Normalize line endings (CRLF -> LF) and trim whitespace
                            final normalizedExpected = testCase.expectedOutput.replace("\r\n", "\n").trim().split("\n");
                            final normalizedActual = result.actualOutput.replace("\r\n", "\n").trim().split("\n");

                            final minLen = Std.int(Math.min(normalizedExpected.length, normalizedActual.length));
                            final maxLen = Std.int(Math.max(normalizedExpected.length, normalizedActual.length));

                            var foundDifference = false;
                            var i = 0;
                            while (i < minLen) {
                                if (normalizedExpected[i] == normalizedActual[i]) {
                                    print(normalizedActual[i].yellow());
                                }
                                else {
                                    print('> Unexpected output at line ${i+1}');
                                    print('>  got: ' + normalizedActual[i].red());
                                    print('> need: ' + normalizedExpected[i].yellow());
                                    foundDifference = true;
                                    break;
                                }
                                i++;
                            }

                            if (!foundDifference && i < maxLen) {
                                if (i < normalizedActual.length) {
                                    while (i < maxLen && normalizedActual[i].trim().length <= 0) {
                                        i++;
                                    }
                                    print('> Unexpected output at line ${i+1}');
                                    print('>  got: ' + normalizedActual[i].red());
                                    print('> need: ' + '(empty)'.yellow());
                                }
                                else {
                                    while (i < maxLen && normalizedExpected[i].trim().length <= 0) {
                                        i++;
                                    }
                                    print('> Unexpected output at line ${i+1}');
                                    print('>  got: ' + '(empty)'.red());
                                    print('> need: ' + normalizedExpected[i].yellow());
                                }
                            }

                            print('\n');
                        }

                    }
                });
            }

            // Combined round-trip test: structural idempotency + behavioral equivalence
            if (testItems.length > 0) {
                testRoundTrip(script, file, crlf, testItems, restoreInputs);
            }

            // JSON round-trip test: toJson → fromJson → toJson must be stable
            testJsonRoundTrip(script, file, crlf);

            // AST printer smoke test: print must not throw
            testAstPrint(script, file, crlf);
        }
        catch (e:Any) {
            failCount++;
            hasFailedTest = true;
            print('FAIL'.red().bold() + ' - $e - ' + file.gray());
        }

    }

    function testRoundTrip(script:Script, file:String, crlf:Bool, testItems:Array<Dynamic>, restoreInputs:Array<String>) {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        try {
            final newline = crlf ? "\r\n" : "\n";
            final printer = new Printer("  ", newline);

            // Structural check: print → parse → print must be stable
            final print1 = printer.print(script);
            final script2 = Loreline.parse(print1, file, handleFile);
            final print2 = printer.print(script2);
            if (print1 != print2) {
                failCount++;
                hasFailedTest = true;
                print('FAIL'.red().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'roundtrip'.gray());

                // Show first difference
                final lines1 = print1.replace("\r\n", "\n").split("\n");
                final lines2 = print2.replace("\r\n", "\n").split("\n");
                final minLen = Std.int(Math.min(lines1.length, lines2.length));
                for (i in 0...minLen) {
                    if (lines1[i] != lines2[i]) {
                        print('> Printer output not idempotent at line ${i + 1}');
                        print('>  print1: ' + lines1[i].red());
                        print('>  print2: ' + lines2[i].yellow());
                        break;
                    }
                }
                if (lines1.length != lines2.length) {
                    print('> Line count differs: print1=${lines1.length}, print2=${lines2.length}');
                }
                print('');
                return;
            }

            // Behavioral check: run each test case on the round-tripped content
            var allPassed = true;
            var firstError:String = null;
            var firstExpected:String = null;
            var firstActual:String = null;
            for (idx in 0...testItems.length) {
                final item = testItems[idx];
                final restoreInput = restoreInputs[idx];
                final saveAtChoice:Int = item.saveAtChoice != null ? item.saveAtChoice : -1;
                final saveAtDialogue:Int = item.saveAtDialogue != null ? item.saveAtDialogue : -1;
                var rtOptions:InterpreterOptions = null;
                if (item.translation != null) {
                    final lang:String = item.translation;
                    final translations = Loreline.loadLocale(lang, script, file, handleFile);
                    if (translations != null) {
                        rtOptions = ({translations: translations} : InterpreterOptions);
                    }
                }
                final rtTestCase = new InterpreterTestCase(
                    file, print1, file,
                    item.beat, item.choices, rtOptions,
                    saveAtChoice, saveAtDialogue, restoreInput, item.expected
                );
                final rtTestRunner = new TestRunner(handleFile);
                rtTestRunner.runTestCase(rtTestCase, rtResult -> {
                    if (!rtResult.passed) {
                        allPassed = false;
                        if (firstError == null) {
                            firstError = rtResult.error != null ? Std.string(rtResult.error) : null;
                            firstExpected = (cast(rtResult.testCase, InterpreterTestCase)).expectedOutput;
                            firstActual = rtResult.actualOutput;
                        }
                    }
                });
            }

            if (allPassed) {
                passCount++;
                print('PASS'.green().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'roundtrip'.gray());
            } else {
                failCount++;
                hasFailedTest = true;
                print('FAIL'.red().bold() + (firstError != null ? ' - ' + firstError : '') + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'roundtrip'.gray());

                if (firstExpected != null && firstActual != null && TestRunner.compareOutput(firstExpected, firstActual) != -1) {
                    print('');
                    final normExpected = firstExpected.replace("\r\n", "\n").trim().split("\n");
                    final normActual = firstActual.replace("\r\n", "\n").trim().split("\n");
                    final ml = Std.int(Math.min(normExpected.length, normActual.length));
                    for (i in 0...ml) {
                        if (normExpected[i] != normActual[i]) {
                            print('> Unexpected output at line ${i+1}');
                            print('>  got: ' + normActual[i].red());
                            print('> need: ' + normExpected[i].yellow());
                            break;
                        }
                    }
                    print('\n');
                }
            }
        } catch (e:Any) {
            failCount++;
            hasFailedTest = true;
            print('FAIL'.red().bold() + ' - roundtrip error: $e - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'roundtrip'.gray());
        }
    }

    function testJsonRoundTrip(script:Script, file:String, crlf:Bool) {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        try {
            // toJson → stringify → parse → fromJson → toJson → stringify
            final json1 = Json.stringify(script.toJson());
            final script2 = Script.fromJson(Json.parse(json1));
            final json2 = Json.stringify(script2.toJson());

            if (json1 == json2) {
                passCount++;
                print('PASS'.green().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'json-roundtrip'.gray());
            } else {
                failCount++;
                hasFailedTest = true;
                print('FAIL'.red().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'json-roundtrip'.gray());

                // Show first difference
                final lines1 = json1.split("\n");
                final lines2 = json2.split("\n");
                final minLen = Std.int(Math.min(lines1.length, lines2.length));
                for (i in 0...minLen) {
                    if (lines1[i] != lines2[i]) {
                        print('> JSON not idempotent at line ${i + 1}');
                        print('>  json1: ' + lines1[i].red());
                        print('>  json2: ' + lines2[i].yellow());
                        break;
                    }
                }
                if (lines1.length != lines2.length) {
                    print('> Line count differs: json1=${lines1.length}, json2=${lines2.length}');
                }
                print('');
            }
        } catch (e:Any) {
            failCount++;
            hasFailedTest = true;
            print('FAIL'.red().bold() + ' - json-roundtrip error: $e - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'json-roundtrip'.gray());
        }
    }

    /**
     * Smoke-test that AstPrinter handles every node type encountered in real
     * `.lor` scripts (the default switch case throws on an unhandled type).
     * AstPrinter is pure Haxe with no target-specific behavior, so this check
     * only runs in the CLI suite — per-target runners (C++, JVM, Python, Lua,
     * C#) skip it. That accounts for the difference between the CLI test
     * count and each per-target runner's count.
     */
    function testAstPrint(script:Script, file:String, crlf:Bool) {
        final modeLabel = crlf ? 'CRLF' : 'LF';
        try {
            final output = new AstPrinter().print(script);
            if (output.length == 0) {
                failCount++;
                hasFailedTest = true;
                print('FAIL'.red().bold() + ' - empty output - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'ast-print'.gray());
            } else {
                passCount++;
                print('PASS'.green().bold() + ' - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'ast-print'.gray());
            }
        } catch (e:Any) {
            failCount++;
            hasFailedTest = true;
            print('FAIL'.red().bold() + ' - ast-print error: $e - ' + file.gray() + ' ~ '.gray() + modeLabel.gray() + ' ~ '.gray() + 'ast-print'.gray());
        }
    }

    function format(file:String) {

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);
            final script = Loreline.parse(content, file, handleFile);
            print(new Printer().print(script));
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function translate(file:String, args:Array<String>) {

        final clearIds = argFlag(args, "clear");
        final lang = argValue(args, "lang", !clearIds);
        final generateIds = argFlag(args, "auto-ids");
        // `--auto-ids-seed N` forces `--auto-ids` to use a deterministic RNG,
        // so the generated `#id` markers are stable across runs. Intended for
        // integration tests; production users don't need to set this.
        final autoIdsSeed = argValue(args, "auto-ids-seed", false);
        var format = argValue(args, "format", false);
        if (format == null || format == "") format = "lor";
        if (format != "lor" && format != "po" && format != "xliff" && format != "csv" && format != "tsv") {
            fail('Unsupported translation format: $format (expected one of: lor, po, xliff, csv, tsv)');
        }

        // Enable alternate translation formats so that an existing file can be
        // read back as the merge baseline.
        Loreline.translationFormat("po", true);
        Loreline.translationFormat("xliff", true);
        Loreline.translationFormat("csv", true);

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file))
            fail('Invalid file: $file');

        try {
            var content = File.getContent(file);
            var script = Loreline.parse(content, file, handleFile);

            if (clearIds) {
                content = AstUtils.removeLocalizationKeys(content, script);
                File.saveContent(file, content);
                print('Localization keys removed from: ' + file);
                return;
            }

            if (generateIds) {
                final rng = (autoIdsSeed != null && autoIdsSeed != "")
                    ? new loreline.Random(Std.parseFloat(autoIdsSeed))
                    : null;
                content = AstUtils.insertLocalizationKeys(content, script, true, null, rng);
                File.saveContent(file, content);
                script = Loreline.parse(content, file, handleFile);
            }

            final basePath = file.uSubstring(0, file.uLength() - 4);
            final translationPath = basePath + "." + lang + "." + format;

            var existingTranslations:Map<String, Node.NStringLiteral> = null;
            if (FileSystem.exists(translationPath)) {
                final transContent = File.getContent(translationPath);
                if (transContent.trim().length > 0) {
                    final lorBody = (format == "lor")
                        ? transContent
                        : convertExistingToLor(transContent, format, lang);
                    if (lorBody != null && lorBody.trim().length > 0) {
                        final transScript = Loreline.parse(lorBody, translationPath, handleFile);
                        if (transScript != null)
                            existingTranslations = AstUtils.extractTranslations(transScript);
                    }
                }
            }

            var output = Loreline.generateTranslationFile(script, existingTranslations, format, lang);
            // Match the line-ending style of the existing translation file (if any),
            // else of the source. The generators always emit `\n`; convert to `\r\n`
            // when the surrounding context is CRLF, so a CRLF project stays CRLF.
            final styleProbe = FileSystem.exists(translationPath)
                ? File.getContent(translationPath)
                : content;
            if (styleProbe.indexOf("\r\n") >= 0) {
                output = output.split("\r\n").join("\n").split("\n").join("\r\n");
            }
            File.saveContent(translationPath, output);

            print('Translation file ' + (existingTranslations != null ? 'updated' : 'created') + ': ' + translationPath);
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function convertExistingToLor(content:String, format:String, locale:String):String {
        return switch (format) {
            case "po":    loreline.translation.PoTranslation.toLoreline(content, locale);
            case "xliff": loreline.translation.XliffTranslation.toLoreline(content, locale);
            case "csv":   loreline.translation.CsvTranslation.toLoreline(content, locale);
            case "tsv":   loreline.translation.CsvTranslation.tsvToLoreline(content, locale);
            case _: null;
        }
    }

    function play(file:String) {

        print("");

        if (!FileSystem.exists(file) || FileSystem.isDirectory(file)) {
            fail('Invalid file: $file');
        }

        try {
            final content = File.getContent(file);

            final script = Loreline.parse(content, file, handleFile);

            errorInStdOut = true;

            Loreline.play(
                script,
                handleDialogue,
                handleChoice,
                _ -> {
                    // Finished script execution
                }
            );
        }
        catch (e:Any) {
            #if debug
            if (e is Error) {
                printStackTrace(false, (e:Error).stack);
                error((e:Error).toString());
            }
            else {
                printStackTrace(false, CallStack.exceptionStack());
            }
            #end
            fail(e, file);
        }

    }

    function handleDialogue(interpreter:Interpreter, character:String, text:String, tags:Array<TextTag>, callback:()->Void):Void {

        final multiline = text.contains("\n");
        if (character != null) {
            character = interpreter.getCharacterField(character, 'name') ?? character;

            var tagItems = [];
            for (tag in tags) {
                if (tag.offset == 0 && !tag.closing) {
                    tagItems.push(("<" + tag.value + ">").cyan());
                }
            }
            var tagItemsText = "";
            if (tagItems.length > 0) {
                tagItemsText = tagItems.join("");
                if (!multiline) {
                    tagItemsText += " ";
                }
            }
            if (multiline) {
                text = "\n  " + text.replace("\n", "\n  ").rtrim();
            }
            type(
                " " + (character + ":").cyan().bold() + " " + tagItemsText + text.green()
            );
        }
        else {
            if (multiline) {
                text = text.replace("\n", "\n ").rtrim();
            }
            type(
                " " + text.cyan().italic()
            );
        }

        lastCharacter = character;

        print('');
        if (sentenceDelay > 0) {
            Sys.sleep(sentenceDelay);
        }

        callback();

    }

    function handleChoice(interpreter:Interpreter, options:Array<ChoiceOption>, callback:(index:Int)->Void):Void {

        lastCharacter = null;

        var index = 1;
        for (opt in options) {
            if (opt.enabled) {
                type(" " + '$index.'.yellow() + " " + opt.text);
                index++;
            }
            else if (showDisabled) {
                type((" " + '$index.' + " " + opt.text).gray());
                index++;
            }
        }

        print('');

        do {
            Sys.stdout().writeString(" " + ">".yellow() + " ");
            final input = Std.parseInt(Sys.stdin().readLine());
            if (input != null) {
                var index = 1;
                var i = 0;
                for (opt in options) {
                    if (opt.enabled || showDisabled) {
                        if (input == index) {
                            print('');
                            callback(i);
                            return;
                        }
                        index++;
                    }
                    i++;
                }
            }
        }
        while (true);

    }

    function argValue(args:Array<String>, name:String, required:Bool = false):String {

        var index = args.indexOf('--$name');

        if (index == -1) {
            if (required) {
                fail('Argument --$name is required');
            }
            return null;
        }

        if (index + 1 >= args.length) {
            fail('A value is required after --$name argument.');
        }

        var value = args[index + 1];

        return value;

    }

    function argFlag(args:Array<String>, name:String):Bool {

        var index = args.indexOf('--$name');

        if (index == -1) {
            return false;
        }

        return true;

    }

    /**
        Splits text into an array of "characters", where each ANSI sequence is kept with its following character.
        @param text The input text that may contain ANSI escape sequences
        @return Array<String> Array where each element is either a single character or an ANSI sequence + character
    **/
    static function splitWithAnsi(text:String):Array<String> {
        final result:Array<String> = [];
        static final ANSI = ~/[\x1B\x9B](?:[@-Z\\-_]|\[[0-?]*[ -\/]*[@-~]|\].*?(?:\x07|\x1B\\))/g; // Comprehensive ANSI pattern

        var currentIndex:Int = 0;
        var lastMatchEnd:Int = 0;

        // Helper to add non-ANSI characters
        inline function addPlainChars(start:Int, end:Int) {
            #if neko
            var chars = neko.Utf8.sub(text, start, end - start);
            #else
            var chars = text.substring(start, end);
            #end
            for (i in 0...chars.length) {
                #if neko
                result.push(neko.Utf8.sub(chars, i, 1));
                #else
                result.push(chars.charAt(i));
                #end
            }
        }

        // Process the string looking for ANSI sequences
        while (ANSI.matchSub(text, currentIndex)) {
            var matchPos = ANSI.matchedPos();

            // Add any plain characters before the ANSI sequence
            if (matchPos.pos > lastMatchEnd) {
                addPlainChars(lastMatchEnd, matchPos.pos);
            }

            // Get the ANSI sequence
            #if neko
            var ansiSeq = neko.Utf8.sub(text, matchPos.pos, matchPos.len);
            #else
            var ansiSeq = text.substr(matchPos.pos, matchPos.len);
            #end

            // Look ahead for any following ANSI sequences
            var nextPos = matchPos.pos + matchPos.len;
            var combinedAnsi = ansiSeq;
            while (ANSI.matchSub(text, nextPos)) {
                var nextMatch = ANSI.matchedPos();
                if (nextMatch.pos == nextPos) {
                    // Adjacent ANSI sequence found
                    #if neko
                    var nextSeq = neko.Utf8.sub(text, nextMatch.pos, nextMatch.len);
                    #else
                    var nextSeq = text.substr(nextMatch.pos, nextMatch.len);
                    #end
                    combinedAnsi += nextSeq;
                    nextPos = nextMatch.pos + nextMatch.len;
                }
                else {
                    break;
                }
            }

            // Get the character after the ANSI sequence(s)
            if (nextPos < text.length) {
                #if neko
                result.push(combinedAnsi + neko.Utf8.sub(text, nextPos, 1));
                #else
                result.push(combinedAnsi + text.charAt(nextPos));
                #end
                lastMatchEnd = nextPos + 1;
            }
            else {
                // Handle case where ANSI sequence is at the end
                result.push(combinedAnsi);
                lastMatchEnd = nextPos;
            }

            currentIndex = lastMatchEnd;
        }

        // Add any remaining characters after the last ANSI sequence
        if (lastMatchEnd < text.length) {
            addPlainChars(lastMatchEnd, text.length);
        }

        return result;

    }

    function type(str:String, delay:Float = -1):Void {
        if (delay == -1) {
            delay = this.typeDelay;
        }
        if (delay > 0) {
            for (part in splitWithAnsi(str)) {
                Sys.stdout().writeString(part);
                Sys.stdout().flush();
                Sys.sleep(delay);
            }
            Sys.stdout().writeString('\n');
            Sys.stdout().flush();
        }
        else {
            print(str);
            Sys.stdout().flush();
        }
    }

    function print(str:String):Void {
        Sys.stdout().writeString(str + '\n');
    }

    function error(err:Any, ?file:String):Void {
        inline function write(str:String) {
            if (errorInStdOut) {
                Sys.stdout().writeString(str);
            }
            else {
                Sys.stderr().writeString(str);
            }
        }
        if (err is Error) {
            final e:Error = cast err;
            write(e.message.red());
            write(' ');
            if (file != null && file.trim().length > 0) {
                write(
                    (file.trim() + ':' + e.pos.line + ':' + e.pos.column).gray()
                );
            }
            write('\n');
        }
        else {
            write(Std.string(err).red() + '\n');
        }
    }

    function fail(?message:String, ?file:String):Void {
        if (message != null) {
            error(message, file);
            error('');
        }
        Sys.exit(1);
    }

    function printStackTrace(returnOnly:Bool = false, ?stack:Array<StackItem>):String {

        var result = new loreline.Utf8.Utf8Buf();

        inline function print(data:Dynamic) {
            if (!returnOnly) {
                #if cs
                trace(data);
                #elseif android
                trace('' + data);
                #elseif sys
                this.error('' + data);
                #else
                trace(data);
                #end
            }
            result.add(data);
            result.addChar('\n'.code);
        }

        if (stack == null)
            stack = CallStack.callStack();

        // Reverse stack
        var reverseStack = [].concat(stack);
        reverseStack.reverse();
        reverseStack.pop(); // Remove last element, no need to display it

        // Print stack trace and error
        for (item in reverseStack) {
            print(stackItemToString(item));
        }

        return result.toString();

    }

    function stackItemToString(item:StackItem):String {
        static final pattern = ~/loreline\.([a-zA-Z]+)(?:\.[a-zA-Z]+)*::/;

        var str:String = "";
        switch (item) {
            case CFunction:
                str = "a C function";
            case Module(m):
                str = "module " + m;
            case FilePos(itm, file, line, column):
                if (itm != null) {
                    str = stackItemToString(itm);
                    str += ' ';
                }
                str += file;
                if (pattern.match(file)) {
                    var name = pattern.matched(1);
                    name = switch name {
                        case 'ParseError': 'Parser';
                        case _: name;
                    }
                    str += ' src/loreline/' + name + '.hx';
                }
                #if (!cpp || HXCPP_STACK_LINE)
                str += ":";
                str += line;
                #end
            case Method(cname, meth):
                str += (cname);
                str += (".");
                str += (meth);
            #if (haxe_ver >= "3.1.0")
            case LocalFunction(n):
            #else
            case Lambda(n):
            #end
                str += ("local function #");
                str += (n);
        }

        return str;

    }

}