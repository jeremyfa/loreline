package loreline;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.io.File;
#end

class CliMacros {

    public static macro function lorelineVersion():Expr {

        #if !display
        return macro $v{haxe.Json.parse(File.getContent('haxelib.json')).version};
        #else
        return macro "";
        #end

    }

    public static macro function gitCommitHash():Expr {

        final commitHash = _gitCommitHash();
        return macro $v{commitHash};

    }

    public static macro function gitCommitShortHash():Expr {

        var commitHash:String = _gitCommitHash();
        if (commitHash != null && commitHash.length > 7) {
            commitHash = commitHash.substr(0, 7);
        }
        return macro $v{commitHash};

    }

#if macro

    static function _gitCommitHash():String {

        static var _commitHash:String = null;

        if (_commitHash == null) {
            #if !display
            var process = new sys.io.Process('git', ['rev-parse', 'HEAD']);
            if (process.exitCode() != 0) {
                var message = process.stderr.readAll().toString();
                var pos = Context.currentPos();
                Context.error("Cannot execute `git rev-parse HEAD`. " + message, pos);
            }
            _commitHash = process.stdout.readLine();
            #else
            _commitHash = "";
            #end
        }

        return _commitHash;

    }

#end

}
