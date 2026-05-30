package loreline.lorscript;
import loreline.lorscript.Expr;

/**
	This is a special type that can be used in API.
	It will be type-checked as `Script` but will compile/execute as `Real`
**/
typedef TypeCheck<Real,Script> = Real;

enum TType {
	TMono( r : { r : TType } );
	TVoid;
	TInt;
	TFloat;
	TBool;
	TDynamic;
	TParam( name : String );
	TUnresolved( name : String );
	TNull( t : TType );
	TInst( c : CClass, args : Array<TType> );
	TEnum( e : CEnum, args : Array<TType> );
	TType( t : CTypedef, args : Array<TType> );
	TAbstract( a : CAbstract, args : Array<TType> );
	TFun( args : Array<{ name : String, opt : Bool, t : TType }>, ret : TType );
	TAnon( fields : Array<{ name : String, opt : Bool, t : TType }> );
	TLazy( f : Void -> TType );
}

private enum WithType {
	NoValue;
	Value;
	WithType( t : TType );
}

enum CTypedecl {
	CTClass( c : CClass );
	CTEnum( e : CEnum );
	CTTypedef( t : CTypedef );
	CTAlias( t : TType );
	CTAbstract( a : CAbstract );
}

typedef CMetadata = Array<{ name : String, params : Null<Array<Expr>> }>;

typedef CNamedType = {
	var name : String;
	var params : Array<TType>;
	var ?meta : CMetadata;
}

typedef CClass = {> CNamedType,
	var ?superClass : TType;
	var ?constructor : CField;
	var ?interfaces : Array<TType>;
	var ?isInterface : Bool;
	var fields : Map<String,CField>;
	var statics : Map<String,CField>;
}

typedef CField = {
	var isPublic : Bool;
	var canWrite : Bool;
	var complete : Bool;
	var params : Array<TType>;
	var name : String;
	var t : TType;
	var ?meta : CMetadata;
}

typedef CEnum = {> CNamedType,
	var constructors : Array<{ name : String, ?args : Array<{ name : String, opt : Bool, t : TType }> }>;
}

typedef CTypedef = {> CNamedType,
	var t : TType;
}

typedef CAbstract = {> CNamedType,
	var t : TType;
}

class Completion {
	public var expr : Expr;
	public var t : TType;
	public function new(expr,t) {
		this.expr = expr;
		this.t = t;
	}
}

@:allow(loreline.lorscript.Checker)
class CheckerTypes {

	var types : Map<String,CTypedecl> = new Map();
	var t_string : TType;
	var localParams : Map<String,TType>;
	var parser : loreline.lorscript.Parser;

	public function new() {
		types = new Map();
		types.set("Void",CTAlias(TVoid));
		types.set("Int",CTAlias(TInt));
		types.set("Float",CTAlias(TFloat));
		types.set("Bool",CTAlias(TBool));
		types.set("Dynamic",CTAlias(TDynamic));
		parser = new loreline.lorscript.Parser();
	}

	public function addXmlApi( api : Xml ) {
		var types = new haxe.rtti.XmlParser();
		types.process(api, "");
		var todo = [];
		for( v in types.root )
			addXmlType(v,todo);
		for( f in todo )
			f();
		t_string = getType("String");
	}

	public function defineClass( name : String, ?ct : CClass ) {
		if( ct == null )
			ct = {
				name : name,
				fields : [],
				statics : [],
				params : [],
			};
		types.set(name, CTClass(ct));
		return ct;
	}

