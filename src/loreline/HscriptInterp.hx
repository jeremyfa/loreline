/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package loreline;

// This is a modified version of original `hscript.Interp`, which has better support
// of loreline types and objects. It also get access to the loreline interpreter context.
// The rest of hscript behaviour stays unchanged

import haxe.Constraints.IMap;
import haxe.PosInfos;
import hscript.Expr;

private enum Stop {
    SBreak;
    SContinue;
    SReturn;
}

class HscriptInterp {

    public var variables : Map<String,Dynamic>;
    var locals : Map<String,{ r : Dynamic }>;
    var binops : Map<String, Expr -> Expr -> Dynamic >;

    var depth : Int;
    var inTry : Bool;
    var declared : Array<{ n : String, old : { r : Dynamic } }>;
    var returnValue : Dynamic;

    #if hscriptPos
    var curExpr : Expr;
    #end

    final interpreter:Interpreter;

    public function new(interpreter:Interpreter) {
        this.interpreter = interpreter;
        locals = new Map();
        declared = new Array();
        resetVariables();
        initOps();
    }

    private function resetVariables(){
        variables = new Map<String,Dynamic>();
        variables.set("null",null);
        variables.set("true",true);
        variables.set("false",false);
        variables.set("trace", Reflect.makeVarArgs(function(el) {
            var inf = posInfos();
            var v = el.shift();
            if( el.length > 0 ) inf.customParams = el;
            haxe.Log.trace(Std.string(v), inf);
        }));
    }

    public function posInfos(): PosInfos {
        #if hscriptPos
            if (curExpr != null)
                return cast { fileName : curExpr.origin, lineNumber : curExpr.line };
        #end
        return cast { fileName : "hscript", lineNumber : 0 };
    }

    function initOps() {
        var me = this;
        binops = new Map();
        binops.set("+",function(e1,e2) return me.expr(e1) + me.expr(e2));
        binops.set("-",function(e1,e2) return me.expr(e1) - me.expr(e2));
        binops.set("*",function(e1,e2) return me.expr(e1) * me.expr(e2));
        binops.set("/",function(e1,e2) return me.expr(e1) / me.expr(e2));
        binops.set("%",function(e1,e2) return me.expr(e1) % me.expr(e2));
        binops.set("&",function(e1,e2) return me.expr(e1) & me.expr(e2));
        binops.set("|",function(e1,e2) return me.expr(e1) | me.expr(e2));
        binops.set("^",function(e1,e2) return me.expr(e1) ^ me.expr(e2));
        binops.set("<<",function(e1,e2) return me.expr(e1) << me.expr(e2));
        binops.set(">>",function(e1,e2) return me.expr(e1) >> me.expr(e2));
        binops.set(">>>",function(e1,e2) return me.expr(e1) >>> me.expr(e2));
        binops.set("==",function(e1,e2) return me.expr(e1) == me.expr(e2));
        binops.set("!=",function(e1,e2) return me.expr(e1) != me.expr(e2));
        // Temporary variables are needed here to work around a Haxe C# target quirk:
        // inline Dynamic comparisons generate Runtime.compare() calls with incorrect boxing,
        // causing "Cannot compare System.String and System.Int32" errors.
        binops.set(">=",function(e1,e2) { var v1 = me.expr(e1); var v2 = me.expr(e2); return v1 >= v2; });
        binops.set("<=",function(e1,e2) { var v1 = me.expr(e1); var v2 = me.expr(e2); return v1 <= v2; });
        binops.set(">",function(e1,e2) { var v1 = me.expr(e1); var v2 = me.expr(e2); return v1 > v2; });
        binops.set("<",function(e1,e2) { var v1 = me.expr(e1); var v2 = me.expr(e2); return v1 < v2; });
        binops.set("||",function(e1,e2) return me.expr(e1) == true || me.expr(e2) == true);
        binops.set("&&",function(e1,e2) return me.expr(e1) == true && me.expr(e2) == true);
        binops.set("=",assign);
        binops.set("...",function(e1,e2) return new IntIterator(me.expr(e1),me.expr(e2)));
        binops.set("is",function(e1,e2) return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (me.expr(e1), me.expr(e2)));
        assignOp("+=",function(v1:Dynamic,v2:Dynamic) return v1 + v2);
        assignOp("-=",function(v1:Float,v2:Float) return v1 - v2);
        assignOp("*=",function(v1:Float,v2:Float) return v1 * v2);
        assignOp("/=",function(v1:Float,v2:Float) return v1 / v2);
        assignOp("%=",function(v1:Float,v2:Float) return v1 % v2);
        assignOp("&=",function(v1,v2) return v1 & v2);
        assignOp("|=",function(v1,v2) return v1 | v2);
        assignOp("^=",function(v1,v2) return v1 ^ v2);
        assignOp("<<=",function(v1,v2) return v1 << v2);
        assignOp(">>=",function(v1,v2) return v1 >> v2);
        assignOp(">>>=",function(v1,v2) return v1 >>> v2);
    }

