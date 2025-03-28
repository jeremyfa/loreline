// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Runtime {
	public class Equal : global::Loreline.Internal.Lang.HxObject {
		
		public Equal(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public Equal() {
			global::Loreline.Runtime.Equal.__hx_ctor_loreline_Equal(this);
		}
		
		
		protected static void __hx_ctor_loreline_Equal(global::Loreline.Runtime.Equal __hx_this) {
		}
		
		
		public static bool equal(global::Loreline.Runtime.Interpreter interpreter, object a, object b) {
			if (global::Loreline.Internal.Lang.Runtime.eq(a, b)) {
				return true;
			}
			
			if (global::Loreline.Runtime.Arrays.isArray(a)) {
				if (global::Loreline.Runtime.Arrays.isArray(b)) {
					return global::Loreline.Runtime.Equal.arrayEqual(interpreter, a, b);
				}
				
				return false;
			}
			else if (( a is global::Loreline.Internal.Ds.StringMap )) {
				if (( b is global::Loreline.Internal.Ds.StringMap )) {
					return global::Loreline.Runtime.Equal.stringMapEqual(interpreter, ((global::Loreline.Internal.Ds.StringMap<object>) (global::Loreline.Internal.Ds.StringMap<object>.__hx_cast<object>(((global::Loreline.Internal.Ds.StringMap) (a) ))) ), ((global::Loreline.Internal.Ds.StringMap<object>) (global::Loreline.Internal.Ds.StringMap<object>.__hx_cast<object>(((global::Loreline.Internal.Ds.StringMap) (b) ))) ));
				}
				
				return false;
			}
			else if (( a is global::Loreline.Internal.Ds.IntMap )) {
				if (( b is global::Loreline.Internal.Ds.IntMap )) {
					return global::Loreline.Runtime.Equal.intMapEqual(interpreter, ((global::Loreline.Internal.Ds.IntMap<object>) (global::Loreline.Internal.Ds.IntMap<object>.__hx_cast<object>(((global::Loreline.Internal.Ds.IntMap) (a) ))) ), ((global::Loreline.Internal.Ds.IntMap<object>) (global::Loreline.Internal.Ds.IntMap<object>.__hx_cast<object>(((global::Loreline.Internal.Ds.IntMap) (b) ))) ));
				}
				
				return false;
			}
			else if (global::Loreline.Runtime.Objects.isFields(a)) {
				if (global::Loreline.Runtime.Objects.isFields(b)) {
					return global::Loreline.Runtime.Equal.objectFieldsEqual(interpreter, a, b);
				}
				
				return false;
			}
			
			return false;
		}
		
		
		public static bool objectFieldsEqual(global::Loreline.Runtime.Interpreter interpreter, object a, object b) {
			{
				int _g = 0;
				global::Loreline.Internal.Root.Array<string> _g1 = global::Loreline.Runtime.Objects.getFields(interpreter, a);
				while (( _g < _g1.length )) {
					string field = _g1[_g];
					 ++ _g;
					if ((  ! (global::Loreline.Runtime.Objects.fieldExists(interpreter, b, field))  ||  ! (global::Loreline.Runtime.Equal.equal(interpreter, global::Loreline.Runtime.Objects.getField(interpreter, a, field), global::Loreline.Runtime.Objects.getField(interpreter, b, field)))  )) {
						return false;
					}
					
				}
				
			}
			
			{
				int _g2 = 0;
				global::Loreline.Internal.Root.Array<string> _g3 = global::Loreline.Runtime.Objects.getFields(interpreter, b);
				while (( _g2 < _g3.length )) {
					string field1 = _g3[_g2];
					 ++ _g2;
					if ( ! (global::Loreline.Runtime.Objects.fieldExists(interpreter, a, field1)) ) {
						return false;
					}
					
				}
				
			}
			
			return true;
		}
		
		
		public static bool arrayEqual(global::Loreline.Runtime.Interpreter interpreter, object a, object b) {
			int lenA = global::Loreline.Runtime.Arrays.arrayLength(a);
			int lenB = global::Loreline.Runtime.Arrays.arrayLength(b);
			if (( lenA != lenB )) {
				return false;
			}
			
			{
				int _g = 0;
				int _g1 = lenA;
				while (( _g < _g1 )) {
					int i = _g++;
					if ( ! (global::Loreline.Runtime.Equal.equal(interpreter, global::Loreline.Runtime.Arrays.arrayGet(a, i), global::Loreline.Runtime.Arrays.arrayGet(b, i))) ) {
						return false;
					}
					
				}
				
			}
			
			return true;
		}
		
		
		public static bool stringMapEqual(global::Loreline.Runtime.Interpreter interpreter, global::Loreline.Internal.Ds.StringMap<object> a, global::Loreline.Internal.Ds.StringMap<object> b) {
			{
				global::Loreline.Internal.IMap<string, object> map = a;
				global::Loreline.Internal.IMap<string, object> _g_map = map;
				object _g_keys = map.keys();
				while (global::Loreline.Internal.Lang.Runtime.toBool(global::Loreline.Internal.Lang.Runtime.callField(_g_keys, "hasNext", 407283053, null))) {
					string key = global::Loreline.Internal.Lang.Runtime.toString(global::Loreline.Internal.Lang.Runtime.callField(_g_keys, "next", 1224901875, null));
					object _g_value = (_g_map.@get(key)).toDynamic();
					string _g_key = key;
					string key1 = _g_key;
					object val = _g_value;
					{
						if ( ! (b.exists(key1)) ) {
							return false;
						}
						
						if ( ! (global::Loreline.Runtime.Equal.equal(interpreter, (b.@get(key1)).toDynamic(), val)) ) {
							return false;
						}
						
					}
					
				}
				
			}
			
			{
				object key2 = ((object) (new global::Loreline.Internal.Ds._StringMap.StringMapKeyIterator<object>(((global::Loreline.Internal.Ds.StringMap<object>) (b) ))) );
				while (global::Loreline.Internal.Lang.Runtime.toBool(global::Loreline.Internal.Lang.Runtime.callField(key2, "hasNext", 407283053, null))) {
					string key3 = global::Loreline.Internal.Lang.Runtime.toString(global::Loreline.Internal.Lang.Runtime.callField(key2, "next", 1224901875, null));
					if ( ! (a.exists(key3)) ) {
						return false;
					}
					
				}
				
			}
			
			return true;
		}
		
		
		public static bool intMapEqual(global::Loreline.Runtime.Interpreter interpreter, global::Loreline.Internal.Ds.IntMap<object> a, global::Loreline.Internal.Ds.IntMap<object> b) {
			{
				global::Loreline.Internal.IMap<int, object> map = a;
				global::Loreline.Internal.IMap<int, object> _g_map = map;
				object _g_keys = map.keys();
				while (global::Loreline.Internal.Lang.Runtime.toBool(global::Loreline.Internal.Lang.Runtime.callField(_g_keys, "hasNext", 407283053, null))) {
					int key = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(global::Loreline.Internal.Lang.Runtime.callField(_g_keys, "next", 1224901875, null))) );
					object _g_value = (_g_map.@get(key)).toDynamic();
					int _g_key = key;
					int key1 = _g_key;
					object val = _g_value;
					{
						if ( ! (b.exists(key1)) ) {
							return false;
						}
						
						if ( ! (global::Loreline.Runtime.Equal.equal(interpreter, (b.@get(key1)).toDynamic(), val)) ) {
							return false;
						}
						
					}
					
				}
				
			}
			
			{
				object key2 = ((object) (new global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<object>(((global::Loreline.Internal.Ds.IntMap<object>) (b) ))) );
				while (global::Loreline.Internal.Lang.Runtime.toBool(global::Loreline.Internal.Lang.Runtime.callField(key2, "hasNext", 407283053, null))) {
					int key3 = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(global::Loreline.Internal.Lang.Runtime.callField(key2, "next", 1224901875, null))) );
					if ( ! (a.exists(key3)) ) {
						return false;
					}
					
				}
				
			}
			
			return true;
		}
		
		
	}
}


