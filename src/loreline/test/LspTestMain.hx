package loreline.test;

// The language server reads files with the sys API, which the GDScript runtime
// does not have
#if !gdscript

/**
 * Runs the language server tests on the targets the CLI does not run on (JS,
 * C++): the protocol tests of LspTests, and the files of `test-lsp/`, embedded at
 * compile time. Built on its own (build-lsp-test.hxml), so that the language
 * server stays out of the runtime exports.
 */
class LspTestMain {

    static function main() {

        var passCount = 0;
        var failCount = 0;

        final pass = name -> {
            passCount++;
            println('PASS - ' + name);
        };
        final fail = (name, error) -> {
            failCount++;
            println('FAIL - ' + name + ' ' + error);
        };

        LspTests.run(pass, fail);

        // Test files are at the top of the folder, the files they import below
        final files = LspTestFiles.embed('test-lsp');
        final fileTests = new LspFileTests(path -> files.get(path));
        final paths = [for (path in files.keys()) if (path.indexOf('/') == -1) path];
        paths.sort(Reflect.compare);
        for (path in paths) {
            fileTests.runFile(path, pass, fail);
        }

        println('');
        if (failCount > 0) {
            println('  $failCount of ${passCount + failCount} language server tests failed');
        }
        else {
            println('  All $passCount language server tests passed');
        }

        exit(failCount > 0 ? 1 : 0);

    }

    static function println(line:String) {
        #if sys
        Sys.println(line);
        #elseif js
        js.Syntax.code("console.log({0})", line);
        #end
    }

    static function exit(code:Int) {
        #if sys
        Sys.exit(code);
        #elseif js
        // Run with node, with or without hxnodejs
        js.Syntax.code("process.exitCode = {0}", code);
        #end
    }

}

#end