    function setVar( name : String, v : Dynamic ) {

        if (!variables.exists(name)) {
            Objects.setField(interpreter, interpreter.topLevelState.fields, name, v);
        }
        else {
            throw "Invalid assign";
        }

        return v;
    }

    function assign( e1 : Expr, e2 : Expr ) : Dynamic {
        var v = expr(e2);
        switch( hscript.Tools.expr(e1) ) {
        case EIdent(id):
            var l = locals.get(id);
            if( l == null )
                setVar(id,v)
            else
                l.r = v;
        case EField(e,f):
            v = set(expr(e),f,v);
        case EArray(e, index):
            var arr:Dynamic = expr(e);
            var index:Dynamic = expr(index);
            if (Arrays.isArray(arr)) {
                Arrays.arraySet(arr, index, v);
            }
            else if (Objects.isFields(arr)) {
                Objects.setField(interpreter, arr, index, v);
            }
            else if (isMap(arr)) {
                setMapValue(arr, index, v);
            }
            else {
                arr[index] = v;
            }

        default:
            error(EInvalidOp("="));
        }
        return v;
    }

    function assignOp( op, fop : Dynamic -> Dynamic -> Dynamic ) {
        var me = this;
        binops.set(op,function(e1,e2) return me.evalAssignOp(op,fop,e1,e2));
    }

    function evalAssignOp(op,fop,e1,e2) : Dynamic {
        var v;
        switch( hscript.Tools.expr(e1) ) {
        case EIdent(id):
            var l = locals.get(id);
            v = fop(expr(e1),expr(e2));
            if( l == null )
                setVar(id,v)
            else
                l.r = v;
        case EField(e,f):
            var obj = expr(e);
            v = fop(get(obj,f),expr(e2));
            v = set(obj,f,v);
        case EArray(e, index):
            var arr:Dynamic = expr(e);
            var index:Dynamic = expr(index);
            if (Arrays.isArray(arr)) {
                v = fop(Arrays.arrayGet(arr, index), expr(e2));
                Arrays.arraySet(arr, index, v);
            }
            else if (Objects.isFields(arr)) {
                v = fop(Objects.getField(interpreter, arr, index), expr(e2));
                Objects.setField(interpreter, arr, index, v);
            }
            else if (isMap(arr)) {
                v = fop(getMapValue(arr, index), expr(e2));
                setMapValue(arr, index, v);
            }
            else {
                v = fop(arr[index],expr(e2));
                arr[index] = v;
            }
        default:
            return error(EInvalidOp(op));
        }
        return v;
    }

