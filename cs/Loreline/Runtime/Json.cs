// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060
namespace Loreline.Runtime {
	public class Json : global::Loreline.Internal.Lang.HxObject {
		
		public Json(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public Json() {
			global::Loreline.Runtime.Json.__hx_ctor_loreline_Json(this);
		}
		
		
		protected static void __hx_ctor_loreline_Json(global::Loreline.Runtime.Json __hx_this) {
		}
		
		
		public static string stringify(object @value, global::Loreline.Internal.Lang.Null<bool> pretty) {
			bool pretty1 = ( ( ! (pretty.hasValue) ) ? (false) : ((pretty).@value) );
			global::Loreline.Internal.Lang.Function replacer = null;
			return global::Loreline.Internal.Format.JsonPrinter.print(((object) (@value) ), replacer, ( (pretty1) ? ("  ") : (null) ));
		}
		
		
		public static object parse(string json) {
			return new global::Loreline.Internal.Format.JsonParser(((string) (json) )).doParse();
		}
		
		
	}
}


