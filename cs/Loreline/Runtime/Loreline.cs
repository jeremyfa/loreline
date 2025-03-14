// Generated by Haxe 4.3.6
using global::Loreline.Internal.Root;

#pragma warning disable 109, 114, 219, 429, 168, 162, IL2026, IL2070, IL2072, IL2060, CS0108
namespace Loreline.Runtime {
	public class Loreline : global::Loreline.Internal.Lang.HxObject {
		
		public Loreline(global::Loreline.Internal.Lang.EmptyObject empty) {
		}
		
		
		public Loreline() {
			global::Loreline.Runtime.Loreline.__hx_ctor_loreline_Loreline(this);
		}
		
		
		protected static void __hx_ctor_loreline_Loreline(global::Loreline.Runtime.Loreline __hx_this) {
		}
		
		
		public static global::Loreline.Runtime.Script parse(string input) {
			global::Loreline.Runtime.Lexer lexer = new global::Loreline.Runtime.Lexer(((string) (input) ));
			global::Loreline.Internal.Root.Array<object> tokens = lexer.tokenize();
			global::Loreline.Runtime.Parser parser = new global::Loreline.Runtime.Parser(((global::Loreline.Internal.Root.Array<object>) (tokens) ));
			global::Loreline.Runtime.Script result = parser.parse();
			global::Loreline.Internal.Root.Array<object> lexerErrors = lexer.getErrors();
			global::Loreline.Internal.Root.Array<object> parseErrors = parser.getErrors();
			if (( ( lexerErrors != null ) && ( lexerErrors.length > 0 ) )) {
				throw ((global::System.Exception) (global::Loreline.Internal.Exception.thrown(((global::Loreline.Runtime.LexerError) (lexerErrors[0]) ))) );
			}
			
			if (( ( parseErrors != null ) && ( parseErrors.length > 0 ) )) {
				throw ((global::System.Exception) (global::Loreline.Internal.Exception.thrown(((global::Loreline.Runtime.ParseError) (parseErrors[0]) ))) );
			}
			
			return result;
		}
		
		
		public static global::Loreline.Runtime.Interpreter play(global::Loreline.Runtime.Script script, global::Loreline.Internal.Lang.Function handleDialogue, global::Loreline.Internal.Lang.Function handleChoice, global::Loreline.Internal.Lang.Function handleFinish, string beatName, global::Loreline.Internal.Ds.StringMap<object> functions) {
			global::Loreline.Runtime.Interpreter interpreter = new global::Loreline.Runtime.Interpreter(((global::Loreline.Runtime.Script) (script) ), ((global::Loreline.Internal.Lang.Function) (handleDialogue) ), ((global::Loreline.Internal.Lang.Function) (handleChoice) ), ((global::Loreline.Internal.Lang.Function) (handleFinish) ), ((global::Loreline.Internal.Ds.StringMap<object>) (functions) ));
			interpreter.start(beatName);
			return interpreter;
		}
		
		
		public static global::Loreline.Runtime.Interpreter resume(global::Loreline.Runtime.Script script, global::Loreline.Internal.Lang.Function handleDialogue, global::Loreline.Internal.Lang.Function handleChoice, global::Loreline.Internal.Lang.Function handleFinish, object saveData, string beatName, global::Loreline.Internal.Ds.StringMap<object> functions) {
			global::Loreline.Runtime.Interpreter interpreter = new global::Loreline.Runtime.Interpreter(((global::Loreline.Runtime.Script) (script) ), ((global::Loreline.Internal.Lang.Function) (handleDialogue) ), ((global::Loreline.Internal.Lang.Function) (handleChoice) ), ((global::Loreline.Internal.Lang.Function) (handleFinish) ), ((global::Loreline.Internal.Ds.StringMap<object>) (functions) ));
			interpreter.restore(saveData);
			interpreter.resume();
			return interpreter;
		}
		
		
	}
}


