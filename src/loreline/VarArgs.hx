package loreline;

/**
 * Reflect.makeVarArgs and Reflect.callMethod, with every argument kept on Lua.
 *
 * The Lua version of Reflect.makeVarArgs in the Haxe standard library counts
 * the arguments up to the last one that is not nil: `f(1, nil)` gives `[1]`, and
 * `f(nil, nil)` gives `[]`. The real count is `select('#', ...)`, used by make.
 * Its Reflect.callMethod with no object and no argument calls `f(nil)`, which
 * the count of make would see as one null argument: call passes none.
 */
class VarArgs {

    public static function make(f:(args:Array<Dynamic>)->Dynamic):Dynamic {
        #if lua
        return untyped __lua__("function(...)
            local n = select('#', ...)
            local a = {...}
            local b = {}
            for i = 1, n do
                b[i - 1] = a[i]
            end
            return {0}(_hx_tab_array(b, n))
        end", f);
        #else
        return Reflect.makeVarArgs(f);
        #end
    }

    public static function call(o:Dynamic, f:haxe.Constraints.Function, args:Array<Dynamic>):Dynamic {
        #if lua
        if (o == null && args.length == 0) {
            final fn:()->Dynamic = cast f;
            return fn();
        }
        #end
        return Reflect.callMethod(o, f, args);
    }

}
