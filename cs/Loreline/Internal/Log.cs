// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal {
	public class Log : global::Loreline.Internal.Lang.HxObject {
		
		static Log() {
			global::Loreline.Internal.Log.trace = ( (( global::Loreline.Internal.Log_Anon_62__Fun.__hx_current != null )) ? (global::Loreline.Internal.Log_Anon_62__Fun.__hx_current) : (global::Loreline.Internal.Log_Anon_62__Fun.__hx_current = ((global::Loreline.Internal.Log_Anon_62__Fun) (new global::Loreline.Internal.Log_Anon_62__Fun()) )) );
		}
		
		
		public Log(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public Log() {
			global::Loreline.Internal.Log.__hx_ctor_haxe_Log(this);
		}
		
		
		protected static void __hx_ctor_haxe_Log(global::Loreline.Internal.Log __hx_this) {
		}
		
		
		public static string formatOutput(object v, object infos) {
			string str = global::Loreline.Internal.Root.Std.@string(v);
			if (( infos == null )) {
				return str;
			}
			
			string pstr = global::Loreline.Internal.Lang.Runtime.concat(global::Loreline.Internal.Lang.Runtime.concat(global::Loreline.Internal.Lang.Runtime.toString(global::Loreline.Internal.Lang.Runtime.getField(infos, "fileName", 1648581351, true)), ":"), global::Loreline.Internal.Lang.Runtime.toString(((int) (global::Loreline.Internal.Lang.Runtime.getField_f(infos, "lineNumber", 1981972957, true)) )));
			if (( ((global::Loreline.Internal.Root.Array) (global::Loreline.Internal.Lang.Runtime.getField(infos, "customParams", 1830310359, true)) ) != null )) {
				int _g = 0;
				global::Loreline.Internal.Root.Array _g1 = ((global::Loreline.Internal.Root.Array) (global::Loreline.Internal.Lang.Runtime.getField(infos, "customParams", 1830310359, true)) );
				while (( _g < ((int) (global::Loreline.Internal.Lang.Runtime.getField_f(_g1, "length", 520590566, true)) ) )) {
					object v1 = _g1[_g];
					 ++ _g;
					str = global::Loreline.Internal.Lang.Runtime.concat(str, global::Loreline.Internal.Lang.Runtime.concat(", ", global::Loreline.Internal.Root.Std.@string(v1)));
				}
				
			}
			
			return global::Loreline.Internal.Lang.Runtime.concat(global::Loreline.Internal.Lang.Runtime.concat(pstr, ": "), str);
		}
		
		
		public static global::Loreline.Internal.Lang.Function trace;
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal {
	public class Log_Anon_62__Fun : global::Loreline.Internal.Lang.Function {
		
		public Log_Anon_62__Fun() : base(2, 0) {
		}
		
		
		public static global::Loreline.Internal.Log_Anon_62__Fun __hx_current;
		
		public override object __hx_invoke2_o(double __fn_float1, object __fn_dyn1, double __fn_float2, object __fn_dyn2) {
			object infos = ( (( __fn_dyn2 == global::Loreline.Internal.Lang.Runtime.undefined )) ? (((object) (__fn_float2) )) : (( (( __fn_dyn2 == null )) ? (null) : (((object) (__fn_dyn2) )) )) );
			object v = ( (( __fn_dyn1 == global::Loreline.Internal.Lang.Runtime.undefined )) ? (((object) (__fn_float1) )) : (((object) (__fn_dyn1) )) );
			string str = global::Loreline.Internal.Log.formatOutput(v, infos);
			global::System.Console.WriteLine(((object) (str) ));
			return null;
		}
		
		
	}
}


