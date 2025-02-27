// Generated by Haxe 4.3.6

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060
namespace Loreline.Internal {
	public class Exception : global::System.Exception, global::Loreline.Internal.Lang.IHxObject {
		
		public Exception(global::Loreline.Internal.Lang.EmptyObject empty) : base(null, null) {
		}
		
		
		public Exception(string message, global::Loreline.Internal.Exception previous, object native) : base(message, ( (( previous == null )) ? (null) : (previous) )) {
			unchecked {
				this.__skipStack = 0;
				{
					this.__previousException = previous;
					if (( ( native != null ) && ( native is global::System.Exception ) )) {
						this.__nativeException = ((global::System.Exception) (((object) (native) )) );
						if (( this.__nativeException.StackTrace == null )) {
							this.__nativeStack = new global::System.Diagnostics.StackTrace(((int) (1) ), ((bool) (true) ));
							this.__ownStack = true;
						}
						else {
							this.__nativeStack = new global::System.Diagnostics.StackTrace(((global::System.Exception) (this.__nativeException) ), ((bool) (true) ));
							this.__ownStack = false;
						}
						
					}
					else {
						this.__nativeException = ((global::System.Exception) (((object) (this) )) );
						this.__nativeStack = new global::System.Diagnostics.StackTrace(((int) (1) ), ((bool) (true) ));
						this.__ownStack = true;
					}
					
				}
				
			}
		}
		
		
		public static global::Loreline.Internal.Exception caught(object @value) {
			if (( @value is global::Loreline.Internal.Exception )) {
				return ((global::Loreline.Internal.Exception) (((object) (@value) )) );
			}
			else if (( @value is global::System.Exception )) {
				return new global::Loreline.Internal.Exception(((string) (((global::System.Exception) (((object) (@value) )) ).Message) ), default(global::Loreline.Internal.Exception), ((object) (@value) ));
			}
			else {
				return new global::Loreline.Internal.ValueException(((object) (@value) ), default(global::Loreline.Internal.Exception), ((object) (@value) ));
			}
			
		}
		
		
		public static object thrown(object @value) {
			if (( @value is global::Loreline.Internal.Exception )) {
				return ((global::Loreline.Internal.Exception) (((object) (@value) )) ).get_native();
			}
			else if (( @value is global::System.Exception )) {
				return @value;
			}
			else {
				global::Loreline.Internal.ValueException e = new global::Loreline.Internal.ValueException(((object) (@value) ), default(global::Loreline.Internal.Exception), default(object));
				if (e.__ownStack) {
					e.__skipStack++;
				}
				
				return e;
			}
			
		}
		
		
		
		
		
		
		[global::System.ComponentModel.EditorBrowsable(global::System.ComponentModel.EditorBrowsableState.Never)]
		public global::System.Diagnostics.StackTrace __nativeStack;
		
		[global::System.ComponentModel.EditorBrowsable(global::System.ComponentModel.EditorBrowsableState.Never)]
		public bool __ownStack;
		
		[global::System.ComponentModel.EditorBrowsable(global::System.ComponentModel.EditorBrowsableState.Never)]
		public int __skipStack;
		
		[global::System.ComponentModel.EditorBrowsable(global::System.ComponentModel.EditorBrowsableState.Never)]
		public global::System.Exception __nativeException;
		
		[global::System.ComponentModel.EditorBrowsable(global::System.ComponentModel.EditorBrowsableState.Never)]
		public global::Loreline.Internal.Exception __previousException;
		
		public virtual object unwrap() {
			return this.__nativeException;
		}
		
		
		public virtual string toString() {
			return this.get_message();
		}
		
		
		public virtual string get_message() {
			return this.Message;
		}
		
		
		public object get_native() {
			return this.__nativeException;
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
			unchecked {
				switch (hash) {
					case 1177754921:
					{
						this.__skipStack = ((int) (@value) );
						return @value;
					}
					
					
					default:
					{
						return this.__hx_lookupSetField_f(field, hash, @value);
					}
					
				}
				
			}
		}
		
		
		public virtual object __hx_setField(string field, int hash, object @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 78945784:
					{
						this.__previousException = ((global::Loreline.Internal.Exception) (@value) );
						return @value;
					}
					
					
					case 221637784:
					{
						this.__nativeException = ((global::System.Exception) (@value) );
						return @value;
					}
					
					
					case 1177754921:
					{
						this.__skipStack = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 1460447810:
					{
						this.__ownStack = global::Loreline.Internal.Lang.Runtime.toBool(@value);
						return @value;
					}
					
					
					case 863972113:
					{
						this.__nativeStack = ((global::System.Diagnostics.StackTrace) (@value) );
						return @value;
					}
					
					
					default:
					{
						return this.__hx_lookupSetField(field, hash, @value);
					}
					
				}
				
			}
		}
		
		
		public virtual object __hx_getField(string field, int hash, bool throwErrors, bool isCheck, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 312752480:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "get_native", 312752480)) );
					}
					
					
					case 537630174:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "get_message", 537630174)) );
					}
					
					
					case 946786476:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "toString", 946786476)) );
					}
					
					
					case 1825849507:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "unwrap", 1825849507)) );
					}
					
					
					case 78945784:
					{
						return this.__previousException;
					}
					
					
					case 221637784:
					{
						return this.__nativeException;
					}
					
					
					case 1177754921:
					{
						return this.__skipStack;
					}
					
					
					case 1460447810:
					{
						return this.__ownStack;
					}
					
					
					case 863972113:
					{
						return this.__nativeStack;
					}
					
					
					case 572311959:
					{
						return this.get_native();
					}
					
					
					case 437335495:
					{
						return this.get_message();
					}
					
					
					default:
					{
						return this.__hx_lookupField(field, hash, throwErrors, isCheck);
					}
					
				}
				
			}
		}
		
		
		public virtual double __hx_getField_f(string field, int hash, bool throwErrors, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1177754921:
					{
						return ((double) (this.__skipStack) );
					}
					
					
					case 572311959:
					{
						return ((double) (global::Loreline.Internal.Lang.Runtime.toDouble(this.get_native())) );
					}
					
					
					default:
					{
						return this.__hx_lookupField_f(field, hash, throwErrors);
					}
					
				}
				
			}
		}
		
		
		public virtual object __hx_invokeField(string field, int hash, object[] dynargs) {
			unchecked {
				switch (hash) {
					case 312752480:
					{
						return this.get_native();
					}
					
					
					case 537630174:
					{
						return this.get_message();
					}
					
					
					case 946786476:
					{
						return this.toString();
					}
					
					
					case 1825849507:
					{
						return this.unwrap();
					}
					
					
					default:
					{
						return ((global::Loreline.Internal.Lang.Function) (this.__hx_getField(field, hash, true, false, false)) ).__hx_invokeDynamic(dynargs);
					}
					
				}
				
			}
		}
		
		
		public virtual void __hx_getFields(global::Loreline.Internal.Root.Array<string> baseArr) {
			baseArr.push("__previousException");
			baseArr.push("__nativeException");
			baseArr.push("__skipStack");
			baseArr.push("__ownStack");
			baseArr.push("__nativeStack");
			baseArr.push("native");
			baseArr.push("message");
		}
		
		
		public override string ToString(){
			return this.toString();
		}
		
		
	}
}


