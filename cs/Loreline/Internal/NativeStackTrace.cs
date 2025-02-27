// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060
namespace Loreline.Internal {
	public class NativeStackTrace : global::Loreline.Internal.Lang.HxObject {
		
		public NativeStackTrace(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public NativeStackTrace() {
			global::Loreline.Internal.NativeStackTrace.__hx_ctor_haxe_NativeStackTrace(this);
		}
		
		
		protected static void __hx_ctor_haxe_NativeStackTrace(global::Loreline.Internal.NativeStackTrace __hx_this) {
		}
		
		
		public static global::Loreline.Internal.Root.Array<object> toHaxe(global::System.Diagnostics.StackTrace native, global::Loreline.Internal.Lang.Null<int> skip) {
			int skip1 = ( ( ! (skip.hasValue) ) ? (0) : ((skip).@value) );
			global::Loreline.Internal.Root.Array<object> stack = new global::Loreline.Internal.Root.Array<object>(new object[]{});
			if (( native == null )) {
				return stack;
			}
			
			int cnt = 0;
			{
				int _g = 0;
				int _g1 = native.FrameCount;
				while (( _g < _g1 )) {
					int i = _g++;
					global::System.Diagnostics.StackFrame frame = native.GetFrame(((int) (i) ));
					global::System.Reflection.MethodBase m = frame.GetMethod();
					if (( m == null )) {
						continue;
					}
					
					if (( skip1 > cnt++ )) {
						continue;
					}
					
					global::Loreline.Internal.StackItem method = global::Loreline.Internal.StackItem.Method(( m as global::System.Reflection.MemberInfo ).ReflectedType.ToString(), ( m as global::System.Reflection.MemberInfo ).Name);
					string fileName = frame.GetFileName();
					int lineNumber = frame.GetFileLineNumber();
					if (( ( fileName != null ) || ( lineNumber >= 0 ) )) {
						stack.push(global::Loreline.Internal.StackItem.FilePos(method, fileName, lineNumber, default(global::Loreline.Internal.Lang.Null<int>)));
					}
					else {
						stack.push(method);
					}
					
				}
				
			}
			
			return stack;
		}
		
		
	}
}


