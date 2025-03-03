// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Iterators {
	public class ArrayIterator<T> : global::Loreline.Internal.Lang.HxObject, global::Loreline.Internal.Iterators.ArrayIterator {
		
		public ArrayIterator(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public ArrayIterator(global::Loreline.Internal.Root.Array<T> array) {
			global::Loreline.Internal.Iterators.ArrayIterator<object>.__hx_ctor_haxe_iterators_ArrayIterator<T>(((global::Loreline.Internal.Iterators.ArrayIterator<T>) (this) ), ((global::Loreline.Internal.Root.Array<T>) (array) ));
		}
		
		
		protected static void __hx_ctor_haxe_iterators_ArrayIterator<T_c>(global::Loreline.Internal.Iterators.ArrayIterator<T_c> __hx_this, global::Loreline.Internal.Root.Array<T_c> array) {
			__hx_this.current = 0;
			{
				__hx_this.array = array;
			}
			
		}
		
		
		public static object __hx_cast<T_c_c>(global::Loreline.Internal.Iterators.ArrayIterator me) {
			return ( (( me != null )) ? (me.haxe_iterators_ArrayIterator_cast<T_c_c>()) : default(object) );
		}
		
		
		public virtual object haxe_iterators_ArrayIterator_cast<T_c>() {
			if (global::Loreline.Internal.Lang.Runtime.eq(typeof(T), typeof(T_c))) {
				return this;
			}
			
			global::Loreline.Internal.Iterators.ArrayIterator<T_c> new_me = new global::Loreline.Internal.Iterators.ArrayIterator<T_c>(((global::Loreline.Internal.Lang.EmptyObject) (global::Loreline.Internal.Lang.EmptyObject.EMPTY) ));
			global::Loreline.Internal.Root.Array<string> fields = global::Loreline.Internal.Root.Reflect.fields(this);
			int i = 0;
			while (( i < fields.length )) {
				string field = fields[i++];
				global::Loreline.Internal.Root.Reflect.setField(new_me, field, global::Loreline.Internal.Root.Reflect.field(this, field));
			}
			
			return new_me;
		}
		
		
		public global::Loreline.Internal.Root.Array<T> array;
		
		public int current;
		
		public bool hasNext() {
			return ( this.current < this.array.length );
		}
		
		
		public T next() {
			return this.array[this.current++];
		}
		
		
		public override double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1273207865:
					{
						this.current = ((int) (@value) );
						return @value;
					}
					
					
					default:
					{
						return base.__hx_setField_f(field, hash, @value, handleProperties);
					}
					
				}
				
			}
		}
		
		
		public override object __hx_setField(string field, int hash, object @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1273207865:
					{
						this.current = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 630156697:
					{
						this.array = ((global::Loreline.Internal.Root.Array<T>) (global::Loreline.Internal.Root.Array<object>.__hx_cast<T>(((global::Loreline.Internal.Root.Array) (@value) ))) );
						return @value;
					}
					
					
					default:
					{
						return base.__hx_setField(field, hash, @value, handleProperties);
					}
					
				}
				
			}
		}
		
		
		public override object __hx_getField(string field, int hash, bool throwErrors, bool isCheck, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1224901875:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "next", 1224901875)) );
					}
					
					
					case 407283053:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "hasNext", 407283053)) );
					}
					
					
					case 1273207865:
					{
						return this.current;
					}
					
					
					case 630156697:
					{
						return this.array;
					}
					
					
					default:
					{
						return base.__hx_getField(field, hash, throwErrors, isCheck, handleProperties);
					}
					
				}
				
			}
		}
		
		
		public override double __hx_getField_f(string field, int hash, bool throwErrors, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1273207865:
					{
						return ((double) (this.current) );
					}
					
					
					default:
					{
						return base.__hx_getField_f(field, hash, throwErrors, handleProperties);
					}
					
				}
				
			}
		}
		
		
		public override object __hx_invokeField(string field, int hash, object[] dynargs) {
			unchecked {
				switch (hash) {
					case 1224901875:
					{
						return this.next();
					}
					
					
					case 407283053:
					{
						return this.hasNext();
					}
					
					
					default:
					{
						return base.__hx_invokeField(field, hash, dynargs);
					}
					
				}
				
			}
		}
		
		
		public override void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr) {
			baseArr.push("current");
			baseArr.push("array");
			base.__hx_getFields(baseArr);
		}
		
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Iterators {
	[global::Loreline.Internal.Lang.GenericInterface(typeof(global::Loreline.Internal.Iterators.ArrayIterator<object>))]
	public interface ArrayIterator : global::Loreline.Internal.Lang.IHxObject, global::Loreline.Internal.Lang.IGenericObject {
		
		object haxe_iterators_ArrayIterator_cast<T_c>();
		
		bool hasNext();
		
	}
}


