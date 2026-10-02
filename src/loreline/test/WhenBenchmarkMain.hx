package loreline.test;

// The benchmark needs Sys and haxe.Timer: it is not part of the GDScript build
#if !gdscript

/**
 * Entry point of the `when` benchmark on its own, for the targets that don't run
 * the CLI (`build-bench-js.hxml`).
 */
class WhenBenchmarkMain {

    static function main() {
        if (!WhenBenchmark.runFromArgs(Sys.args(), line -> Sys.println(line))) {
            Sys.println(WhenBenchmark.USAGE);
            Sys.exit(1);
        }
    }

}

#end
