// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Root {
	public class Reflect : global::Loreline.Internal.Lang.HxObject {
		
		public Reflect(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public Reflect() {
			global::Loreline.Internal.Root.Reflect.__hx_ctor__Reflect(this);
		}
		
		
		protected static void __hx_ctor__Reflect(global::Loreline.Internal.Root.Reflect __hx_this) {
		}
		
		
		public static bool hasField(object o, string field) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				return ( ihx.__hx_getField(field, global::Loreline.Internal.Lang.FieldLookup.hash(field), false, true, false) != global::Loreline.Internal.Lang.Runtime.undefined );
			}
			
			return global::Loreline.Internal.Lang.Runtime.slowHasField(o, field);
		}
		
		
		public static object field(object o, string field) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				return ihx.__hx_getField(field, global::Loreline.Internal.Lang.FieldLookup.hash(field), false, false, false);
			}
			
			return global::Loreline.Internal.Lang.Runtime.slowGetField(o, field, false);
		}
		
		
		public static void setField(object o, string field, object @value) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				ihx.__hx_setField(field, global::Loreline.Internal.Lang.FieldLookup.hash(field), @value, false);
			}
			else {
				global::Loreline.Internal.Lang.Runtime.slowSetField(o, field, @value);
			}
			
		}
		
		
		public static object getProperty(object o, string field) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				return ihx.__hx_getField(field, global::Loreline.Internal.Lang.FieldLookup.hash(field), false, false, true);
			}
			
			if (global::Loreline.Internal.Lang.Runtime.slowHasField(o, global::Loreline.Internal.Lang.Runtime.concat("get_", field))) {
				return global::Loreline.Internal.Lang.Runtime.slowCallField(o, global::Loreline.Internal.Lang.Runtime.concat("get_", field), null);
			}
			
			return global::Loreline.Internal.Lang.Runtime.slowGetField(o, field, false);
		}
		
		
		public static void setProperty(object o, string field, object @value) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				ihx.__hx_setField(field, global::Loreline.Internal.Lang.FieldLookup.hash(field), @value, true);
			}
			else if (global::Loreline.Internal.Lang.Runtime.slowHasField(o, global::Loreline.Internal.Lang.Runtime.concat("set_", field))) {
				global::Loreline.Internal.Lang.Runtime.slowCallField(o, global::Loreline.Internal.Lang.Runtime.concat("set_", field), new object[]{((object) (@value) )});
			}
			else {
				global::Loreline.Internal.Lang.Runtime.slowSetField(o, field, @value);
			}
			
		}
		
		
		public static object callMethod(object o, object func, global::Loreline.Internal.Root.Array args) {
			object[] ret = new object[((int) (global::Loreline.Internal.Lang.Runtime.getField_f(args, "length", 520590566, true)) )];
			global::Loreline.Internal.Cs.Lib.p_nativeArray<object>(((global::Loreline.Internal.Root.Array<object>) (global::Loreline.Internal.Root.Array<object>.__hx_cast<object>(((global::Loreline.Internal.Root.Array) (args) ))) ), ((global::System.Array) (ret) ));
			object[] args1 = ret;
			return (((global::Loreline.Internal.Lang.Function) (func) )).__hx_invokeDynamic(args1);
		}
		
		
		public static global::Loreline.Internal.Root.Array<string> fields(object o) {
			global::Loreline.Internal.Lang.IHxObject ihx = ( o as global::Loreline.Internal.Lang.IHxObject );
			if (( ihx != null )) {
				global::Loreline.Internal.Root.Array<string> ret = new global::Loreline.Internal.Root.Array<string>(new string[]{});
				ihx.__hx_getFields(ret);
				return ret;
			}
			else if (( o is global::System.Type )) {
				return global::Loreline.Internal.Root.Type.getClassFields(((global::System.Type) (o) ));
			}
			else {
				return global::Loreline.Internal.Root.Reflect.instanceFields(o.GetType());
			}
			
		}
		
		
		public static global::Loreline.Internal.Root.Array<string> instanceFields(global::System.Type c) {
			global::System.Type c1 = ((global::System.Type) (c) );
			global::Loreline.Internal.Root.Array<string> ret = new global::Loreline.Internal.Root.Array<string>(new string[]{});
			global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags> initial = new global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags>(global::System.Reflection.BindingFlags.Public, true);
			global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags> initial1 = new global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags>(( (((global::System.Reflection.BindingFlags) (( ( ! (initial.hasValue) ) ? (default(global::System.Reflection.BindingFlags)) : ((initial).@value) )) )) | ((global::System.Reflection.BindingFlags) (global::System.Reflection.BindingFlags.Instance) ) ), true);
			global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags> initial2 = new global::Loreline.Internal.Lang.Null<global::System.Reflection.BindingFlags>(( (((global::System.Reflection.BindingFlags) (( ( ! (initial1.hasValue) ) ? (default(global::System.Reflection.BindingFlags)) : ((initial1).@value) )) )) | ((global::System.Reflection.BindingFlags) (global::System.Reflection.BindingFlags.FlattenHierarchy) ) ), true);
			global::System.Reflection.FieldInfo[] mis = c1.GetFields(((global::System.Reflection.BindingFlags) (( ( ! (initial2.hasValue) ) ? (default(global::System.Reflection.BindingFlags)) : ((initial2).@value) )) ));
			{
				int _g = 0;
				int _g1 = ( mis as global::System.Array ).Length;
				while (( _g < _g1 )) {
					int i = _g++;
					global::System.Reflection.FieldInfo i1 = ((global::System.Reflection.FieldInfo) (mis[i]) );
					ret.push(( i1 as global::System.Reflection.MemberInfo ).Name);
				}
				
			}
			
			return ret;
		}
		
		
		public static int compare<T>(T a, T b) {
			return global::Loreline.Internal.Lang.Runtime.compare(a, b);
		}
		
		
		public static bool isObject(object v) {
			if (( v != null )) {
				return  ! ((( ( ( v is global::Loreline.Internal.Lang.Enum ) || ( v is global::Loreline.Internal.Lang.Function ) ) || ( v is global::System.ValueType ) ))) ;
			}
			else {
				return false;
			}
			
		}
		
		
		public static bool isEnumValue(object v) {
			if (( v != null )) {
				if ( ! (( v is global::Loreline.Internal.Lang.Enum )) ) {
					return ( v is global::System.Enum );
				}
				else {
					return true;
				}
				
			}
			else {
				return false;
			}
			
		}
		
		
		public static object makeVarArgs(global::Loreline.Internal.Lang.Function f) {
			return new global::Loreline.Internal.Lang.VarArgsFunction(f);
		}
		
		
	}
}


