// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060
namespace Loreline.Internal.Format {
	public class JsonPrinter : global::Loreline.Internal.Lang.HxObject {
		
		public JsonPrinter(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public JsonPrinter(global::Loreline.Internal.Lang.Function replacer, string space) {
			global::Loreline.Internal.Format.JsonPrinter.__hx_ctor_haxe_format_JsonPrinter(this, replacer, space);
		}
		
		
		protected static void __hx_ctor_haxe_format_JsonPrinter(global::Loreline.Internal.Format.JsonPrinter __hx_this, global::Loreline.Internal.Lang.Function replacer, string space) {
			__hx_this.replacer = replacer;
			__hx_this.indent = space;
			__hx_this.pretty = ( space != null );
			__hx_this.nind = 0;
			__hx_this.buf = new global::Loreline.Internal.Root.StringBuf();
		}
		
		
		public static string print(object o, global::Loreline.Internal.Lang.Function replacer, string space) {
			global::Loreline.Internal.Format.JsonPrinter printer = new global::Loreline.Internal.Format.JsonPrinter(((global::Loreline.Internal.Lang.Function) (replacer) ), ((string) (space) ));
			printer.write("", o);
			return printer.buf.b.ToString();
		}
		
		
		public global::Loreline.Internal.Root.StringBuf buf;
		
		public global::Loreline.Internal.Lang.Function replacer;
		
		public string indent;
		
		public bool pretty;
		
		public int nind;
		
		public virtual void write(object k, object v) {
			unchecked {
				if (( this.replacer != null )) {
					v = ((object) (this.replacer.__hx_invoke2_o(default(double), k, default(double), v)) );
				}
				
				{
					global::Loreline.Internal.Root.ValueType _g = global::Loreline.Internal.Root.Type.@typeof(v);
					switch (_g._hx_index) {
						case 0:
						{
							this.buf.b.Append(((string) ("null") ));
							break;
						}
						
						
						case 1:
						{
							this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(global::Loreline.Internal.Lang.Runtime.toString(v))) ));
							break;
						}
						
						
						case 2:
						{
							double f = ((double) (global::Loreline.Internal.Lang.Runtime.toDouble(v)) );
							string v1 = ( ((  ! (global::System.Double.IsInfinity(((double) (f) )))  &&  ! (global::System.Double.IsNaN(((double) (f) )))  )) ? (global::Loreline.Internal.Root.Std.@string(v)) : ("null") );
							this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v1)) ));
							break;
						}
						
						
						case 3:
						{
							this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(global::Loreline.Internal.Lang.Runtime.toString(v))) ));
							break;
						}
						
						
						case 4:
						{
							this.fieldsString(v, global::Loreline.Internal.Root.Reflect.fields(v));
							break;
						}
						
						
						case 5:
						{
							this.buf.b.Append(((string) ("\"<fun>\"") ));
							break;
						}
						
						
						case 6:
						{
							global::System.Type c = ( _g as global::Loreline.Internal.Root.ValueType_TClass ).c;
							if (global::Loreline.Internal.Lang.Runtime.refEq(c, typeof(string))) {
								this.quote(global::Loreline.Internal.Lang.Runtime.toString(v));
							}
							else if (global::Loreline.Internal.Lang.Runtime.refEq(c, typeof(global::Loreline.Internal.Root.Array<object>))) {
								global::Loreline.Internal.Root.Array v2 = ((global::Loreline.Internal.Root.Array) (v) );
								this.buf.addChar(91);
								int len = ((int) (global::Loreline.Internal.Lang.Runtime.getField_f(v2, "length", 520590566, true)) );
								int last = ( len - 1 );
								{
									int _g1 = 0;
									int _g2 = len;
									while (( _g1 < _g2 )) {
										int i = _g1++;
										if (( i > 0 )) {
											this.buf.addChar(44);
										}
										else {
											this.nind++;
										}
										
										if (this.pretty) {
											this.buf.addChar(10);
										}
										
										if (this.pretty) {
											string v3 = global::Loreline.Internal.Root.StringTools.lpad("", this.indent, ( this.nind * this.indent.Length ));
											this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v3)) ));
										}
										
										this.write(i, v2[i]);
										if (( i == last )) {
											this.nind--;
											if (this.pretty) {
												this.buf.addChar(10);
											}
											
											if (this.pretty) {
												string v4 = global::Loreline.Internal.Root.StringTools.lpad("", this.indent, ( this.nind * this.indent.Length ));
												this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v4)) ));
											}
											
										}
										
									}
									
								}
								
								this.buf.addChar(93);
							}
							else if (global::Loreline.Internal.Lang.Runtime.refEq(c, typeof(global::Loreline.Internal.Ds.StringMap<object>))) {
								global::Loreline.Internal.Ds.StringMap v5 = ((global::Loreline.Internal.Ds.StringMap) (v) );
								object o = new global::Loreline.Internal.Lang.DynamicObject(new int[]{}, new object[]{}, new int[]{}, new double[]{});
								{
									object k1 = ((object) (new global::Loreline.Internal.Ds._StringMap.StringMapKeyIterator<object>(((global::Loreline.Internal.Ds.StringMap<object>) (global::Loreline.Internal.Ds.StringMap<object>.__hx_cast<object>(((global::Loreline.Internal.Ds.StringMap) (v5) ))) ))) );
									while (global::Loreline.Internal.Lang.Runtime.toBool(global::Loreline.Internal.Lang.Runtime.callField(k1, "hasNext", 407283053, null))) {
										string k2 = global::Loreline.Internal.Lang.Runtime.toString(global::Loreline.Internal.Lang.Runtime.callField(k1, "next", 1224901875, null));
										global::Loreline.Internal.Root.Reflect.setField(o, k2, ((object) (global::Loreline.Internal.Lang.Runtime.callField(v5, "get", 5144726, new object[]{k2})) ));
									}
									
								}
								
								{
									object v6 = ((object) (o) );
									this.fieldsString(v6, global::Loreline.Internal.Root.Reflect.fields(v6));
								}
								
							}
							else if (global::Loreline.Internal.Lang.Runtime.refEq(c, typeof(global::Loreline.Internal.Root.Date))) {
								global::Loreline.Internal.Root.Date v7 = ((global::Loreline.Internal.Root.Date) (v) );
								this.quote(v7.toString());
							}
							else {
								this.classString(v);
							}
							
							break;
						}
						
						
						case 7:
						{
							global::System.Type _g3 = ( _g as global::Loreline.Internal.Root.ValueType_TEnum ).e;
							{
								int i1 = global::Loreline.Internal.Root.Type.enumIndex(v);
								{
									string v8 = global::Loreline.Internal.Root.Std.@string(i1);
									this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v8)) ));
								}
								
							}
							
							break;
						}
						
						
						case 8:
						{
							this.buf.b.Append(((string) ("\"???\"") ));
							break;
						}
						
						
					}
					
				}
				
			}
		}
		
		
		public virtual void classString(object v) {
			this.fieldsString(v, global::Loreline.Internal.Root.Type.getInstanceFields(global::Loreline.Internal.Root.Type.getClass<object>(((object) (v) ))));
		}
		
		
		public virtual void fieldsString(object v, global::Loreline.Internal.Root.Array<string> fields) {
			unchecked {
				this.buf.addChar(123);
				int len = fields.length;
				bool empty = true;
				{
					int _g = 0;
					int _g1 = len;
					while (( _g < _g1 )) {
						int i = _g++;
						string f = fields[i];
						object @value = global::Loreline.Internal.Root.Reflect.field(v, f);
						if (( ((object) (@value) ) is global::Loreline.Internal.Lang.Function )) {
							continue;
						}
						
						if (empty) {
							this.nind++;
							empty = false;
						}
						else {
							this.buf.addChar(44);
						}
						
						if (this.pretty) {
							this.buf.addChar(10);
						}
						
						if (this.pretty) {
							string v1 = global::Loreline.Internal.Root.StringTools.lpad("", this.indent, ( this.nind * this.indent.Length ));
							this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v1)) ));
						}
						
						this.quote(f);
						this.buf.addChar(58);
						if (this.pretty) {
							this.buf.addChar(32);
						}
						
						this.write(f, @value);
					}
					
				}
				
				if ( ! (empty) ) {
					this.nind--;
					if (this.pretty) {
						this.buf.addChar(10);
					}
					
					if (this.pretty) {
						string v2 = global::Loreline.Internal.Root.StringTools.lpad("", this.indent, ( this.nind * this.indent.Length ));
						this.buf.b.Append(((string) (global::Loreline.Internal.Root.Std.@string(v2)) ));
					}
					
				}
				
				this.buf.addChar(125);
			}
		}
		
		
		public virtual void quote(string s) {
			unchecked {
				this.buf.addChar(34);
				int i = 0;
				int length = s.Length;
				while (( i < length )) {
					int c = ((int) (s[i++]) );
					switch (c) {
						case 8:
						{
							this.buf.b.Append(((string) ("\\b") ));
							break;
						}
						
						
						case 9:
						{
							this.buf.b.Append(((string) ("\\t") ));
							break;
						}
						
						
						case 10:
						{
							this.buf.b.Append(((string) ("\\n") ));
							break;
						}
						
						
						case 12:
						{
							this.buf.b.Append(((string) ("\\f") ));
							break;
						}
						
						
						case 13:
						{
							this.buf.b.Append(((string) ("\\r") ));
							break;
						}
						
						
						case 34:
						{
							this.buf.b.Append(((string) ("\\\"") ));
							break;
						}
						
						
						case 92:
						{
							this.buf.b.Append(((string) ("\\\\") ));
							break;
						}
						
						
						default:
						{
							this.buf.addChar(c);
							break;
						}
						
					}
					
				}
				
				this.buf.addChar(34);
			}
		}
		
		
		public override double __hx_setField_f(string field, int hash, double @value, bool handleProperties) {
			unchecked {
				switch (hash) {
					case 1225098545:
					{
						this.nind = ((int) (@value) );
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
					case 1225098545:
					{
						this.nind = ((int) (global::Loreline.Internal.Lang.Runtime.toInt(@value)) );
						return @value;
					}
					
					
					case 784433846:
					{
						this.pretty = global::Loreline.Internal.Lang.Runtime.toBool(@value);
						return @value;
					}
					
					
					case 334695532:
					{
						this.indent = global::Loreline.Internal.Lang.Runtime.toString(@value);
						return @value;
					}
					
					
					case 404153790:
					{
						this.replacer = ((global::Loreline.Internal.Lang.Function) (@value) );
						return @value;
					}
					
					
					case 4899635:
					{
						this.buf = ((global::Loreline.Internal.Root.StringBuf) (@value) );
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
					case 1576149820:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "quote", 1576149820)) );
					}
					
					
					case 878103594:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "fieldsString", 878103594)) );
					}
					
					
					case 142151465:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "classString", 142151465)) );
					}
					
					
					case 1348037855:
					{
						return ((global::Loreline.Internal.Lang.Function) (new global::Loreline.Internal.Lang.Closure(this, "write", 1348037855)) );
					}
					
					
					case 1225098545:
					{
						return this.nind;
					}
					
					
					case 784433846:
					{
						return this.pretty;
					}
					
					
					case 334695532:
					{
						return this.indent;
					}
					
					
					case 404153790:
					{
						return this.replacer;
					}
					
					
					case 4899635:
					{
						return this.buf;
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
					case 1225098545:
					{
						return ((double) (this.nind) );
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
					case 1576149820:
					{
						this.quote(global::Loreline.Internal.Lang.Runtime.toString(dynargs[0]));
						break;
					}
					
					
					case 878103594:
					{
						this.fieldsString(dynargs[0], ((global::Loreline.Internal.Root.Array<string>) (global::Loreline.Internal.Root.Array<object>.__hx_cast<string>(((global::Loreline.Internal.Root.Array) (dynargs[1]) ))) ));
						break;
					}
					
					
					case 142151465:
					{
						this.classString(dynargs[0]);
						break;
					}
					
					
					case 1348037855:
					{
						this.write(dynargs[0], dynargs[1]);
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
			baseArr.push("nind");
			baseArr.push("pretty");
			baseArr.push("indent");
			baseArr.push("replacer");
			baseArr.push("buf");
			base.__hx_getFields(baseArr);
		}
		
		
	}
}


