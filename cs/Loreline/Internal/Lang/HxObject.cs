// Generated by Haxe 4.3.6

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public interface IHxObject {
		
		object __hx_lookupField(string field, int hash, bool throwErrors, bool isCheck);
		
		double __hx_lookupField_f(string field, int hash, bool throwErrors);
		
		object __hx_lookupSetField(string field, int hash, object @value);
		
		double __hx_lookupSetField_f(string field, int hash, double @value);
		
		double __hx_setField_f(string field, int hash, double @value, bool handleProperties);
		
		object __hx_setField(string field, int hash, object @value, bool handleProperties);
		
		object __hx_getField(string field, int hash, bool throwErrors, bool isCheck, bool handleProperties);
		
		double __hx_getField_f(string field, int hash, bool throwErrors, bool handleProperties);
		
		object __hx_invokeField(string field, int hash, object[] dynargs);
		
		void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr);
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public class HxObject : global::Loreline.Internal.Lang.IHxObject {
		
		public HxObject(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public HxObject() {
			global::Loreline.Internal.Lang.HxObject.__hx_ctor_haxe_lang_HxObject(this);
		}
		
		
		protected static void __hx_ctor_haxe_lang_HxObject(global::Loreline.Internal.Lang.HxObject __hx_this) {
		}
		
		
		public virtual bool __hx_deleteField(string field, int hash) {
			return false;
		}
		
		
		public virtual object __hx_lookupField(string field, int hash, bool throwErrors, bool isCheck) {
			if (isCheck) {
				return global::Loreline.Internal.Lang.Runtime.undefined;
			}
			else if (throwErrors) {
				throw new global::System.MemberAccessException("Field not found.");
			}
			else {
				return null;
			}
			
		}
		
		
		public virtual double __hx_lookupField_f(string field, int hash, bool throwErrors) {
			if (throwErrors) {
				throw new global::System.MemberAccessException("Field not found or incompatible field type.");
			}
			else {
				return default(double);
			}
			
		}
		
		
		public virtual object __hx_lookupSetField(string field, int hash, object @value) {
			throw new global::System.MemberAccessException("Cannot access field for writing.");
		}
		
		
		public virtual double __hx_lookupSetField_f(string field, int hash, double @value) {
			throw new global::System.MemberAccessException("Cannot access field for writing or incompatible type.");
		}
		
		
		public virtual double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			switch (hash) {
				default:
				{
					return this.__hx_lookupSetField_f(field, hash, @value);
				}
				
			}
			
		}
		
		
		public virtual object __hx_setField(string field, int hash, object @value, bool handleProperties) {
			switch (hash) {
				default:
				{
					return this.__hx_lookupSetField(field, hash, @value);
				}
				
			}
			
		}
		
		
		public virtual object __hx_getField(string field, int hash, bool throwErrors, bool isCheck, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1937159360:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "__hx_deleteField", 1937159360)) );
					}
					
					
					default:
					{
						return this.__hx_lookupField(field, hash, throwErrors, isCheck);
					}
					
				}
				
			}
		}
		
		
		public virtual double __hx_getField_f(string field, int hash, bool throwErrors, bool handleProperties) {
			switch (hash) {
				default:
				{
					return this.__hx_lookupField_f(field, hash, throwErrors);
				}
				
			}
			
		}
		
		
		public virtual object __hx_invokeField(string field, int hash, object[] dynargs) {
			unchecked {
				switch (hash) {
					case 1937159360:
					{
						return this.__hx_deleteField(global::Loreline.Internal.Lang.Runtime.toString(dynargs[0]), ((int) (global::Loreline.Internal.Lang.Runtime.toInt(dynargs[1])) ));
					}
					
					
					default:
					{
						return ((global::Loreline.Internal.Lang.Function) (this.__hx_getField(field, hash, true, false, false)) ).__hx_invokeDynamic(dynargs);
					}
					
				}
				
			}
		}
		
		
		public virtual void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr) {
		}
		
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public class DynamicObject : global::Loreline.Internal.Lang.HxObject {
		
		static DynamicObject() {
			global::Loreline.Internal.Lang.DynamicObject.__hx_toString_depth = 0;
		}
		
		
		public DynamicObject(global::Loreline.Internal.Lang.EmptyObject empty) : base(global::Loreline.Internal.Lang.EmptyObject.EMPTY) {
		}
		
		
		public DynamicObject(int[] hashes, object[] dynamics, int[] hashes_f, double[] dynamics_f) {
			global::Loreline.Internal.Lang.DynamicObject.__hx_ctor_haxe_lang_DynamicObject(((global::Loreline.Internal.Lang.DynamicObject) (this) ), ((int[]) (hashes) ), ((object[]) (dynamics) ), ((int[]) (hashes_f) ), ((double[]) (dynamics_f) ));
		}
		
		
		public DynamicObject() {
			global::Loreline.Internal.Lang.DynamicObject.__hx_ctor_haxe_lang_DynamicObject(((global::Loreline.Internal.Lang.DynamicObject) (this) ));
		}
		
		
		protected static void __hx_ctor_haxe_lang_DynamicObject(global::Loreline.Internal.Lang.DynamicObject __hx_this, int[] hashes, object[] dynamics, int[] hashes_f, double[] dynamics_f) {
			__hx_this.__hx_hashes = hashes;
			__hx_this.__hx_dynamics = dynamics;
			__hx_this.__hx_hashes_f = hashes_f;
			__hx_this.__hx_dynamics_f = dynamics_f;
			__hx_this.__hx_length = ( hashes as global::System.Array ).Length;
			__hx_this.__hx_length_f = ( hashes_f as global::System.Array ).Length;
			__hx_this.__hx_conflicts = null;
		}
		
		
		protected static void __hx_ctor_haxe_lang_DynamicObject(global::Loreline.Internal.Lang.DynamicObject __hx_this) {
			__hx_this.__hx_hashes = new int[0];
			__hx_this.__hx_dynamics = new object[0];
			__hx_this.__hx_hashes_f = new int[0];
			__hx_this.__hx_dynamics_f = new double[0];
			__hx_this.__hx_conflicts = null;
		}
		
		
		public static int __hx_toString_depth;
		
		public int[] __hx_hashes;
		
		public object[] __hx_dynamics;
		
		public int[] __hx_hashes_f;
		
		public double[] __hx_dynamics_f;
		
		public int __hx_length;
		
		public int __hx_length_f;
		
		public global::Loreline.Internal.Lang.FieldHashConflict __hx_conflicts;
		
		public override bool __hx_deleteField(string field, int hash) {
			if (( hash < 0 )) {
				return global::Loreline.Internal.Lang.FieldLookup.deleteHashConflict(ref this.__hx_conflicts, hash, field);
			}
			
			int res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes, this.__hx_length);
			if (( res >= 0 )) {
				global::Loreline.Internal.Lang.FieldLookup.removeInt(this.__hx_hashes, this.__hx_length, res);
				global::Loreline.Internal.Lang.FieldLookup.removeDynamic(this.__hx_dynamics, this.__hx_length, res);
				this.__hx_length--;
				return true;
			}
			
			res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes_f, this.__hx_length_f);
			if (( res >= 0 )) {
				global::Loreline.Internal.Lang.FieldLookup.removeInt(this.__hx_hashes_f, this.__hx_length_f, res);
				global::Loreline.Internal.Lang.FieldLookup.removeFloat(this.__hx_dynamics_f, this.__hx_length_f, res);
				this.__hx_length_f--;
				return true;
			}
			
			return false;
		}
		
		
		public override object __hx_getField(string field, int hash, bool throwErrors, bool isCheck, bool handleProperties) {
			if (( hash < 0 )) {
				global::Loreline.Internal.Lang.FieldHashConflict conflict = global::Loreline.Internal.Lang.FieldLookup.getHashConflict(this.__hx_conflicts, hash, field);
				if (( conflict != null )) {
					return conflict.@value;
				}
				
			}
			
			int res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes, this.__hx_length);
			if (( res >= 0 )) {
				return this.__hx_dynamics[res];
			}
			
			res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes_f, this.__hx_length_f);
			if (( res >= 0 )) {
				return this.__hx_dynamics_f[res];
			}
			
			if (isCheck) {
				return global::Loreline.Internal.Lang.Runtime.undefined;
			}
			else {
				return null;
			}
			
		}
		
		
		public override object __hx_setField(string field, int hash, object @value, bool handleProperties) {
			if (( hash < 0 )) {
				global::Loreline.Internal.Lang.FieldLookup.setHashConflict(ref this.__hx_conflicts, hash, field, @value);
				return @value;
			}
			
			int res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes, this.__hx_length);
			if (( res >= 0 )) {
				return this.__hx_dynamics[res] = @value;
			}
			else {
				int res1 = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes_f, this.__hx_length_f);
				if (( res1 >= 0 )) {
					if ((( ( @value is double ) || ( ( @value is int ) || ( @value is uint ) ) ))) {
						return this.__hx_dynamics_f[res1] = ((double) (global::Loreline.Internal.Lang.Runtime.toDouble(@value)) );
					}
					
					global::Loreline.Internal.Lang.FieldLookup.removeInt(this.__hx_hashes_f, this.__hx_length_f, res1);
					global::Loreline.Internal.Lang.FieldLookup.removeFloat(this.__hx_dynamics_f, this.__hx_length_f, res1);
					this.__hx_length_f--;
				}
				
			}
			
			this.__hx_hashes = global::Loreline.Internal.Lang.FieldLookup.insertInt(this.__hx_hashes, this.__hx_length,  ~ (res) , hash);
			this.__hx_dynamics = global::Loreline.Internal.Lang.FieldLookup.insertDynamic(this.__hx_dynamics, this.__hx_length,  ~ (res) , @value);
			this.__hx_length++;
			return @value;
		}
		
		
		public override double __hx_getField_f(string field, int hash, bool throwErrors, bool handleProperties) {
			if (( hash < 0 )) {
				global::Loreline.Internal.Lang.FieldHashConflict conflict = global::Loreline.Internal.Lang.FieldLookup.getHashConflict(this.__hx_conflicts, hash, field);
				if (( conflict != null )) {
					return ((double) (global::Loreline.Internal.Lang.Runtime.toDouble(conflict.@value)) );
				}
				
			}
			
			int res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes_f, this.__hx_length_f);
			if (( res >= 0 )) {
				return this.__hx_dynamics_f[res];
			}
			
			res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes, this.__hx_length);
			if (( res >= 0 )) {
				return ((double) (global::Loreline.Internal.Lang.Runtime.toDouble(this.__hx_dynamics[res])) );
			}
			
			return 0.0;
		}
		
		
		public override double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			if (( hash < 0 )) {
				global::Loreline.Internal.Lang.FieldLookup.setHashConflict(ref this.__hx_conflicts, hash, field, @value);
				return @value;
			}
			
			int res = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes_f, this.__hx_length_f);
			if (( res >= 0 )) {
				return this.__hx_dynamics_f[res] = @value;
			}
			else {
				int res1 = global::Loreline.Internal.Lang.FieldLookup.findHash(hash, this.__hx_hashes, this.__hx_length);
				if (( res1 >= 0 )) {
					global::Loreline.Internal.Lang.FieldLookup.removeInt(this.__hx_hashes, this.__hx_length, res1);
					global::Loreline.Internal.Lang.FieldLookup.removeDynamic(this.__hx_dynamics, this.__hx_length, res1);
					this.__hx_length--;
				}
				
			}
			
			this.__hx_hashes_f = global::Loreline.Internal.Lang.FieldLookup.insertInt(this.__hx_hashes_f, this.__hx_length_f,  ~ (res) , hash);
			this.__hx_dynamics_f = global::Loreline.Internal.Lang.FieldLookup.insertFloat(this.__hx_dynamics_f, this.__hx_length_f,  ~ (res) , @value);
			this.__hx_length_f++;
			return @value;
		}
		
		
		public override void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr) {
			{
				int _g = 0;
				int _g1 = this.__hx_length;
				while (( _g < _g1 )) {
					int i = _g++;
					baseArr.push(global::Loreline.Internal.Lang.FieldLookup.lookupHash(this.__hx_hashes[i]));
				}
				
			}
			
			{
				int _g2 = 0;
				int _g3 = this.__hx_length_f;
				while (( _g2 < _g3 )) {
					int i1 = _g2++;
					baseArr.push(global::Loreline.Internal.Lang.FieldLookup.lookupHash(this.__hx_hashes_f[i1]));
				}
				
			}
			
			global::Loreline.Internal.Lang.FieldLookup.addHashConflictNames(this.__hx_conflicts, baseArr);
		}
		
		
		public override object __hx_invokeField(string field, int hash, object[] dynargs) {
			if (( field == "toString" )) {
				return this.toString();
			}
			
			global::Loreline.Internal.Lang.Function fn = ((global::Loreline.Internal.Lang.Function) (this.__hx_getField(field, hash, false, false, false)) );
			if (( fn == null )) {
				throw ((global::System.Exception) (global::Loreline.Internal.Exception.thrown(global::Loreline.Internal.Lang.Runtime.concat(global::Loreline.Internal.Lang.Runtime.concat("Cannot invoke field ", field), ": It does not exist"))) );
			}
			
			return fn.__hx_invokeDynamic(dynargs);
		}
		
		
		public virtual string toString() {
			unchecked {
				if (( global::Loreline.Internal.Lang.DynamicObject.__hx_toString_depth >= 5 )) {
					return "...";
				}
				
				 ++ global::Loreline.Internal.Lang.DynamicObject.__hx_toString_depth;
				try {
					string s = this.__hx_toString();
					 -- global::Loreline.Internal.Lang.DynamicObject.__hx_toString_depth;
					return s;
				}
				catch (global::System.Exception _g){
					object e = ((object) (global::Loreline.Internal.Exception.caught(_g).unwrap()) );
					 -- global::Loreline.Internal.Lang.DynamicObject.__hx_toString_depth;
					throw ((global::System.Exception) (global::Loreline.Internal.Exception.thrown(e)) );
				}
				
				
			}
		}
		
		
		public virtual string __hx_toString() {
			global::Loreline.Internal.Lang.Function ts = ((global::Loreline.Internal.Lang.Function) (global::Loreline.Internal.Lang.Runtime.getField(this, "toString", 946786476, false)) );
			if (( ts != null )) {
				return global::Loreline.Internal.Lang.Runtime.toString(ts.__hx_invoke0_o());
			}
			
			global::System.Text.StringBuilder ret_b = new global::System.Text.StringBuilder();
			ret_b.Append(((string) ("[") ));
			bool first = true;
			{
				int _g = 0;
				global::Loreline.Internal.Root.Array<string> _g1 = global::Loreline.Internal.Root.Reflect.fields(this);
				while (( _g < _g1.length )) {
					string f = _g1[_g];
					 ++ _g;
					if (first) {
						first = false;
					}
					else {
						ret_b.Append(((string) (",") ));
					}
					
					ret_b.Append(((string) (" ") ));
					ret_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(f)) ));
					ret_b.Append(((string) (" : ") ));
					ret_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(((object) (global::Loreline.Internal.Root.Reflect.field(this, f)) ))) ));
				}
				
			}
			
			if ( ! (first) ) {
				ret_b.Append(((string) (" ") ));
			}
			
			ret_b.Append(((string) ("]") ));
			return ret_b.ToString();
		}
		
		
		public override string ToString(){
			return this.toString();
		}
		
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public interface IGenericObject : global::Loreline.Internal.Lang.IHxObject {
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public class GenericInterface : global::System.Attribute {
		
		public GenericInterface(global::System.Type generic) : base() {
			this.generic = generic;
		}
		
		
		public readonly global::System.Type generic;
		
	}
}



