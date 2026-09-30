// Decorations drawn on top of the grammar coloring (text, choices, plural pipes,
// once-only options, when rules), for the syntax test report. Built against the current
// parser of this repository.

import loreline.Lexer;
import loreline.Node;
import loreline.Parser;

@:expose
class SyntaxDecorations {

	/**
	 * Lexer and parser errors of a source: a test file must be valid Loreline, or
	 * its decorations and its coloring describe code that can't exist.
	 */
	public static function getErrors(source:String):Array<Dynamic> {
		final result:Array<Dynamic> = [];
		final lexer = new Lexer(source);
		final tokens = lexer.tokenize();
		for (error in lexer.getErrors()) {
			result.push({message: error.message, line: error.pos.line, column: error.pos.column});
		}
		final parser = new Parser(tokens);
		final script = parser.parse();
		for (error in parser.getErrors()) {
			// Imports need files to load: here only their syntax is checked
			if (error.message == "Cannot import without a context") continue;
			result.push({message: error.message, line: error.pos.line, column: error.pos.column});
		}
		// Function bodies are only converted and parsed when the script runs:
		// do it like the interpreter (initializeTopLevelFunction)
		script.eachExcludingImported(function(node:Node, parent:Node) {
			if (node is NFunctionDecl) {
				final func:NFunctionDecl = cast node;
				try {
					final code = new loreline.CodeToLorscript().process(func.code + (func.external ? " {}" : ""));
					final lorscript = new loreline.lorscript.Parser();
					lorscript.allowJSON = true;
					lorscript.allowTypes = true;
					lorscript.parseString(code);
				}
				catch (e:Dynamic) {
					result.push({message: "Invalid function body: " + Std.string(e), line: func.pos.line, column: func.pos.column});
				}
			}
		});
		return result;
	}

	public static function getDecorations(source:String):Array<Dynamic> {
		final result:Array<Dynamic> = [];

		final lexer = new Lexer(source);
		final tokens = lexer.tokenize();
		final parser = new Parser(tokens);
		final script = parser.parse();

		script.eachExcludingImported(function(node:Node, parent:Node) {
			if (node is NStringLiteral) {
				final stringLit:NStringLiteral = cast node;
				var prevWasExpr = false;
				for (part in stringLit.parts) {
					switch (part.partType) {
						case Expr(_):
							prevWasExpr = true;
						case Raw(rawText):
							if (prevWasExpr) {
								findPluralPipeRanges(rawText, part.pos.offset, result);
							}
							prevWasExpr = false;
						case _:
							prevWasExpr = false;
					}
				}
			}
			if (node is NTextStatement) {
				final text:NTextStatement = cast node;
				if (text.content != null) {
					result.push({
						kind: "text-statement",
						offset: text.content.pos.offset,
						length: text.content.pos.length
					});
					if (text.content.quotes == DoubleQuotes) {
						result.push({
							kind: "text-content",
							offset: text.content.pos.offset,
							length: 1
						});
					}
					for (part in text.content.parts) {
						switch (part.partType) {
							case Raw(rawText):
								final sections = extractTextSectionsExcludingComments(rawText);
								for (section in sections) {
									result.push({
										kind: "text-content",
										offset: part.pos.offset + section.offset,
										length: section.length
									});
								}
								findEscapeRanges(source, part.pos.offset, part.pos.length, "text-markup", result);
							case Tag(_, expr):
								pushTagRanges(source, part, expr, "text-tag", result);
							case _:
						}
					}
					if (text.content.quotes == DoubleQuotes) {
						result.push({
							kind: "text-content",
							offset: text.content.pos.offset + text.content.pos.length - 1,
							length: 1
						});
					}
				}
			}
			if (node is NChoiceOption) {
				final opt:NChoiceOption = cast node;
				if (opt.text != null) {
					if (opt.once) {
						result.push({
							kind: "choice-once-prefix",
							offset: opt.pos.offset,
							length: 1
						});
						result.push({
							kind: "choice-once-style",
							offset: opt.pos.offset,
							length: opt.text.pos.offset - opt.pos.offset + opt.text.pos.length
						});
					}
					result.push({
						kind: "choice-option",
						offset: if (opt.once) opt.pos.offset else opt.text.pos.offset,
						length: if (opt.once) opt.text.pos.offset - opt.pos.offset + opt.text.pos.length else opt.text.pos.length
					});
					if (opt.text.quotes == DoubleQuotes) {
						result.push({
							kind: "choice-text",
							offset: opt.text.pos.offset,
							length: 1
						});
					}
					for (part in opt.text.parts) {
						switch (part.partType) {
							case Raw(rawText):
								final sections = extractTextSectionsExcludingComments(rawText);
								for (section in sections) {
									result.push({
										kind: "choice-text",
										offset: part.pos.offset + section.offset,
										length: section.length
									});
								}
								findEscapeRanges(source, part.pos.offset, part.pos.length, "choice-markup", result);
							case Tag(_, expr):
								pushTagRanges(source, part, expr, "choice-markup", result);
							case _:
						}
					}
					if (opt.text.quotes == DoubleQuotes) {
						result.push({
							kind: "choice-text",
							offset: opt.text.pos.offset + opt.text.pos.length - 1,
							length: 1
						});
					}
				}
			}
			if (node is NWhenRule) {
				final rule:NWhenRule = cast node;
				// The header of a rule gets a background, like a choice option, and a
				// rule played once also gets a dimmed `-` and italic. An insertion rule has no
				// header of its own.
				if (rule.insertion == null) {
					final start = rule.pos.offset;
					final end = whenRuleHeaderEnd(source, start);
					if (end > start) {
						if (rule.once) {
							result.push({
								kind: "when-once-prefix",
								offset: start,
								length: 1
							});
							result.push({
								kind: "when-once-style",
								offset: start,
								length: end - start
							});
						}
						result.push({
							kind: "when-rule",
							offset: start,
							length: end - start
						});
					}
				}
			}
		});

		return result;
	}

