// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Root {
	public class StringTools : global::Loreline.Internal.Lang.HxObject {
		
		public StringTools(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public StringTools() {
			global::Loreline.Internal.Root.StringTools.__hx_ctor__StringTools(this);
		}
		
		
		protected static void __hx_ctor__StringTools(global::Loreline.Internal.Root.StringTools __hx_this) {
		}
		
		
		public static string lpad(string s, string c, int l) {
			if (( c.Length <= 0 )) {
				return s;
			}
			
			global::System.Text.StringBuilder buf_b = new global::System.Text.StringBuilder();
			l -= s.Length;
			while (( buf_b.Length < l )) {
				buf_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(c)) ));
			}
			
			buf_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(s)) ));
			return buf_b.ToString();
		}
		
		
	}
}