#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Internal.Lang {
	public class Enum {
		
		protected Enum(int index) {
			this._hx_index = index;
		}
		
		
		protected static string paramsToString(string tag, object[] @params) {
			global::System.Text.StringBuilder ret_b = new global::System.Text.StringBuilder();
			ret_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(tag)) ));
			ret_b.Append(((string) ("(") ));
			bool first = true;
			{
				int _g = 0;
				while (( _g < ( ((object[]) (@params) ) as global::System.Array ).Length )) {
					object p = ((object[]) (@params) )[_g];
					 ++ _g;
					if (first) {
						first = false;
					}
					else {
						ret_b.Append(((string) (",") ));
					}
					
					ret_b.Append(((string) (global::Loreline.Internal.Root.Std.@string(((object) (p) ))) ));
				}
				
			}
			
			ret_b.Append(((string) (")") ));
			return ret_b.ToString();
		}
		
		
		protected static int paramsGetHashCode(int index, object[] @params) {
			unchecked {
				int h = 19;
				if (( @params != null )) {
					int _g = 0;
					while (( _g < ( ((object[]) (@params) ) as global::System.Array ).Length )) {
						object p = ((object[]) (@params) )[_g];
						 ++ _g;
						h *= 31;
						if (( p != null )) {
							h += ((int) (global::Loreline.Internal.Lang.Runtime.toInt(p.GetHashCode())) );
						}
						
					}
					
				}
				
				h += index;
				return h;
			}
		}
		
		
		public readonly int _hx_index;
		
		public virtual string getTag() {
			unchecked {
				throw new global::Loreline.Internal.Exceptions.NotImplementedException(default(string), default(global::Loreline.Internal.Exception), ((object) (new global::Loreline.Internal.Lang.DynamicObject(new int[]{302979532, 1547539107, 1648581351}, new object[]{"getTag", "global::Loreline.Internal.Cs.internal.HxEnum", "global::Loreline.Internal.Cs.internal/HxObject.hx"}, new int[]{1981972957}, new double[]{((double) (279) )})) ));
			}
		}
		
		
		public virtual global::Loreline.Internal.Root.Array<object> getParams() {
			return new global::Loreline.Internal.Root.Array<object>(new object[]{});
		}
		
		
		public virtual string toString() {
			return this.getTag();
		}
		
		
		public override string ToString(){
			return this.toString();
		}
		
		
	}
}