    function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
        #if hscriptPos
        curExpr = e;
        var e = e.e;
        #end
        switch(e) {
        case EIdent(id):
            var l = locals.get(id);
            var v : Dynamic = (l == null) ? resolve(id) : l.r;
            if( prefix ) {
                v += delta;
                if( l == null ) setVar(id,v) else l.r = v;
            } else
                if( l == null ) setVar(id,v + delta) else l.r = v + delta;
            return v;
        case EField(e,f):
            var obj = expr(e);
            var v : Dynamic = get(obj,f);
            if( prefix ) {
                v += delta;
                set(obj,f,v);
            } else
                set(obj,f,v + delta);
            return v;
        case EArray(e, index):
            var arr:Dynamic = expr(e);
            var index:Dynamic = expr(index);
            if (Arrays.isArray(arr)) {
                var v:Dynamic = Arrays.arrayGet(arr, index);
                if (prefix) {
                    v += delta;
                    Arrays.arraySet(arr, index, v);
                }
                else {
                    Arrays.arraySet(arr, index, v + delta);
                }
                return v;
            }
            else if (Objects.isFields(arr)) {
                var v:Dynamic = Objects.getField(interpreter, arr, index);
                if (prefix) {
                    v += delta;
                    Objects.setField(interpreter, arr, index, v);
                }
                else {
                    Objects.setField(interpreter, arr, index, v + delta);
                }
                return v;
            }
            else if (isMap(arr)) {
                var v = getMapValue(arr, index);
                if (prefix) {
                    v += delta;
                    setMapValue(arr, index, v);
                }
                else {
                    setMapValue(arr, index, v + delta);
                }
                return v;
            }
            else {
                var v = arr[index];
                if( prefix ) {
                    v += delta;
                    arr[index] = v;
                } else
                    arr[index] = v + delta;
                return v;
            }
        default:
            return error(EInvalidOp((delta > 0)?"++":"--"));
        }
    }

    public function execute( expr : Expr ) : Dynamic {
        depth = 0;
        locals = new Map();
        declared = new Array();
        return exprReturn(expr);
    }

    function exprReturn(e) : Dynamic {
        try {
            return expr(e);
        } catch( e : Stop ) {
            switch( e ) {
            case SBreak: throw "Invalid break";
            case SContinue: throw "Invalid continue";
            case SReturn:
                var v = returnValue;
                returnValue = null;
                return v;
            }
        }
        return null;
    }

    function duplicate<T>( h : Map<String,T> ) {
        var h2 = new Map();
        for( k in h.keys() )
            h2.set(k,h.get(k));
        return h2;
    }

    function restore( old : Int ) {
        while( declared.length > old ) {
            var d = declared.pop();
            locals.set(d.n,d.old);
        }
    }

    inline function error(e : #if hscriptPos ErrorDef #else Error #end, rethrow=false ) : Dynamic {
        #if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
        if( rethrow ) this.rethrow(e) else throw e;
        return null;
    }

    inline function rethrow( e : Dynamic ) {
        #if hl
        hl.Api.rethrow(e);
        #else
        throw e;
        #end
    }

    function resolve( id : String ) : Dynamic {
        var v = variables.get(id);
        if( v == null && !variables.exists(id) ) {

            // Look for state fields
            if (Objects.fieldExists(interpreter, interpreter.topLevelState.fields, id)) {
                return Objects.getField(interpreter, interpreter.topLevelState.fields, id);
            }

            // Look for characters
            if (interpreter.topLevelCharacters.exists(id)) {
                return interpreter.topLevelCharacters.get(id).fields;
            }

            // Look for functions
            if (interpreter.topLevelFunctions.exists(id)) {
                return interpreter.topLevelFunctions.get(id);
            }

            error(EUnknownVariable(id));
        }
        return v;
    }

    public function expr( e : Expr ) : Dynamic {
        #if hscriptPos
        curExpr = e;
        var e = e.e;
        #end
        switch( e ) {
        case EConst(c):
            switch( c ) {
            case CInt(v): return v;
            case CFloat(f): return f;
            case CString(s): return s;
            }
        case EIdent(id):
            var l = locals.get(id);
            if( l != null )
                return l.r;
            return resolve(id);
        case EVar(n,_,e):
            declared.push({ n : n, old : locals.get(n) });
            locals.set(n,{ r : (e == null)?null:expr(e) });
            return null;
        case EParent(e):
            return expr(e);
        case EBlock(exprs):
            var old = declared.length;
            var v = null;
            for( e in exprs )
                v = expr(e);
            restore(old);
            return v;
        case EField(e,f):
            return get(expr(e),f);
        case EBinop(op,e1,e2):
            var fop = binops.get(op);
            if( fop == null ) error(EInvalidOp(op));
            return fop(e1,e2);
        case EUnop(op,prefix,e):
            switch(op) {
            case "!":
                return expr(e) != true;
            case "-":
                return -expr(e);
            case "++":
                return increment(e,prefix,1);
            case "--":
                return increment(e,prefix,-1);
            case "~":
                return ~expr(e);
            default:
                error(EInvalidOp(op));
            }
        case ECall(e,params):
            var args = new Array();
            for( p in params )
                args.push(expr(p));

            switch( hscript.Tools.expr(e) ) {
            case EField(e,f):
                var obj = expr(e);
                if( obj == null ) error(EInvalidAccess(f));
                return fcall(obj,f,args);
            default:
                return call(null,expr(e),args);
            }
        case EIf(econd,e1,e2):
            return if( expr(econd) == true ) expr(e1) else if( e2 == null ) null else expr(e2);
        case EWhile(econd,e):
            whileLoop(econd,e);
            return null;
        case EDoWhile(econd,e):
            doWhileLoop(econd,e);
            return null;
        case EFor(v,it,e):
            forLoop(v,it,e);
            return null;
        case EBreak:
            throw SBreak;
        case EContinue:
            throw SContinue;
        case EReturn(e):
            returnValue = e == null ? null : expr(e);
            throw SReturn;
        case EFunction(params,fexpr,name,_):
            var capturedLocals = duplicate(locals);
            var me = this;
            var hasOpt = false, minParams = 0;
            for( p in params )
                if( p.opt || p.value != null )
                    hasOpt = true;
                else
                    minParams++;
            var f = function(args:Array<Dynamic>) {
                if( ( (args == null) ? 0 : args.length ) != params.length ) {
                    if( args.length < minParams ) {
                        var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
                        if( name != null ) str += " for function '" + name+"'";
                        error(ECustom(str));
                    }
                    // make sure mandatory args are forced
                    var args2 = [];
                    var extraParams = args.length - minParams;
                    var pos = 0;
                    for( p in params )
                        if( p.opt || p.value != null ) {
                            if( extraParams > 0 ) {
                                args2.push(args[pos++]);
                                extraParams--;
                            } else
                                args2.push(p.value != null ? me.expr(p.value) : null);
                        } else
                            args2.push(args[pos++]);
                    args = args2;
                }
                var old = me.locals, depth = me.depth;
                me.depth++;
                me.locals = me.duplicate(capturedLocals);
                for( i in 0...params.length )
                    me.locals.set(params[i].name,{ r : args[i] });
                var r = null;
                var oldDecl = declared.length;
                if( inTry )
                    try {
                        r = me.exprReturn(fexpr);
                    } catch( e : Dynamic ) {
                        restore(oldDecl);
                        me.locals = old;
                        me.depth = depth;
                        #if neko
                        neko.Lib.rethrow(e);
                        #else
                        throw e;
                        #end
                    }
                else
                    r = me.exprReturn(fexpr);
                restore(oldDecl);
                me.locals = old;
                me.depth = depth;
                return r;
            };
            var f = Reflect.makeVarArgs(f);
            if( name != null ) {
                if( depth == 0 ) {
                    // global function
                    variables.set(name, f);
                } else {
                    // function-in-function is a local function
                    declared.push( { n : name, old : locals.get(name) } );
                    var ref = { r : f };
                    locals.set(name, ref);
                    capturedLocals.set(name, ref); // allow self-recursion
                }
            }
            return f;
        case EArrayDecl(arr):
            if( arr.length > 0 && hscript.Tools.expr(arr[0]).match(EBinop("=>", _)) ) {
                var keys = [];
                var values = [];
                for( e in arr ) {
                    switch(hscript.Tools.expr(e)) {
                    case EBinop("=>", eKey, eValue):
                        keys.push(expr(eKey));
                        values.push(expr(eValue));
                    default:
                        #if hscriptPos
                        curExpr = e;
                        #end
                        error(ECustom("Invalid map key=>value expression"));
                    }
                }
                return makeMap(keys,values);
            } else {
                var a = new Array();
                for( e in arr )
                    a.push(expr(e));
                return a;
            }
        case EArray(e, index):
            var arr:Dynamic = expr(e);
            var index:Dynamic = expr(index);
            if (Arrays.isArray(arr)) {
                return Arrays.arrayGet(arr, index);
            }
            else if (Objects.isFields(arr)) {
                return Objects.getField(interpreter, arr, index);
            }
            else if( isMap(arr) )
                return getMapValue(arr, index);
            return arr[index];
        case ENew(cl,params):
            var a = new Array();
            for( e in params )
                a.push(expr(e));
            return cnew(cl,a);
        case EThrow(e):
            throw expr(e);
        case ETry(e,n,_,ecatch):
            var old = declared.length;
            var oldTry = inTry;
            try {
                inTry = true;
                var v : Dynamic = expr(e);
                restore(old);
                inTry = oldTry;
                return v;
            } catch( err : Stop ) {
                inTry = oldTry;
                throw err;
            } catch( err : Dynamic ) {
                // restore vars
                restore(old);
                inTry = oldTry;
                // declare 'v'
                declared.push({ n : n, old : locals.get(n) });
                locals.set(n,{ r : err });
                var v : Dynamic = expr(ecatch);
                restore(old);
                return v;
            }
        case EObject(fl):
            var o = Objects.createFields(interpreter);
            for( f in fl )
                Objects.setField(interpreter, o, f.name, expr(f.e));
            return o;
        case ETernary(econd,e1,e2):
            return if( expr(econd) == true ) expr(e1) else expr(e2);
        case ESwitch(e, cases, def):
            var val : Dynamic = expr(e);
            var match = false;
            for( c in cases ) {
                for( v in c.values )
                    if( expr(v) == val ) {
                        match = true;
                        break;
                    }
                if( match ) {
                    val = expr(c.expr);
                    break;
                }
            }
            if( !match )
                val = def == null ? null : expr(def);
            return val;
        case EMeta(_, _, e):
            return expr(e);
        case ECheckType(e,_):
            return expr(e);
        }
        return null;
    }

    function doWhileLoop(econd,e) {
        var old = declared.length;
        do {
            if( !loopRun(() -> expr(e)) )
                break;
        }
        while( expr(econd) == true );
        restore(old);
    }

    function whileLoop(econd,e) {
        var old = declared.length;
        while( expr(econd) == true ) {
            if( !loopRun(() -> expr(e)) )
                break;
        }
        restore(old);
    }

    function makeIterator( v : Dynamic ) : Iterator<Dynamic> {
        #if ((flash && !flash9) || (php && !php7 && haxe_ver < '4.0.0'))
        if ( v.iterator != null ) v = v.iterator();
        #elseif js
        // don't use try/catch (very slow)
        if( v is Array )
            return (v : Array<Dynamic>).iterator();
        if (Arrays.isArray(v)) {
            return Arrays.getIterator(v);
        }
        if( v.iterator != null ) v = v.iterator();
        #else
        if (Arrays.isArray(v)) {
            return Arrays.getIterator(v);
        }
        try v = v.iterator() catch( e : Dynamic ) {};
        #end
        if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
        return v;
    }

    function forLoop(n,it,e) {
        var old = declared.length;
        declared.push({ n : n, old : locals.get(n) });
        var it = makeIterator(expr(it));
        while( it.hasNext() ) {
            locals.set(n,{ r : it.next() });
            if( !loopRun(() -> expr(e)) )
                break;
        }
        restore(old);
    }

    inline function loopRun( f : Void -> Void ) {
        var cont = true;
        try {
            f();
        } catch( err : Stop ) {
            switch( err ) {
            case SContinue:
            case SBreak:
                cont = false;
            case SReturn:
                throw err;
            }
        }
        return cont;
    }

    inline function isMap(o:Dynamic):Bool {
        return (o is IMap);
    }

    inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
        return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
    }

    inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
        cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
    }

    function makeMap( keys : Array<Dynamic>, values : Array<Dynamic> ) : Dynamic {
        var isAllString:Bool = true;
        var isAllInt:Bool = true;
        var isAllObject:Bool = true;
        var isAllEnum:Bool = true;
        for( key in keys ) {
            isAllString = isAllString && (key is String);
            isAllInt = isAllInt && (key is Int);
            isAllObject = isAllObject && Reflect.isObject(key);
            isAllEnum = isAllEnum && Reflect.isEnumValue(key);
        }
        if( isAllInt ) {
            var m = new Map<Int,Dynamic>();
            for( i => key in keys )
                m.set(key, values[i]);
            return m;
        }
        if( isAllString ) {
            var m = new Map<String,Dynamic>();
            for( i => key in keys )
                m.set(key, values[i]);
            return m;
        }
        if( isAllEnum ) {
            var m = new haxe.ds.EnumValueMap<Dynamic,Dynamic>();
            for( i => key in keys )
                m.set(key, values[i]);
            return m;
        }
        if( isAllObject ) {
            var m = new Map<{},Dynamic>();
            for( i => key in keys )
                m.set(key, values[i]);
            return m;
        }
        error(ECustom("Invalid map keys "+keys));
        return null;
    }

    function get( o : Dynamic, f : String ) : Dynamic {
        if ( o == null ) error(EInvalidAccess(f));

        if (Objects.isFields(o)) {
            return Objects.getField(interpreter, o, f);
        }

        return {
            #if php
                // https://github.com/HaxeFoundation/haxe/issues/4915
                try {
                    Reflect.getProperty(o, f);
                } catch (e:Dynamic) {
                    Reflect.field(o, f);
                }
            #else
                Reflect.getProperty(o, f);
            #end
        }
    }

    function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
        if( o == null ) error(EInvalidAccess(f));

        if (Objects.isFields(o)) {
            Objects.setField(interpreter, o, f, v);
            return v;
        }

        Reflect.setProperty(o,f,v);
        return v;
    }

    function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
        // Try helper functions for built-in types first (string, array, map),
        // before calling get(o, f) which may fail on some targets for these types.
        var helper:Dynamic = null;
        if (o is String) {
            helper = Objects.getStringHelper(interpreter, f);
        } else if (Arrays.isArray(o)) {
            helper = Objects.getArrayHelper(interpreter, f);
        } else if (Objects.isFields(o)) {
            helper = Objects.getMapHelper(interpreter, f);
        }
        if (helper != null && Reflect.isFunction(helper)) {
            args.insert(0, o);
            return call(null, helper, args);
        }
        return call(o, get(o, f), args);
    }

    function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) : Dynamic {
        return Reflect.callMethod(o,f,args);
    }

    function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
        var c = Type.resolveClass(cl);
        if( c == null ) c = resolve(cl);
        return Type.createInstance(c,args);
    }

}