	/**
	 * End of the header of a when rule starting at `start`: the end of its line,
	 * without a trailing comment, an opening brace or spaces. Comment markers inside
	 * strings of the condition don't count.
	 */
	static function whenRuleHeaderEnd(source:String, start:Int):Int {
		var i = start;
		var inString = false;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\n".code || c == "\r".code) break;
			if (inString) {
				if (c == "\\".code) i++;
				else if (c == '"'.code) inString = false;
			}
			else if (c == '"'.code) {
				inString = true;
			}
			else if (c == "/".code && i + 1 < source.length) {
				final next = source.charCodeAt(i + 1);
				if (next == "/".code || next == "*".code) break;
			}
			i++;
		}
		var end = i;
		while (end > start && isSpace(source.charCodeAt(end - 1))) end--;
		if (end > start && source.charCodeAt(end - 1) == "{".code) {
			end--;
			while (end > start && isSpace(source.charCodeAt(end - 1))) end--;
		}
		return end;
	}

	static function isSpace(c:Int):Bool {
		return c == " ".code || c == "\t".code;
	}

	static function findPluralPipeRanges(text:String, baseOffset:Int, result:Array<Dynamic>):Void {
		final len = text.length;
		var i = 0;

		while (i < len) {
			final c = text.charCodeAt(i);

			// Skip escaped pipes
			if (c == "\\".code && i + 1 < len && text.charCodeAt(i + 1) == "|".code) {
				i += 2;
				continue;
			}

			// Parenthesized pattern: (text1|text2)
			if (c == "(".code) {
				var pipePos = -1;
				var closePos = -1;
				var j = i + 1;
				while (j < len) {
					final cj = text.charCodeAt(j);
					if (cj == "\\".code && j + 1 < len && text.charCodeAt(j + 1) == "|".code) {
						j += 2;
						continue;
					}
					if (cj == "|".code && pipePos == -1) {
						pipePos = j;
					} else if (cj == ")".code) {
						closePos = j;
						break;
					}
					j++;
				}
				if (pipePos != -1 && closePos != -1 && pipePos > i + 1 && closePos > pipePos + 1) {
					result.push({kind: "plural-pipe", offset: baseOffset + i, length: 1});
					result.push({kind: "plural-pipe", offset: baseOffset + pipePos, length: 1});
					result.push({kind: "plural-pipe", offset: baseOffset + closePos, length: 1});
					i = closePos + 1;
					continue;
				}
			}

			// Simple word pattern: word1|word2
			if (c == "|".code) {
				var wordStart = i;
				while (wordStart > 0) {
					final wc = text.charCodeAt(wordStart - 1);
					if (wc == " ".code || wc == "\t".code || wc == "\n".code
						|| wc == "|".code || wc == "(".code || wc == ")".code) break;
					wordStart--;
				}
				var wordEnd = i + 1;
				while (wordEnd < len) {
					final wc = text.charCodeAt(wordEnd);
					if (wc == " ".code || wc == "\t".code || wc == "\n".code
						|| wc == "|".code || wc == "(".code || wc == ")".code) break;
					wordEnd++;
				}
				if (i - wordStart > 0 && wordEnd - (i + 1) > 0) {
					result.push({kind: "plural-pipe", offset: baseOffset + i, length: 1});
					i = wordEnd;
					continue;
				}
			}

			i++;
		}
	}

	/**
	 * Escapes (`\x`, `$$`, `##`) in the source of a raw text part, skipping
	 * comments. They get a tint derived from the text around them, so they stand
	 * out without leaving their context.
	 */
	static function findEscapeRanges(source:String, offset:Int, length:Int, kind:String, result:Array<Dynamic>) {
		final text = source.substr(offset, length);
		for (section in extractTextSectionsExcludingComments(text)) {
			final start:Int = section.offset;
			final end:Int = start + section.length;
			var i = start;
			while (i < end) {
				final c = text.charCodeAt(i);
				if (c == '\\'.code && i + 1 < end) {
					result.push({kind: kind, offset: offset + i, length: 2});
					i += 2;
				}
				else if ((c == '$'.code || c == '#'.code) && i + 1 < end && text.charCodeAt(i + 1) == c) {
					result.push({kind: kind, offset: offset + i, length: 2});
					i += 2;
				}
				else {
					i++;
				}
			}
		}
	}

	/**
	 * The content of a tag in narration or a choice option (`b` in `<b>` and `</b>`,
	 * `pause` in `<pause=$x>`) gets a tint derived from the text. Its `<`, `/`,
	 * `=` and `>` keep their coloring, and so do the interpolations inside it.
	 */
	static function pushTagRanges(source:String, part:NStringPart, expr:NStringLiteral, kind:String, result:Array<Dynamic>) {
		var start = part.pos.offset + 1;
		var end = part.pos.offset + part.pos.length;
		if (start < end && source.charCodeAt(start) == '/'.code) start++;
		if (end > start && source.charCodeAt(end - 1) == '>'.code) end--;
		// Interpolations split the content
		final pieces:Array<Array<Int>> = [];
		var cursor = start;
		if (expr != null) {
			for (sub in expr.parts) {
				switch (sub.partType) {
					case Expr(_):
						if (sub.pos.offset > cursor) pieces.push([cursor, sub.pos.offset]);
						cursor = sub.pos.offset + sub.pos.length;
					case _:
				}
			}
		}
		if (end > cursor) pieces.push([cursor, end]);
		// And so does each `=`
		for (piece in pieces) {
			var from = piece[0];
			for (i in piece[0]...piece[1]) {
				if (source.charCodeAt(i) == '='.code) {
					if (i > from) result.push({kind: kind, offset: from, length: i - from});
					from = i + 1;
				}
			}
			if (piece[1] > from) result.push({kind: kind, offset: from, length: piece[1] - from});
		}
	}

	static function extractTextSectionsExcludingComments(text:String):Array<Dynamic> {
		final results:Array<Dynamic> = [];

		var i = 0;
		var startOffset = 0;
		var inSingleLineComment = false;
		var inMultiLineComment = false;

		while (i < text.length) {
			if (!inSingleLineComment && !inMultiLineComment) {
				if (i + 1 < text.length && text.charCodeAt(i) == '/'.code && text.charCodeAt(i + 1) == '/'.code) {
					if (i > startOffset) {
						var sectionText = text.substr(startOffset, i - startOffset);
						var trimmedLength = StringTools.rtrim(sectionText).length;
						if (trimmedLength > 0) {
							results.push({offset: startOffset, length: trimmedLength});
						}
					}
					inSingleLineComment = true;
					i += 2;
					continue;
				} else if (i + 1 < text.length && text.charCodeAt(i) == '/'.code && text.charCodeAt(i + 1) == '*'.code) {
					if (i > startOffset) {
						results.push({offset: startOffset, length: i - startOffset});
					}
					inMultiLineComment = true;
					i += 2;
					continue;
				}
			}

			if (inSingleLineComment) {
				if (text.charCodeAt(i) == '\n'.code) {
					inSingleLineComment = false;
					startOffset = i + 1;
				}
			} else if (inMultiLineComment) {
				if (i + 1 < text.length && text.charCodeAt(i) == '*'.code && text.charCodeAt(i + 1) == '/'.code) {
					inMultiLineComment = false;
					i += 2;
					startOffset = i;
					continue;
				}
			}

			i++;
		}

		if (!inSingleLineComment && !inMultiLineComment && i > startOffset) {
			results.push({offset: startOffset, length: i - startOffset});
		}

		return results;
	}

	public static function main() {}
}