	function addXmlType(x:haxe.rtti.CType.TypeTree,todo:Array<Void->Void>) {
		switch (x) {
		case TPackage(name, full, subs):
			for( s in subs ) addXmlType(s,todo);
		case TClassdecl(c):
			if( types.exists(c.path) ) return;
			var cl : CClass = {
				name : c.path,
				params : [],
				fields : new Map(),
				statics : new Map(),
			};
			addMeta(c,cl);
			if( c.isInterface )
				cl.isInterface = true;
			for( p in c.params )
				cl.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in cl.params ) c.path+"."+Checker.typeStr(t) => t];
				if( c.superClass != null )
					cl.superClass = getType(c.superClass.path, [for( t in c.superClass.params ) makeXmlType(t)]);
				if( c.interfaces != null ) {
					cl.interfaces = [];
					for( i in c.interfaces )
						cl.interfaces.push(getType(i.path, [for( t in i.params ) makeXmlType(t)]));
				}
				var pkeys = [];
				function initField(f:haxe.rtti.CType.ClassField, fields) {
					if( f.isOverride || f.name.substr(0,4) == "get_" || f.name.substr(0,4) == "set_" ) return;
					var complete = !StringTools.startsWith(f.name,"__"); // __uid, etc. (no metadata in such fields)
					for( m in f.meta ) {
						if( m.name == ":noScript"  )
							return;
						if( m.name == ":noCompletion" )
							complete = false;
					}
					var fl : CField = { isPublic : f.isPublic, canWrite : f.set.match(RNormal | RCall(_) | RDynamic), complete : complete, params : [], name : f.name, t : null };
					for( p in f.params ) {
						var pt = TParam(p);
						var key = f.name+"."+p;
						pkeys.push(key);
						fl.params.push(pt);
						localParams.set(key, pt);
					}
					fl.t = makeXmlType(f.type);
					if( f.meta != null && f.meta.length > 0 ) {
						fl.meta = [];
						for( m in f.meta )
							fl.meta.push({ name : m.name, params : [for( p in m.params ) try parser.parseString(p) catch( e : loreline.lorscript.Expr.Error ) null] });
					}
					while( pkeys.length > 0 )
						localParams.remove(pkeys.pop());
					if( fl.name == "new" )
						cl.constructor = fl;
					else
						fields.set(f.name, fl);
				}
				for( f in c.fields )
					initField(f, cl.fields);
				for( f in c.statics )
					initField(f, cl.statics);
				localParams = null;
			});
			types.set(cl.name, CTClass(cl));
		case TEnumdecl(e):
			if( types.exists(e.path) ) return;
			var en : CEnum = {
				name : e.path,
				params : [],
				constructors: [],
			};
			addMeta(e,en);
			for( p in e.params )
				en.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in en.params ) e.path+"."+Checker.typeStr(t) => t];
				for( c in e.constructors )
					en.constructors.push({ name : c.name, args : c.args == null ? null : [for( a in c.args ) { name : a.name, opt : a.opt, t : makeXmlType(a.t) }] });
				localParams = null;
			});
			types.set(en.name, CTEnum(en));
		case TTypedecl(t):
			if( types.exists(t.path) ) return;
			var td : CTypedef = {
				name : t.path,
				params : [],
				t : null,
			};
			for( p in t.params )
				td.params.push(TParam(p));
			if( t.path == "loreline.lorscript.TypeCheck" )
				td.params.reverse();
			todo.push(function() {
				localParams = [for( pt in td.params ) t.path+"."+Checker.typeStr(pt) => pt];
				td.t = makeXmlType(t.type);
				localParams = null;
			});
			types.set(t.path, CTTypedef(td));
		case TAbstractdecl(a):
			if( types.exists(a.path) ) return;
			var ta : CAbstract = {
				name : a.path,
				params : [],
				t : null,
			};
			addMeta(a,ta);
			for( p in a.params )
				ta.params.push(TParam(p));
			todo.push(function() {
				localParams = [for( t in ta.params ) a.path+"."+Checker.typeStr(t) => t];
				ta.t = makeXmlType(a.athis);
				localParams = null;
			});
			types.set(a.path, CTAbstract(ta));
		}
	}

	function addMeta( src : haxe.rtti.CType.TypeInfos, to : CNamedType ) {
		if( src.meta == null || src.meta.length == 0 )
			return;
		to.meta = [];
		for( m in src.meta )
			to.meta.push({ name : m.name, params : [for( p in m.params ) try parser.parseString(p) catch( e : loreline.lorscript.Expr.Error ) null] });
	}

	function makeXmlType( t : haxe.rtti.CType.CType ) : TType {
		return switch (t) {
		case CUnknown: TUnresolved("Unknown");
		case CEnum(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CClass(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CTypedef(name, params): getType(name,[for( t in params ) makeXmlType(t)]);
		case CFunction(args, ret): TFun([for( a in args ) { name : a.name, opt : a.opt, t : makeXmlType(a.t) }], makeXmlType(ret));
		case CAnonymous(fields):
			inline function isOpt(m:haxe.rtti.CType.MetaData) {
				if( m == null ) return false;
				var b = false;
				for( m in m ) if( m.name == ":optional" ) { b = true; break; }
				return b;
			}
			TAnon([for( f in fields ) { name : f.name, t : makeXmlType(f.type), opt : isOpt(f.meta) }]);
		case CDynamic(t): TDynamic;
		case CAbstract(name, params):
			switch( name ) {
			default:
				getType(name,[for( t in params ) makeXmlType(t)]);
			}
		}
	}

	function getType( name : String, ?args : Array<TType> ) : TType {
		if( localParams != null ) {
			var t = localParams.get(name);
			if( t != null ) return t;
		}
		var t = resolve(name,args);
		if( t == null ) {
			var pack = name.split(".");
			if( pack.length > 1 ) {
				// bugfix for some args reported as pack._Name.Name while they are not private
				var priv = pack[pack.length-2];
				if( priv.charCodeAt(0) == "_".code ) {
					pack.remove(priv);
					return getType(pack.join("."), args);
				}
			}
			return TUnresolved(name); // most likely private class
		}
		return t;
	}

	public function resolve( name : String, ?args : Array<TType> ) : TType {
		if( name == "Null" ) {
			if( args == null || args.length != 1 ) throw "Missing Null<T> parameter";
			return TNull(args[0]);
		}
		var t = types.get(name);
		if( t == null ) return null;
		if( args == null ) args = [];
		return switch( t ) {
		case CTClass(c): TInst(c,args);
		case CTEnum(e): TEnum(e,args);
		case CTTypedef(t): TType(t,args);
		case CTAbstract(a): TAbstract(a, args);
		case CTAlias(t): t;
		}
	}

}

class Checker {

	public var types : CheckerTypes;
	var locals : Map<String,TType>;
	var globals : Map<String,TType> = new Map();
	var events : Map<String,TType> = new Map();
	var currentFunType : TType;
	var isCompletion : Bool;
	var allowDefine : Bool;
	var hasReturn : Bool;
	public var allowAsync : Bool;
	public var allowReturn : Null<TType>;
	public var allowGlobalsDefine : Bool;
	public var allowUntypedMeta : Bool;

	public function new( ?types ) {
		if( types == null ) types = new CheckerTypes();
		this.types = types;
	}

	public function setGlobals( cl : CClass, allowPrivate = false ) {
		while( true ) {
			for( f in cl.fields )
				if( f.isPublic || allowPrivate )
					setGlobal(f.name, f.params.length == 0 ? f.t : TLazy(function() return apply(f.t,f.params,[for( i in 0...f.params.length) makeMono()])));
			if( cl.superClass == null )
				break;
			cl = switch( cl.superClass ) {
			case TInst(c,_): c;
			default: throw "assert";
			}
		}
	}

	public function removeGlobal( name : String ) {
		globals.remove(name);
	}

	public function setGlobal( name : String, type : TType ) {
		globals.set(name, type);
	}

	public function setEvent( name : String, type : TType ) {
		events.set(name, type);
	}

	public function getGlobals() {
		return globals;
	}

	public dynamic function onTopDownEnum( en : CEnum, field : String ) {
		return false;
	}

	function typeArgs( args : Array<Argument>, pos : Expr ) {
		return [for( i in 0...args.length ) {
			var a = args[i];
			var at = a.t == null ? makeMono() : makeType(a.t, pos);
			{ name : a.name, opt : a.opt, t : at };
		}];
	}

	public function check( expr : Expr, ?withType : WithType, ?isCompletion = false ) {
		if( withType == null ) withType = NoValue;
		locals = new Map();
		if( types.t_string == null )
			types.t_string = types.getType("String");
		allowDefine = allowGlobalsDefine;
		this.isCompletion = isCompletion;
		if( edef(expr).match(EFunction(_)) )
			expr = mk(EBlock([expr]), expr); // single function might be self recursive
		switch( edef(expr) ) {
		case EBlock(el):
			var delayed = [];
			var last = TVoid;
			for( e in el ) {
				while( true ) {
					switch( edef(e) ) {
					case EMeta(_,_,e2): e = e2;
					default: break;
					}
				}
				switch( edef(e) ) {
				case EFunction(args,_,name,ret) if( name != null ):
					var tret = ret == null ? makeMono() : makeType(ret, e);
					var ft = TFun(typeArgs(args,e),tret);
					locals.set(name, ft);
					delayed.push(function() {
						currentFunType = ft;
						typeExpr(e, NoValue);
						return ft;
					});
				default:
					for( f in delayed ) f();
					delayed = [];
					if( el[el.length-1] == e )
						last = typeExpr(e, withType);
					else
						typeExpr(e, NoValue);
				}
			}
			for( f in delayed )
				last = f();
			return last;
		default:
		}
		return typeExpr(expr,withType);
	}

	inline function edef( e : Expr ) {
		
		return e.e;
		
	}

	inline function error( msg : String, curExpr : Expr ) {
		var e = ECustom(msg);
		 var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); 
		if( !isCompletion ) throw e;
	}

	function saveLocals() {
		return [for( k in locals.keys() ) k => locals.get(k)];
	}

	function makeType( t : CType, e : Expr ) : TType {
		return switch (t) {
		case CTPath(path, params):
			var ct = types.resolve(path.join("."),params == null ? [] : [for( p in params ) makeType(p,e)]);
			if( ct == null ) {
				error("Unknown type "+path, e);
				ct = TDynamic;
			}
			return ct;
		case CTFun(args, ret):
			var i = 0;
			return TFun([for( a in args ) { name : "p"+(i++), opt : false, t : makeType(a,e) }], makeType(ret,e));
		case CTAnon(fields):
			return TAnon([for( f in fields ) { name : f.name, opt : false, t : makeType(f.t,e) }]);
		case CTParent(t):
			return makeType(t,e);
		case CTNamed(n, t):
			return makeType(t,e);
		case CTOpt(t):
			return makeType(t,e);
		}
	}

	public static function typeStr( t : TType ) {
		inline function makeArgs(args:Array<TType>) return args.length==0 ? "" : "<"+[for( t in args ) typeStr(t)].join(",")+">";
		return switch (t) {
		case TMono(r): r.r == null ? "Unknown" : typeStr(r.r);
		case TInst(c, args): c.name + makeArgs(args);
		case TEnum(e, args): e.name + makeArgs(args);
		case TType(t, args):
			if( t.name == "loreline.lorscript.TypeCheck" )
				typeStr(args[1]);
			else
				t.name + makeArgs(args);
		case TAbstract(a, args): a.name + makeArgs(args);
		case TFun(args, ret): "(" + [for( a in args ) (a.opt?"?":"")+(a.name == "" ? "" : a.name+":")+typeStr(a.t)].join(", ")+") -> "+typeStr(ret);
		case TAnon(fields): "{" + [for( f in fields ) (f.opt?"?":"")+f.name+":"+typeStr(f.t)].join(", ")+"}";
		case TParam(name): name;
		case TNull(t): "Null<"+typeStr(t)+">";
		case TUnresolved(name): "?"+name;
		default: t.getName().substr(1);
		}
	}

	public static function typeIter( t : TType, callb : TType -> Void ) {
		switch( t ) {
		case TMono(r) if( r.r != null ): callb(r.r);
		case TNull(t): callb(t);
		case TInst(_,tl), TAbstract(_,tl), TEnum(_,tl), TType(_,tl):
			for( t in tl ) callb(t);
		case TFun(args,ret):
			for( t in args ) callb(t.t);
			callb(ret);
		case TAnon(fl):
			for( f in fl )
				callb(f.t);
		case TLazy(f):
			callb(f());
		default:
		}
	}

	function linkLoop( a : TType, t : TType ) {
		if( t == a ) return true;
		switch( t ) {
		case TMono(r):
			if( r.r == null ) return false;
			return linkLoop(a,r.r);
		case TEnum(_,tl), TInst(_,tl), TType(_,tl), TAbstract(_,tl):
			for( t in tl )
				if( linkLoop(a,t) )
					return true;
			return false;
		case TFun(args,ret):
			for( arg in args )
				if( linkLoop(a,arg.t) )
					return true;
			return linkLoop(a,ret);
		case TDynamic:
			if( t == TDynamic )
				return false;
			return linkLoop(a,TDynamic);
		case TAnon(fl):
			for( f in fl )
				if( linkLoop(a, f.t) )
					return true;
			return false;
		default:
			return false;
		}
	}

	function link( a : TType, b : TType, r : { r : TType } ) {
		if( linkLoop(a,b) )
			return follow(b) == a;
		if( b == TDynamic )
			return true;
		r.r = b;
		return true;
	}

	function typeEq( t1 : TType, t2 : TType ) {
		if( t1 == t2 )
			return true;
		switch( [t1,t2] ) {
		case [TMono(r), _]:
			if( r.r == null ) {
				if( !link(t1,t2,r) )
					return false;
				r.r = t2;
				return true;
			}
			return typeEq(r.r, t2);
		case [_, TMono(r)]:
			if( r.r == null ) {
				if( !link(t2,t1,r) )
					return false;
				r.r = t1;
				return true;
			}
			return typeEq(t1, r.r);
		case [TType(t1,pl1),TType(t2,pl2)] if( t1 == t2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TType(t1,pl1), _]:
			return typeEq(apply(t1.t, t1.params, pl1), t2);
		case [_,TType(t2,pl2)]:
			return typeEq(t1, apply(t2.t, t2.params, pl2));
		case [TInst(cl1,pl1), TInst(cl2,pl2)] if( cl1 == cl2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TEnum(e1,pl1), TEnum(e2,pl2)] if( e1 == e2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TAbstract(a1,pl1), TAbstract(a2,pl2)] if( a1 == a2 ):
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TNull(t1), TNull(t2)]:
			return typeEq(t1,t2);
		case [TNull(t1), _]:
			return typeEq(t1,t2);
		case [_, TNull(t2)]:
			return typeEq(t1,t2);
		case [TFun(args1,r1), TFun(args2,r2)] if( args1.length == args2.length ):
			for( i in 0...args1.length )
				if( !typeEq(args1[i].t, args2[i].t) )
					return false;
			return typeEq(r1, r2);
		case [TAnon(a1),TAnon(a2)] if( a1.length == a2.length ):
			var m = new Map();
			for( f in a2 )
				m.set(f.name, f);
			for( f1 in a1 ) {
				var f2 = m.get(f1.name);
				if( f2 == null ) return false;
				if( !typeEq(f1.t,f2.t) )
					return false;
			}
			return true;
		default:
		}
		return false;
	}

	public function tryUnify( t1 : TType, t2 : TType ) {
		if( t1 == t2 )
			return true;
		switch( [t1,t2] ) {
		case [TMono(r), _]:
			if( r.r == null ) {
				if( !link(t1,t2,r) )
					return false;
				r.r = t2;
				return true;
			}
			return tryUnify(r.r, t2);
		case [_, TMono(r)]:
			if( r.r == null ) {
				if( !link(t2,t1,r) )
					return false;
				r.r = t1;
				return true;
			}
			return tryUnify(t1, r.r);
		case [TType(t1,pl1), _]:
			return tryUnify(apply(t1.t, t1.params, pl1), t2);
		case [_,TType(t2,pl2)]:
			return tryUnify(t1, apply(t2.t, t2.params, pl2));
		case [TNull(t1), _]:
			return tryUnify(t1,t2);
		case [_, TNull(t2)]:
			return tryUnify(t1,t2);
		case [TFun(args1,r1),TFun(args2,r2)] if( args1.length == args2.length ):
			for( i in 0...args1.length ) {
				var a1 = args1[i];
				var a2 = args2[i];
				if( a2.opt && !a1.opt ) return false;
				if( !tryUnify(a2.t, a1.t) ) return false;
			}
			return tryUnify(r1,r2);
		case [_, TDynamic]:
			return true;
		case [TDynamic, _]:
			return true;
		case [TAnon(a1),TAnon(a2)]:
			if( a2.length == 0 ) // always unify with {}
				return true;
			var m = new Map();
			for( f in a1 )
				m.set(f.name, f);
			for( f2 in a2 ) {
				var f1 = m.get(f2.name);
				if( f1 == null ) {
					if( f2.opt ) continue;
					return false;
				}
				if( !typeEq(f1.t,f2.t) )
					return false;
			}
			return true;
		case [TInst(cl1,pl1), TInst(cl2,pl2)]:
			while( cl1 != cl2 ) {
				if( cl1.interfaces != null ) {
					for( i in cl1.interfaces ) {
						switch( i ) {
						case TInst(cli, args):
							var i = TInst(cli, [for( a in args ) apply(a, cl1.params, pl1)]);
							if( tryUnify(i, t2) )
								return true;
						default:
							throw "assert";
						}
					}
				}
				switch( cl1.superClass ) {
				case null: return false;
				case TInst(c, args):
					pl1 = [for( a in args ) apply(a,cl1.params,pl1)];
					cl1 = c;
				default: throw "assert";
				}
			}
			for( i in 0...pl1.length )
				if( !typeEq(pl1[i],pl2[i]) )
					return false;
			return true;
		case [TInst(cl1,pl1),TAnon(fl)]:
			for( i in 0...fl.length ) {
				var f2 = fl[i];
				var f1 = null;
				var cl = cl1;
				while( true ) {
				 	f1 = cl.fields.get(f2.name);
					if( f1 != null ) break;
					if( cl.superClass == null )
						return false;
					cl = switch( cl.superClass ) {
					case TInst(c,_): c;
					default: throw "assert";
					}
				}
				if( !typeEq(apply(f1.t,cl1.params,pl1),f2.t) )
					return false;
			}
			return true;
		case [TInt, TFloat]:
			return true;
		case [TFun(_), TAbstract({ name : "haxe.Function" },_)]:
			return true;
		default:
		}
		return typeEq(t1,t2);
	}

	public function unify( t1 : TType, t2 : TType, e : Expr ) {
		if( !tryUnify(t1,t2) )
			error(typeStr(t1)+" should be "+typeStr(t2),e);
	}

	public function apply( t : TType, params : Array<TType>, args : Array<TType> ) {
		if( args.length != params.length ) throw "Invalid number of type parameters";
		if( args.length == 0 )
			return t;
		var subst = new Map();
		for( i in 0...params.length )
			subst.set(params[i], args[i]);
		function map(t:TType) {
			var st = subst.get(t);
			if( st != null ) return st;
			return mapType(t,map);
		}
		return map(t);
	}

	public function mapType( t : TType, f : TType -> TType ) {
		switch (t) {
		case TMono(r):
			if( r.r == null ) return t;
			return f(t);
		case TVoid, TInt, TFloat,TBool,TDynamic,TParam(_), TUnresolved(_):
			return t;
		case TEnum(_,[]), TInst(_,[]), TAbstract(_,[]), TType(_,[]):
			return t;
		case TNull(t):
			return TNull(f(t));
		case TInst(c, args):
			return TInst(c, [for( t in args ) f(t)]);
		case TEnum(e, args):
			return TEnum(e, [for( t in args ) f(t)]);
		case TType(t, args):
			return TType(t, [for( t in args ) f(t)]);
		case TAbstract(a, args):
			return TAbstract(a, [for( t in args ) f(t)]);
		case TFun(args, ret):
			return TFun([for( a in args ) { name : a.name, opt : a.opt, t : f(a.t) }], f(ret));
		case TAnon(fields):
			return TAnon([for( af in fields ) { name : af.name, opt : af.opt, t : f(af.t) }]);
		case TLazy(l):
			return f(l());
		}
	}

	public function follow( t : TType ) {
		return switch( t ) {
		case TMono(r): if( r.r != null ) follow(r.r) else t;
		case TType(t,args): follow(apply(t.t, t.params, args));
		case TNull(t): follow(t);
		case TLazy(f): follow(f());
		default: t;
		}
	}

	public function getFields( t : TType ) : Array<{ name : String, t : TType }> {
		var fields = [];
		switch( follow(t) ) {
		case TInst(c, args):
			var map = (t) -> apply(t,c.params,args);
			while( c != null ) {
				for( fname in c.fields.keys() ) {
					var f = c.fields.get(fname);
					if( !f.isPublic || !f.complete ) continue;
					var name = f.name, t = map(f.t);
					if( allowAsync && StringTools.startsWith(name,"a_") ) {
						t = unasync(t);
						name = name.substr(2);
					}
					fields.push({ name : name, t : t });
				}
				if( c.isInterface && c.interfaces != null ) {
					for( i in c.interfaces ) {
						for( f in getFields(i) )
							fields.push({ name : f.name, t : map(f.t) });
					}
				}
				if( c.superClass == null ) break;
				switch( c.superClass ) {
				case TInst(csup,args):
					var curMap = map;
					map = (t) -> curMap(apply(t,csup.params,args));
					c = csup;
				default:
					break;
				}
			}
		case TAnon(fl):
			for( f in fl )
				fields.push({ name : f.name, t : f.t });
		case TFun(args, ret):
			if( isCompletion )
				fields.push({ name : "bind", t : TFun(args,TVoid) });
		default:
		}
		return fields;
	}

	function getField( t : TType, f : String, e : Expr, forWrite = false ) {
		switch( follow(t) ) {
		case TInst(c, args):
			var cf = c.fields.get(f);
			if( cf == null && allowAsync ) {
				cf = c.fields.get("a_"+f);
				if( cf != null ) {
					var isPublic = true; // consider a_ prefixed as script specific
					cf = { isPublic : isPublic, canWrite : false, params : cf.params, name : cf.name, t : unasync(cf.t), complete : cf.complete };
					if( cf.t == null ) cf = null;
				}
			}
			if( cf == null && c.isInterface && c.interfaces != null ) {
				for( i in c.interfaces ) {
					var ft = getField(i, f, e, forWrite);
					if( ft != null )
						return apply(ft, c.params, args);
				}
			}
			if( cf == null ) {
				if( c.superClass == null ) return null;
				var ft = getField(c.superClass, f, e, forWrite);
				if( ft != null ) ft = apply(ft, c.params, args);
				return ft;
			}
			if( !cf.isPublic )
				error("Can't access private field "+f+" on "+c.name, e);
			if( forWrite && !cf.canWrite )
				error("Can't write readonly field "+f+" on "+c.name, e);
			var t = cf.t;
			if( cf.params != null ) t = apply(t, cf.params, [for( i in 0...cf.params.length ) makeMono()]);
			return apply(t, c.params, args);
		case TDynamic:
			return makeMono();
		case TAnon(fields):
			for( af in fields )
				if( af.name == f )
					return af.t;
			return null;
		default:
			return null;
		}
	}

	public function unasync( t : TType ) : TType {
		switch( follow(t) ) {
		case TFun(args, ret) if( args.length > 0 ):
			var rargs = args.copy();
			switch( follow(rargs.shift().t) ) {
			case TFun([r],_): return TFun(rargs,r.t);
			default:
			}
		default:
		}
		return null;
	}

	function typeExprWith( expr : Expr, t : TType ) {
		var et = typeExpr(expr, WithType(t));
		unify(et, t, expr);
		return t;
	}

	function makeMono() {
		return TMono({r:null});
	}

	function makeIterator(t) : TType {
		return TAnon([{ name : "next", opt : false, t : TFun([],t) }, { name : "hasNext", opt : false, t : TFun([],TBool) }]);
	}

	function mk(e,p) : Expr {
		
		return { e : e, pmin : p.pmin, pmax : p.pmax, origin : p.origin, line : p.line };
		
	}

	function isString( t : TType ) {
		t = follow(t);
		return t.match(TInst({name:"String"},_));
	}

	function onCompletion( expr : Expr, t : TType ) {
		if( isCompletion ) throw new Completion(expr, t);
	}

	function typeField( o : Expr, f : String, expr : Expr, forWrite : Bool ) {
		var ot = typeExpr(o, Value);
		if( f == null )
			onCompletion(expr, ot);
		var ft = getField(ot, f, expr, forWrite);
		if( ft == null ) {
			error(typeStr(ot)+" has no field "+f, expr);
			ft = TDynamic;
		}
		return ft;
	}

	function typeExpr( expr : Expr, withType : WithType ) : TType {
		if( expr == null && isCompletion )
			return switch( withType ) {
			case WithType(t): t;
			default: TDynamic;
			}
		switch( edef(expr) ) {
		case EConst(c):
			return switch (c) {
			case CInt(_): TInt;
			case CFloat(_): TFloat;
			case CString(_): types.t_string;
			}
		case EIdent(v):
			var l = locals.get(v);
			if( l != null ) return l;
			var g = globals.get(v);
			if( g != null ) {
				return switch( g ) {
				case TLazy(f): f();
				default: g;
				}
			}
			if( allowAsync ) {
				g = globals.get("a_"+v);
				if( g != null ) g = unasync(g);
				if( g != null ) return g;
			}
			switch( v ) {
			case "null":
				return makeMono();
			case "true", "false":
				return TBool;
			case "trace":
				return TDynamic;
			default:
				switch( withType ) {
				case WithType(et = TEnum(e, args)):
					for( c in e.constructors )
						if( c.name == v ) {
							if( onTopDownEnum(e,v) ) {
								var ct = c.args == null ? et : TFun(c.args, et);
								return apply(ct, e.params, args);
							}
							break;
						}
				default:
				}
				if( isCompletion ) return TDynamic;
				error("Unknown identifier "+v, expr);
			}
		case EBlock(el):
			var t = TVoid;
			var locals = saveLocals();
			for( e in el )
				t = typeExpr(e, e == el[el.length-1] ? withType : NoValue);
			this.locals = locals;
			return t;
		case EVar(n, t, init):
			var vt = t == null ? makeMono() : makeType(t, expr);
			if( init != null ) {
				var et = typeExpr(init, t == null ? Value : WithType(vt));
				if( t == null ) vt = et else unify(et,vt, init);
			}
			locals.set(n, vt);
			return TVoid;
		case EParent(e):
			return typeExpr(e,withType);
		case ECall(e, params):
			switch( edef(e) ) {
			case EField(val, "bind"):
				var ft = typeExpr(val, Value);
				switch( ft ) {
				case TFun(args,ret):
					var remainArgs = args.copy();
					for( p in params ) {
						var a = remainArgs.shift();
						if( a == null ) {
							error("Too many arguments", p);
							return TFun([], ret);
						}
						typeExprWith(p, a.t);
					}
					return TFun(remainArgs, ret);
				default:
				}
			default:
			}
			var ft = typeExpr(e, switch( [edef(e),withType] ) {
				case [EIdent(_),WithType(TEnum(_))]: withType;
				default: Value;
			});
			switch( follow(ft) ) {
			case TFun(args, ret):
				for( i in 0...params.length ) {
					var a = args[i];
					if( a == null ) {
						error("Too many arguments", params[i]);
						break;
					}
					var t = typeExpr(params[i], a == null ? Value : WithType(a.t));
					unify(t, a.t, params[i]);
				}
				for( i in params.length...args.length )
					if( !args[i].opt )
						error("Missing argument "+args[i].name+":"+typeStr(args[i].t), expr);
				return ret;
			case TDynamic:
				for( p in params ) typeExpr(p,Value);
				return makeMono();
			default:
				error(typeStr(ft)+" cannot be called", e);
				return makeMono();
			}
		case EField(o, f):
			return typeField(o,f,expr,false);
		case ECheckType(v, t):
			var ct = makeType(t, expr);
			var vt = typeExpr(v, WithType(ct));
			unify(vt, ct, v);
			return ct;
		case EMeta(m, _, e):
			if( m == ":untyped" && allowUntypedMeta )
				return makeMono();
			return typeExpr(e, withType);
		case EIf(cond, e1, e2), ETernary(cond, e1, e2):
			typeExprWith(cond, TBool);
			var t1 = typeExpr(e1, withType);
			if( e2 == null )
				return t1;
			var t2 = typeExpr(e2, withType);
			if( withType == NoValue )
				return TVoid;
			if( tryUnify(t2,t1) )
				return t1;
			if( tryUnify(t1,t2) )
				return t2;
			unify(t2,t1,e2); // error
		case EWhile(cond, e), EDoWhile(cond, e):
			typeExprWith(cond,TBool);
			typeExpr(e, NoValue);
			return TVoid;
		case EObject(fl):
			switch( withType ) {
			case WithType(follow(_) => TAnon(tfields)) if( tfields.length > 0 ):
				var map = [for( f in tfields ) f.name => f];
				return TAnon([for( f in fl ) {
					var ft = map.get(f.name);
					var ft = if( ft == null ) {
						error("Extra field "+f.name, f.e);
						TDynamic;
					} else ft.t;
					{ t : typeExprWith(f.e, ft), opt : false, name : f.name }
				}]);
			default:
				return TAnon([for( f in fl ) { t : typeExpr(f.e, Value), opt : false, name : f.name }]);
			}
		case EBreak, EContinue:
			return TVoid;
		case EReturn(v):
			var et = v == null ? TVoid : typeExpr(v, allowReturn == null ? Value : WithType(allowReturn));
			hasReturn = true;
			if( allowReturn == null )
				error("Return not allowed here", expr);
			else
				unify(et, allowReturn, v == null ? expr : v);
			return makeMono();
		case EArrayDecl(el):
			var et = null;
			for( v in el ) {
				var t = typeExpr(v, et == null ? Value : WithType(et));
				if( et == null ) et = t else if( !tryUnify(t,et) ) {
					if( tryUnify(et,t) ) et = t else unify(t,et,v);
				}
			}
			if( et == null ) et = makeMono();
			return types.getType("Array",[et]);
		case EArray(a, index):
			typeExprWith(index, TInt);
			var at = typeExpr(a, Value);
			switch( follow(at) ) {
			case TInst({ name : "Array"},[et]): return et;
			default: error(typeStr(at)+" is not an Array", a);
			}
		case EThrow(e):
			typeExpr(e, Value);
			return makeMono();
		case EFunction(args, body, name, ret):
			var ft = null, tret = null, targs = null;
			if( currentFunType != null ) {
				switch( currentFunType ) {
				case TFun(args,ret):
					ft = currentFunType;
					tret = ret; targs = args;
				default:
					throw "assert";
				}
				currentFunType = null;
			} else {
				tret = ret == null ? makeMono() : makeType(ret, expr);
			}
			var locals = saveLocals();
			var oldRet = allowReturn;
			var oldGDef = allowDefine;
			var oldHasRet = hasReturn;
			allowReturn = tret;
			allowDefine = false;
			hasReturn = false;
			var withArgs = null;
			if( name != null && !withType.match(WithType(follow(_) => TFun(_))) ) {
				var ev = events.get(name);
				if( ev != null ) withType = WithType(ev);
			}
			switch( withType ) {
			case WithType(follow(_) => TFun(args,ret)): withArgs = args; unify(tret,ret,expr);
			default:
			}
			if( targs == null )
				targs = typeArgs(args,expr);
			for( i in 0...targs.length ) {
				var a = targs[i];
				if( withArgs != null ) {
					if( i < withArgs.length )
						unify(withArgs[i].t, a.t, expr);
					else
						error("Extra argument "+a.name, expr);
				}
				this.locals.set(a.name, a.t);
			}
			if( withArgs != null && targs.length < withArgs.length )
				error("Missing "+(withArgs.length - targs.length)+" arguments ("+[for( i in targs.length...withArgs.length ) typeStr(withArgs[i].t)].join(",")+")", expr);
			typeExpr(body,NoValue);
			if( !hasReturn && !tryUnify(tret, TVoid) )
				error("Missing return "+typeStr(tret), expr);
			allowDefine = oldGDef;
			allowReturn = oldRet;
			hasReturn = oldHasRet;
			this.locals = locals;
			if( ft == null ) {
				ft = TFun(targs, tret);
				if( name != null ) locals.set(name, ft);
			}
			return ft;
		case EUnop(op, _, e):
			var et = typeExpr(e, Value);
			switch( op ) {
			case "++", "--", "-":
				unify(et,TInt,e);
				return et;
			case "!":
				unify(et,TBool,e);
				return et;
			default:
			}
		case EFor(v, it, e):
			var locals = saveLocals();
			var itt = typeExpr(it, Value);
			var vt = getIteratorType(it, itt);
			this.locals.set(v, vt);
			typeExpr(e, NoValue);
			this.locals = locals;
			return TVoid;
		case EBinop(op, e1, e2):
			switch( op ) {
			case "&", "|", "^", ">>", ">>>", "<<":
				typeExprWith(e1,TInt);
				typeExprWith(e2,TInt);
				return TInt;
			case "=":
				if( allowDefine ) {
					switch( edef(e1) ) {
					case EIdent(i) if( !locals.exists(i) && !globals.exists(i) ):
						var vt = typeExpr(e2,Value);
						locals.set(i, vt);
						return vt;
					default:
					}
				}
				var vt = switch( edef(e1) ) {
				case EField(o,f): typeField(o, f, e1, true);
				default: typeExpr(e1,Value);
				}
				typeExprWith(e2,vt);
				return vt;
			case "+":
				var t1 = typeExpr(e1,WithType(TInt));
				var t2 = typeExpr(e2,WithType(t1));
				tryUnify(t1,t2);
				switch( [follow(t1), follow(t2)]) {
				case [TInt, TInt]:
					return TInt;
				case [TFloat, TInt], [TInt, TFloat], [TFloat, TFloat]:
					return TFloat;
				case [TDynamic, _], [_, TDynamic]:
					return TDynamic;
				case [t1,t2]:
					if( isString(t1) || isString(t2) )
						return types.t_string;
					unify(t1, TFloat, e1);
					unify(t2, TFloat, e2);
				}
			case "-", "*", "/", "%":
				var t1 = typeExpr(e1,WithType(TInt));
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				switch( [follow(t1), follow(t2)]) {
				case [TInt, TInt]:
					if( op == "/" ) return TFloat;
					return TInt;
				case [TFloat|TDynamic, TInt|TDynamic], [TInt|TDynamic, TFloat|TDynamic], [TFloat, TFloat]:
					return TFloat;
				default:
					unify(t1, TFloat, e1);
					unify(t2, TFloat, e2);
				}
			case "&&", "||":
				typeExprWith(e1,TBool);
				typeExprWith(e2,TBool);
				return TBool;
			case "...":
				typeExprWith(e1,TInt);
				typeExprWith(e2,TInt);
				return makeIterator(TInt);
			case "==", "!=":
				var t1 = typeExpr(e1,Value);
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				return TBool;
			case ">", "<", ">=", "<=":
				var t1 = typeExpr(e1,Value);
				var t2 = typeExpr(e2,WithType(t1));
				if( !tryUnify(t1,t2) )
					unify(t2,t1,e2);
				switch( follow(t1) ) {
				case TInt, TFloat, TBool, TInst({name:"String"},_):
				default:
					error("Cannot compare "+typeStr(t1), expr);
				}
				return TBool;
			default:
				if( op.charCodeAt(op.length-1) == "=".code ) {
					var t = typeExpr(mk(EBinop(op.substr(0,op.length-1),e1,e2),expr),withType);
					return typeExpr(mk(EBinop("=",e1,e2),expr), withType);
				}
				error("Unsupported operation "+op, expr);
			}
		case ETry(etry, v, et, ecatch):
			var vt = typeExpr(etry, withType);

			var old = locals.get(v);
			locals.set(v, makeType(et, ecatch));
			var ct = typeExpr(ecatch, withType);
			if( old != null ) locals.set(v,old) else locals.remove(v);

			if( withType == NoValue )
				return TVoid;
			if( tryUnify(vt,ct) )
				return ct;
			unify(ct,vt,ecatch);
			return vt;
		case ESwitch(value, cases, defaultExpr):
			var tmin = null;
			var vt = typeExpr(value, Value);
			inline function mergeType(t,p) {
				if( withType != NoValue ) {
					if( tmin == null )
						tmin = t;
					else if( !tryUnify(t,tmin) ) {
						unify(tmin,t, p);
						tmin = t;
					}
				}
			}
			for( c in cases ) {
				for( v in c.values ) {
					var ct = typeExpr(v, WithType(vt));
					unify(ct, vt, v);
				}
				var et = typeExpr(c.expr, withType);
				mergeType(et, c.expr);
			}
			if( defaultExpr != null )
				mergeType( typeExpr(defaultExpr, withType), defaultExpr);
			return withType == NoValue ? TVoid : tmin == null ? makeMono() : tmin;
		case ENew(cl, params):
		}
		error("Don't know how to type "+edef(expr).getName(), expr);
		return TDynamic;
	}

	function getIteratorType( it : Expr, itt : TType ) {
		switch( follow(itt) ) {
		case TInst({name:"Array"},[t]):
			return t;
		default:
		}
		var ft = getField(itt,"iterator", it);
		if( ft == null )
			switch( itt ) {
			case TAbstract(a, args):
				// special case : we allow unconditional access
				// to an abstract iterator() underlying value (eg: ArrayProxy)
				var at = apply(a.t,a.params,args);
				return getIteratorType(it, at);
			default:
			}
		if( ft != null )
			switch( ft ) {
			case TFun([],ret): ft = ret;
			default: ft = null;
			}
		var t = makeMono();
		var iter = makeIterator(t);
		unify(ft != null ? ft : itt,iter,it);
		return t;
	}

}