package loreline.lib;

import loreline.AstUtils;
import loreline.Interpreter;
import loreline.Json;
import loreline.Lexer;
import loreline.Loreline;
import loreline.Parser;

#if loreline_cpp_lib
@:build(loreline.Linc.touch())
@:build(loreline.Linc.xml('Loreline', './'))
#end
class Library {
	static function main() {}
}
