// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Ds {
	public class IntMap<T> : global::Loreline.Internal.Lang.HxObject, global::Loreline.Internal.Ds.IntMap, global::Loreline.Internal.IMap<int, T> {
		
		public IntMap(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public IntMap() {
			global::Loreline.Internal.Ds.IntMap<object>.__hx_ctor_haxe_ds_IntMap<T>(((global::Loreline.Internal.Ds.IntMap<T>) (this) ));
		}
		
		
		protected static void __hx_ctor_haxe_ds_IntMap<T_c>(global::Loreline.Internal.Ds.IntMap<T_c> __hx_this) {
			unchecked {
				__hx_this.cachedIndex = -1;
			}
		}
		
		
		public static object __hx_cast<T_c_c>(global::Loreline.Internal.Ds.IntMap me) {
			return ( (( me != null )) ? (me.haxe_ds_IntMap_cast<T_c_c>()) : default(object) );
		}
		
		
		public virtual object haxe_ds_IntMap_cast<T_c>() {
			unchecked {
				if (global::Loreline.Internal.Lang.Runtime.eq(typeof(T), typeof(T_c))) {
					return this;
				}
				
				global::Loreline.Internal.Ds.IntMap<T_c> new_me = new global::Loreline.Internal.Ds.IntMap<T_c>(global::Loreline.Internal.Lang.EmptyObject.EMPTY);
				global::Loreline.Internal.Root.Array<string> fields = global::Loreline.Internal.Root.Reflect.fields(this);
				int i = 0;
				while (( i < fields.length )) {
					string field = fields[i++];
					switch (field) {
						case "vals":
						{
							if (( this.vals != null )) {
								T_c[] __temp_new_arr1 = new T_c[this.vals.Length];
								int __temp_i2 = -1;
								while ((  ++ __temp_i2 < this.vals.Length )) {
									object __temp_obj3 = ((object) (this.vals[__temp_i2]) );
									if (( __temp_obj3 != null )) {
										__temp_new_arr1[__temp_i2] = global::Loreline.Internal.Lang.Runtime.genericCast<T_c>(__temp_obj3);
									}
									
								}
								
								new_me.vals = __temp_new_arr1;
							}
							else {
								new_me.vals = null;
							}
							
							break;
						}
						
						
						default:
						{
							global::Loreline.Internal.Root.Reflect.setField(new_me, field, global::Loreline.Internal.Root.Reflect.field(this, field));
							break;
						}
						
					}
					
				}
				
				return new_me;
			}
		}
		
		
		public virtual object haxe_IMap_cast<K_c, V_c>() {
			return this.haxe_ds_IntMap_cast<T>();
		}
		
		
		public int[] flags;
		
		public int[] _keys;
		
		public T[] vals;
		
		public int nBuckets;
		
		public int size;
		
		public int nOccupied;
		
		public int upperBound;
		
		public int cachedKey;
		
		public int cachedIndex;
		
		public virtual void @set(int key, T @value) {
			unchecked {
				int targetIndex = default(int);
				if (( this.nOccupied >= this.upperBound )) {
					if (( this.nBuckets > ( this.size << 1 ) )) {
						this.resize(( this.nBuckets - 1 ));
					}
					else {
						this.resize(( this.nBuckets + 1 ));
					}
					
				}
				
				int[] flags = this.flags;
				int[] _keys = this._keys;
				{
					int mask = ( this.nBuckets - 1 );
					int hashedKey = key;
					int curIndex = ( hashedKey & mask );
					int delKey = -1;
					int curFlag = 0;
					if (( (( ( ((int) (( ((uint) (flags[( curIndex >> 4 )]) ) >> (( (( curIndex & 15 )) << 1 )) )) ) & 3 ) & 2 )) != 0 )) {
						targetIndex = curIndex;
					}
					else {
						int inc = ( (( ( ( hashedKey >> 3 ) ^ ( hashedKey << 3 ) ) | 1 )) & mask );
						int last = curIndex;
						while (true) {
							bool tmp = default(bool);
							if (( _keys[curIndex] != key )) {
								curFlag = ( ((int) (( ((uint) (flags[( curIndex >> 4 )]) ) >> (( (( curIndex & 15 )) << 1 )) )) ) & 3 );
								tmp = ( (( curFlag & 2 )) != 0 );
							}
							else {
								tmp = true;
							}
							
							if (tmp) {
								break;
							}
							
							if (( ( delKey == -1 ) && ( (( curFlag & 1 )) != 0 ) )) {
								delKey = curIndex;
							}
							
							curIndex = ( ( curIndex + inc ) & mask );
						}
						
						if (( ( delKey != -1 ) && ( (( ( ((int) (( ((uint) (flags[( curIndex >> 4 )]) ) >> (( (( curIndex & 15 )) << 1 )) )) ) & 3 ) & 2 )) != 0 ) )) {
							targetIndex = delKey;
						}
						else {
							targetIndex = curIndex;
						}
						
					}
					
				}
				
				int flag = ( ((int) (( ((uint) (flags[( targetIndex >> 4 )]) ) >> (( (( targetIndex & 15 )) << 1 )) )) ) & 3 );
				if (( (( flag & 2 )) != 0 )) {
					_keys[targetIndex] = key;
					this.vals[targetIndex] = @value;
					flags[( targetIndex >> 4 )] &=  ~ ((( 3 << (( (( targetIndex & 15 )) << 1 )) ))) ;
					this.size++;
					this.nOccupied++;
				}
				else if (( (( flag & 1 )) != 0 )) {
					_keys[targetIndex] = key;
					this.vals[targetIndex] = @value;
					flags[( targetIndex >> 4 )] &=  ~ ((( 3 << (( (( targetIndex & 15 )) << 1 )) ))) ;
					this.size++;
				}
				else {
					this.vals[targetIndex] = @value;
				}
				
			}
		}
		
		
		public int lookup(int key) {
			unchecked {
				if (( this.nBuckets != 0 )) {
					int[] flags = this.flags;
					int[] _keys = this._keys;
					int mask = ( this.nBuckets - 1 );
					int k = key;
					int index = ( k & mask );
					int curFlag = -1;
					int inc = ( (( ( ( k >> 3 ) ^ ( k << 3 ) ) | 1 )) & mask );
					int last = index;
					while (true) {
						if (( _keys[index] == key )) {
							curFlag = ( ((int) (( ((uint) (flags[( index >> 4 )]) ) >> (( (( index & 15 )) << 1 )) )) ) & 3 );
							if (( (( curFlag & 2 )) != 0 )) {
								index = ( ( index + inc ) & mask );
								if ( ! ((( index != last ))) ) {
									break;
								}
								else {
									continue;
								}
								
							}
							else if (( (( curFlag & 1 )) != 0 )) {
								return -1;
							}
							else {
								return index;
							}
							
						}
						else {
							index = ( ( index + inc ) & mask );
						}
						
						if ( ! ((( index != last ))) ) {
							break;
						}
						
					}
					
				}
				
				return -1;
			}
		}
		
		
		public virtual global::Loreline.Internal.Lang.Null<T> @get(int key) {
			unchecked {
				int idx = -1;
				bool tmp = default(bool);
				if (( this.cachedKey == key )) {
					idx = this.cachedIndex;
					tmp = ( idx != -1 );
				}
				else {
					tmp = false;
				}
				
				if (tmp) {
					return new global::Loreline.Internal.Lang.Null<T>(global::Loreline.Internal.Lang.Runtime.genericCast<T>(this.vals[idx]), true);
				}
				
				idx = this.lookup(key);
				if (( idx != -1 )) {
					this.cachedKey = key;
					this.cachedIndex = idx;
					return new global::Loreline.Internal.Lang.Null<T>(global::Loreline.Internal.Lang.Runtime.genericCast<T>(this.vals[idx]), true);
				}
				
				return default(global::Loreline.Internal.Lang.Null<T>);
			}
		}
		
		
		public virtual bool exists(int key) {
			unchecked {
				int idx = -1;
				bool tmp = default(bool);
				if (( this.cachedKey == key )) {
					idx = this.cachedIndex;
					tmp = ( idx != -1 );
				}
				else {
					tmp = false;
				}
				
				if (tmp) {
					return true;
				}
				
				idx = this.lookup(key);
				if (( idx != -1 )) {
					this.cachedKey = key;
					this.cachedIndex = idx;
					return true;
				}
				
				return false;
			}
		}
		
		
		public void resize(int newNBuckets) {
			unchecked {
				int[] newFlags = null;
				int j = 1;
				{
					int x = newNBuckets;
					 -- x;
					x |= ((int) (( ((uint) (x) ) >> 1 )) );
					x |= ((int) (( ((uint) (x) ) >> 2 )) );
					x |= ((int) (( ((uint) (x) ) >> 4 )) );
					x |= ((int) (( ((uint) (x) ) >> 8 )) );
					x |= ((int) (( ((uint) (x) ) >> 16 )) );
					 ++ x;
					newNBuckets = x;
					if (( newNBuckets < 4 )) {
						newNBuckets = 4;
					}
					
					if (( this.size >= ( ( newNBuckets * 0.7 ) + 0.5 ) )) {
						j = 0;
					}
					else {
						int nfSize = ( (( newNBuckets < 16 )) ? (1) : (( newNBuckets >> 4 )) );
						newFlags = new int[nfSize];
						{
							int _g = 0;
							int _g1 = nfSize;
							while (( _g < _g1 )) {
								int i = _g++;
								newFlags[i] = -1431655766;
							}
							
						}
						
						if (( this.nBuckets < newNBuckets )) {
							int[] k = new int[newNBuckets];
							if (( this._keys != null )) {
								global::System.Array.Copy(((global::System.Array) (this._keys) ), ((int) (0) ), ((global::System.Array) (k) ), ((int) (0) ), ((int) (this.nBuckets) ));
							}
							
							this._keys = k;
							T[] v = new T[newNBuckets];
							if (( this.vals != null )) {
								global::System.Array.Copy(((global::System.Array) (this.vals) ), ((int) (0) ), ((global::System.Array) (v) ), ((int) (0) ), ((int) (this.nBuckets) ));
							}
							
							this.vals = v;
						}
						
					}
					
				}
				
				if (( j != 0 )) {
					this.cachedKey = 0;
					this.cachedIndex = -1;
					j = -1;
					int nBuckets = this.nBuckets;
					int[] _keys = this._keys;
					T[] vals = this.vals;
					int[] flags = this.flags;
					int newMask = ( newNBuckets - 1 );
					while ((  ++ j < nBuckets )) {
						if (( (( ((int) (( ((uint) (flags[( j >> 4 )]) ) >> (( (( j & 15 )) << 1 )) )) ) & 3 )) == 0 )) {
							int key = _keys[j];
							T val = global::Loreline.Internal.Lang.Runtime.genericCast<T>(vals[j]);
							vals[j] = default(T);
							flags[( j >> 4 )] |= ( 1 << (( (( j & 15 )) << 1 )) );
							while (true) {
								int k1 = key;
								int inc = ( (( ( ( k1 >> 3 ) ^ ( k1 << 3 ) ) | 1 )) & newMask );
								int i1 = ( k1 & newMask );
								while (( (( ( ((int) (( ((uint) (newFlags[( i1 >> 4 )]) ) >> (( (( i1 & 15 )) << 1 )) )) ) & 3 ) & 2 )) == 0 )) {
									i1 = ( ( i1 + inc ) & newMask );
								}
								
								newFlags[( i1 >> 4 )] &=  ~ ((( 2 << (( (( i1 & 15 )) << 1 )) ))) ;
								if (( ( i1 < nBuckets ) && ( (( ((int) (( ((uint) (flags[( i1 >> 4 )]) ) >> (( (( i1 & 15 )) << 1 )) )) ) & 3 )) == 0 ) )) {
									{
										int tmp = _keys[i1];
										_keys[i1] = key;
										key = tmp;
									}
									
									{
										T tmp1 = global::Loreline.Internal.Lang.Runtime.genericCast<T>(vals[i1]);
										vals[i1] = val;
										val = tmp1;
									}
									
									flags[( i1 >> 4 )] |= ( 1 << (( (( i1 & 15 )) << 1 )) );
								}
								else {
									_keys[i1] = key;
									vals[i1] = val;
									break;
								}
								
							}
							
						}
						
					}
					
					if (( nBuckets > newNBuckets )) {
						{
							int[] k2 = new int[newNBuckets];
							global::System.Array.Copy(((global::System.Array) (_keys) ), ((int) (0) ), ((global::System.Array) (k2) ), ((int) (0) ), ((int) (newNBuckets) ));
							this._keys = k2;
						}
						
						{
							T[] v1 = new T[newNBuckets];
							global::System.Array.Copy(((global::System.Array) (vals) ), ((int) (0) ), ((global::System.Array) (v1) ), ((int) (0) ), ((int) (newNBuckets) ));
							this.vals = v1;
						}
						
					}
					
					this.flags = newFlags;
					this.nBuckets = newNBuckets;
					this.nOccupied = this.size;
					this.upperBound = ((int) (( ( newNBuckets * 0.7 ) + .5 )) );
				}
				
			}
		}
		
		
		public object keys() {
			return new global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<T>(((global::Loreline.Internal.Ds.IntMap<T>) (this) ));
		}
		
		
		public override double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 922671056:
					{
						this.cachedIndex = ((int) (@value) );
						return @value;
					}
					
					
					case 1395555037:
					{
						this.cachedKey = ((int) (@value) );
						return @value;
					}
					
					
					case 2022294396:
					{
						this.upperBound = ((int) (@value) );
						return @value;
					}
					
					
					case 480756972:
					{
						this.nOccupied = ((int) (@value) );
						return @value;
					}
					
					
					case 1280549057:
					{
						this.size = ((int) (@value) );
						return @value;
					}
					
					
					case 1537812987:
					{
						this.nBuckets = ((int) (@value) );
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
					case 922671056:
					{
						this.cachedIndex = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 1395555037:
					{
						this.cachedKey = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 2022294396:
					{
						this.upperBound = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 480756972:
					{
						this.nOccupied = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 1280549057:
					{
						this.size = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 1537812987:
					{
						this.nBuckets = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 1313416818:
					{
						this.vals = ((T[]) (@value) );
						return @value;
					}
					
					
					case 2048392659:
					{
						this._keys = ((int[]) (@value) );
						return @value;
					}
					
					
					case 42740551:
					{
						this.flags = ((int[]) (@value) );
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
					case 1191633396:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "keys", 1191633396)) );
					}
					
					
					case 142301684:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "resize", 142301684)) );
					}
					
					
					case 1071652316:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "exists", 1071652316)) );
					}
					
					
					case 5144726:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "get", 5144726)) );
					}
					
					
					case 1639293562:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "lookup", 1639293562)) );
					}
					
					
					case 5741474:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "set", 5741474)) );
					}
					
					
					case 922671056:
					{
						return this.cachedIndex;
					}
					
					
					case 1395555037:
					{
						return this.cachedKey;
					}
					
					
					case 2022294396:
					{
						return this.upperBound;
					}
					
					
					case 480756972:
					{
						return this.nOccupied;
					}
					
					
					case 1280549057:
					{
						return this.size;
					}
					
					
					case 1537812987:
					{
						return this.nBuckets;
					}
					
					
					case 1313416818:
					{
						return this.vals;
					}
					
					
					case 2048392659:
					{
						return this._keys;
					}
					
					
					case 42740551:
					{
						return this.flags;
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
					case 922671056:
					{
						return ((double) (this.cachedIndex) );
					}
					
					
					case 1395555037:
					{
						return ((double) (this.cachedKey) );
					}
					
					
					case 2022294396:
					{
						return ((double) (this.upperBound) );
					}
					
					
					case 480756972:
					{
						return ((double) (this.nOccupied) );
					}
					
					
					case 1280549057:
					{
						return ((double) (this.size) );
					}
					
					
					case 1537812987:
					{
						return ((double) (this.nBuckets) );
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
					case 1191633396:
					{
						return this.keys();
					}
					
					
					case 142301684:
					{
						this.resize(((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[0])) ));
						break;
					}
					
					
					case 1071652316:
					{
						return this.exists(((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[0])) ));
					}
					
					
					case 5144726:
					{
						return (this.@get(((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[0])) ))).toDynamic();
					}
					
					
					case 1639293562:
					{
						return this.lookup(((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[0])) ));
					}
					
					
					case 5741474:
					{
						this.@set(((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[0])) ), global::Loreline.Internal.Lang.Runtime.genericCast<T>(dynargs[1]));
						break;
					}
					
					
					default:
					{
						return base.__hx_invokeField(field, hash, dynargs);
					}
					
				}
				
				return null;
			}
		}
		
		
		public override void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr) {
			baseArr.push("cachedIndex");
			baseArr.push("cachedKey");
			baseArr.push("upperBound");
			baseArr.push("nOccupied");
			baseArr.push("size");
			baseArr.push("nBuckets");
			baseArr.push("vals");
			baseArr.push("_keys");
			baseArr.push("flags");
			base.__hx_getFields(baseArr);
		}
		
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Ds {
	[global::Loreline.Internal.Lang.GenericInterface(typeof(global::Loreline.Internal.Ds.IntMap<object>))]
	public interface IntMap : global::Loreline.Internal.Lang.IHxObject, global::Loreline.Internal.Lang.IGenericObject {
		
		object haxe_ds_IntMap_cast<T_c>();
		
		object haxe_IMap_cast<K_c, V_c>();
		
		int lookup(int key);
		
		bool exists(int key);
		
		void resize(int newNBuckets);
		
		object keys();
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Ds._IntMap {
	public sealed class IntMapKeyIterator<T> : global::Loreline.Internal.Lang.HxObject, global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator {
		
		public IntMapKeyIterator(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public IntMapKeyIterator(global::Loreline.Internal.Ds.IntMap<T> m) {
			global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<object>.__hx_ctor_haxe_ds__IntMap_IntMapKeyIterator<T>(((global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<T>) (this) ), ((global::Loreline.Internal.Ds.IntMap<T>) (m) ));
		}
		
		
		private static void __hx_ctor_haxe_ds__IntMap_IntMapKeyIterator<T_c>(global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<T_c> __hx_this, global::Loreline.Internal.Ds.IntMap<T_c> m) {
			__hx_this.i = 0;
			__hx_this.m = m;
			__hx_this.len = m.nBuckets;
		}
		
		
		public static object __hx_cast<T_c_c>(global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator me) {
			return ( (( me != null )) ? (me.haxe_ds__IntMap_IntMapKeyIterator_cast<T_c_c>()) : default(object) );
		}
		
		
		public object haxe_ds__IntMap_IntMapKeyIterator_cast<T_c>() {
			if (global::Loreline.Internal.Lang.Runtime.eq(typeof(T), typeof(T_c))) {
				return this;
			}
			
			global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<T_c> new_me = new global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<T_c>(((global::Loreline.Internal.Lang.EmptyObject) (global::Loreline.Internal.Lang.EmptyObject.EMPTY) ));
			global::Loreline.Internal.Root.Array<string> fields = global::Loreline.Internal.Root.Reflect.fields(this);
			int i = 0;
			while (( i < fields.length )) {
				string field = fields[i++];
				global::Loreline.Internal.Root.Reflect.setField(new_me, field, global::Loreline.Internal.Root.Reflect.field(this, field));
			}
			
			return new_me;
		}
		
		
		public global::Loreline.Internal.Ds.IntMap<T> m;
		
		public int i;
		
		public int len;
		
		public bool hasNext() {
			unchecked {
				{
					int _g = this.i;
					int _g1 = this.len;
					while (( _g < _g1 )) {
						int j = _g++;
						if (( (( ((int) (( ((uint) (this.m.flags[( j >> 4 )]) ) >> (( (( j & 15 )) << 1 )) )) ) & 3 )) == 0 )) {
							this.i = j;
							return true;
						}
						
					}
					
				}
				
				return false;
			}
		}
		
		
		public int next() {
			int ret = this.m._keys[this.i];
			this.m.cachedIndex = this.i;
			this.m.cachedKey = ret;
			this.i++;
			return ret;
		}
		
		
		public override double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 5393365:
					{
						this.len = ((int) (@value) );
						return @value;
					}
					
					
					case 105:
					{
						this.i = ((int) (@value) );
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
					case 5393365:
					{
						this.len = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 105:
					{
						this.i = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 109:
					{
						this.m = ((global::Loreline.Internal.Ds.IntMap<T>) (global::Loreline.Internal.Ds.IntMap<object>.__hx_cast<T>(((global::Loreline.Internal.Ds.IntMap) (@value) ))) );
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
					
					
					case 5393365:
					{
						return this.len;
					}
					
					
					case 105:
					{
						return this.i;
					}
					
					
					case 109:
					{
						return this.m;
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
					case 5393365:
					{
						return ((double) (this.len) );
					}
					
					
					case 105:
					{
						return ((double) (this.i) );
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
			baseArr.push("len");
			baseArr.push("i");
			baseArr.push("m");
			base.__hx_getFields(baseArr);
		}
		
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Ds._IntMap {
	[global::Loreline.Internal.Lang.GenericInterface(typeof(global::Loreline.Internal.Ds._IntMap.IntMapKeyIterator<object>))]
	public interface IntMapKeyIterator : global::Loreline.Internal.Lang.IHxObject, global::Loreline.Internal.Lang.IGenericObject {
		
		object haxe_ds__IntMap_IntMapKeyIterator_cast<T_c>();
		
		bool hasNext();
		
		int next();
		
	}
}


