package loreline;

import haxe.io.Path;
import loreline.Lexer;

using StringTools;
using loreline.Utf8;

typedef ImportsFileHandler = (path:String, callback:(data:String)->Void)->Void;

typedef ImportsErrorHandler = (error:Error)->Void;

typedef ImportsCallback = (hasErrors:Bool, resolvedImports:Map<String,Tokens>)->Void;

@:structInit
@:allow(loreline.Imports)
private class ImportsLoopInfo {

    public var finished:Bool;

}

class Imports {

    /** Returns true if `c` matches `lowerExpected` (lowercase ASCII letter) case-insensitively. */
    static inline function sameLetterCi(c:Int, lowerExpected:Int):Bool {
        return c == lowerExpected || c == lowerExpected - 32; // 'a' (97) - 'A' (65) = 32
    }

    /** True if `path` ends with `.lor.txt` (case-insensitive on letters). */
    public static inline function endsWithLorTxt(path:String):Bool {
        if (path == null) return false;
        final n = path.uLength();
        if (n < 8) return false;
        return path.uCharCodeAt(n - 8) == '.'.code
            && sameLetterCi(path.uCharCodeAt(n - 7), 'l'.code)
            && sameLetterCi(path.uCharCodeAt(n - 6), 'o'.code)
            && sameLetterCi(path.uCharCodeAt(n - 5), 'r'.code)
            && path.uCharCodeAt(n - 4) == '.'.code
            && sameLetterCi(path.uCharCodeAt(n - 3), 't'.code)
            && sameLetterCi(path.uCharCodeAt(n - 2), 'x'.code)
            && sameLetterCi(path.uCharCodeAt(n - 1), 't'.code);
    }

    /** True if `path` ends with `.lor` (but not `.lor.txt`). */
    public static inline function endsWithLor(path:String):Bool {
        if (path == null) return false;
        final n = path.uLength();
        if (n < 4) return false;
        return path.uCharCodeAt(n - 4) == '.'.code
            && sameLetterCi(path.uCharCodeAt(n - 3), 'l'.code)
            && sameLetterCi(path.uCharCodeAt(n - 2), 'o'.code)
            && sameLetterCi(path.uCharCodeAt(n - 1), 'r'.code);
    }

    /**
     * Returns the canonical Loreline extension for a path: `.lor.txt` if the path
     * ends with that, otherwise `.lor` (also returned for paths with no Loreline
     * extension at all — matches the fallback used elsewhere).
     */
    public static inline function lorExtension(path:String):String {
        return endsWithLorTxt(path) ? '.lor.txt' : '.lor';
    }

    /** True if `path` ends with `.lor` or `.lor.txt`. */
    public static inline function isLorFilePath(path:String):Bool {
        return endsWithLorTxt(path) || endsWithLor(path);
    }

    /**
     * Strips the Loreline extension from a path. Removes `.lor.txt` if present,
     * otherwise removes `.lor` if present, otherwise returns the path unchanged.
     */
    public static inline function stripLorExtension(path:String):String {
        if (path == null) return null;
        if (endsWithLorTxt(path)) return path.uSubstr(0, path.uLength() - 8);
        if (endsWithLor(path)) return path.uSubstr(0, path.uLength() - 4);
        return path;
    }

    var handleFile:ImportsFileHandler;

    var handleError:ImportsErrorHandler;

    var tokens:Tokens;

    var rootPath:String;

    public var autoAddExtension:Bool = true;

    var resolvedImports(default, null):Map<String,Tokens> = null;

    var done:ImportsCallback = null;

    var hasErrors:Bool = false;

    var pendingImports:Int = 0;

    var ext:String = '.lor';

    public function new() {}

    public function resolve(rootPath:String, tokens:Tokens, handleFile:ImportsFileHandler, handleError:ImportsErrorHandler, done:ImportsCallback) {

        this.rootPath = rootPath;
        this.tokens = tokens;
        this.handleFile = handleFile;
        this.handleError = handleError;

        this.done = done;
        this.hasErrors = false;
        this.pendingImports = 0;

        ext = lorExtension(rootPath);

        final resolvedImports:Map<String,Tokens> = new Map();
        final toImport:Array<String> = [];
        final visitedImports:Map<String,Bool> = new Map();
        final cwd = Path.directory(rootPath);

        // Extract root imports
        extractImports(cwd, tokens, toImport, visitedImports);

        // Then iterate through items to import
        processImports(toImport, visitedImports, resolvedImports);

    }

    function processImports(toImport:Array<String>, visitedImports:Map<String,Bool>, resolvedImports:Map<String,Tokens>) {

        final loopInfo:ImportsLoopInfo = { finished: false };
        while (toImport.length > 0) {
            final item = toImport.shift();
            handleItemInLoop(item, loopInfo, toImport, visitedImports, resolvedImports);
        }
        loopInfo.finished = true;
        if (pendingImports == 0 && done != null) {
            this.resolvedImports = resolvedImports;
            done(hasErrors, resolvedImports);
            done = null;
        }

    }

    function handleItemInLoop(item:String, loopInfo:ImportsLoopInfo, toImport:Array<String>, visitedImports:Map<String,Bool>, resolvedImports:Map<String,Tokens>) {

        handleFile(item, data -> {
            pendingImports--;
            if (data != null) {
                try {
                    final lexer = new Lexer(data);
                    final tokens = lexer.tokenize();

                    final lexerErrors = lexer.getErrors();
                    if (lexerErrors != null && lexerErrors.length > 0) {
                        handleError(lexerErrors[0]);
                    }

                    resolvedImports.set(item, tokens);

                    extractImports(Path.directory(item), tokens, toImport, visitedImports);

                    // If still in the while loop, new imports will be processed in the current loop anyway
                    if (loopInfo.finished) {
                        // But if not, then we are asynchronous, let's explicitly process imports
                        processImports(toImport, visitedImports, resolvedImports);
                    }
                }
                catch (e:Any) {
                    hasErrors = true;
                    if (e is Error) {
                        handleError(e);
                    }
                    else {
                        throw e;
                    }
                }
            }
            else {
                hasErrors = true;
            }
            if (loopInfo.finished && pendingImports == 0 && done != null) {
                this.resolvedImports = resolvedImports;
                done(hasErrors, resolvedImports);
                done = null;
            }
        });

    }

    function extractImports(cwd:String, tokens:Tokens, toImport:Array<String>, visitedImports:Map<String,Bool>) {

        // Tokens are enough to extract imports, as they are
        // always structured with KwImport followed with a string

        var i = 0;
        var len = tokens.length;
        while (i < len - 1) {
            if (tokens[i].type == KwImport) {
                switch tokens[i+1].type {

                    case LString(_, s, _):
                        var path = s;
                        if (!Path.isAbsolute(s)) {
                            path = Path.join([cwd, path]);
                        }
                        path = Path.normalize(path);
                        if (!isLorFilePath(path)) {
                            path += ext;
                        }
                        if (!visitedImports.exists(path)) {
                            pendingImports++;
                            visitedImports.set(path, true);
                            toImport.push(path);
                        }

                    case _:
                }
            }
            i++;
        }

    }

}