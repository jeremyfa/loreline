package loreline.test;

// The language server reads files with the sys API, which the GDScript runtime
// does not have
#if !gdscript

/**
 * Runs the language server tests. Built on its own (build-lsp-test.hxml), so
 * that the language server stays out of the runtime exports and of the CLI.
 */
class LspTestMain {

    static function main() {

        var passCount = 0;
        var failCount = 0;

        LspDefinitionTests.run(
            name -> {
                passCount++;
                println('PASS - ' + name);
            },
            (name, error) -> {
                failCount++;
                println('FAIL - ' + name + ' ' + error);
            }
        );

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
