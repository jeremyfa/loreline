package loreline.test;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;
#end

/**
 * The files of `test-lsp/`, read at compile time, for the targets that have no
 * file system (JS in a web worker). Only the language server test build uses
 * it: nothing of it reaches the runtime exports.
 */
class LspTestFiles {

    /**
     * Every file of the folder, keyed by path relative to it.
     * @param dir Folder, relative to the directory the build runs from
     */
    public static macro function embed(dir:String):Expr {
        final entries:Array<Expr> = [];
        function walk(relative:String) {
            final full = relative == '' ? dir : dir + '/' + relative;
            final names = FileSystem.readDirectory(full);
            names.sort(Reflect.compare);
            for (name in names) {
                final path = relative == '' ? name : relative + '/' + name;
                if (FileSystem.isDirectory(dir + '/' + path)) {
                    walk(path);
                }
                else if (StringTools.endsWith(name, '.lor')) {
                    // Rebuild when a test file changes
                    Context.registerModuleDependency(Context.getLocalModule(), dir + '/' + path);
                    final content = File.getContent(dir + '/' + path);
                    entries.push(macro $v{path} => $v{content});
                }
            }
        }
        walk('');
        return macro ([$a{entries}]:Map<String, String>);
    }

}
