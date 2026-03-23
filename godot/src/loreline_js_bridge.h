#pragma once

#ifdef LORELINE_USE_JS

// JavaScript bridge code injected after loreline.min.js to provide
// an object-store and helper functions for the GDExtension to call.
//
// Events (dialogue, choice, finished) are queued and polled by C++
// after each eval() call, since we can't call back into C++ from JS.
static const char LORELINE_JS_BRIDGE[] = R"LORELINE_BRIDGE(
(function() {
    // Object store: maps integer IDs to JS objects (scripts, interpreters)
    var _nextId = 1;
    var _store = {};

    function _storeObj(obj) {
        var id = _nextId++;
        _store[id] = obj;
        return id;
    }

    function _getObj(id) {
        return _store[id];
    }

    function _releaseObj(id) {
        delete _store[id];
    }

    // Pending advance/select callbacks per interpreter ID
    var _pendingAdvance = {};
    var _pendingSelect = {};

    // Pending done callbacks for async custom function calls
    var _pendingFunctionDone = {};

    // Pending file provide callbacks for async parse (requestId → provide fn)
    var _pendingFileProvides = {};
    var _nextFileRequestId = 1;

    // Event queue: C++ polls this after play/advance/select/start/restore calls
    var _eventQueue = [];

    window._lorelineBridge = {
        // --- Runtime ---
        update: function(delta) {
            Loreline.update(delta);
        },

        // --- Event queue ---
        pollEvents: function() {
            if (_eventQueue.length === 0) return "";
            var events = JSON.stringify(_eventQueue);
            _eventQueue = [];
            return events;
        },

        // --- Parse (supports async file loading) ---
        parse: function(source, filePath, fileCallback) {
            try {
                var handleFile = null;
                if (filePath) {
                    handleFile = function(path, provide) {
                        // 1. Check overrides from C++
                        if (fileCallback) {
                            var content = fileCallback(path);
                            if (content !== null && content !== undefined) {
                                provide(content);
                                return;
                            }
                        }
                        // 2. Queue file_request for C++ to handle via FileAccess
                        var reqId = _nextFileRequestId++;
                        _pendingFileProvides[reqId] = provide;
                        _eventQueue.push({
                            type: "file_request",
                            requestId: reqId,
                            path: path
                        });
                        // provide() will be called later by provideFile()
                    };
                }
                // Use async parse with callback — if handleFile defers provide(),
                // parse() returns null and callback fires when all imports resolve
                var syncResult = Loreline.parse(source, filePath || null, handleFile, function(script) {
                    _eventQueue.push({
                        type: "parse_complete",
                        scriptId: script ? _storeObj(script) : 0
                    });
                });
                if (syncResult) {
                    // Synchronous completion (no imports or all overrides hit)
                    return _storeObj(syncResult);
                }
                // Async: file requests are pending, C++ will poll and provideFile
                return -1;
            } catch (e) {
                console.error("Loreline parse error:", e);
                return 0;
            }
        },

        // Provide file content for an async parse file_request
        provideFile: function(requestId, content) {
            var fn = _pendingFileProvides[requestId];
            if (fn) {
                delete _pendingFileProvides[requestId];
                fn(content);
            }
        },

        // --- Script ---
        releaseScript: function(scriptId) {
            _releaseObj(scriptId);
        },

        extractTranslations: function(scriptId) {
            var script = _getObj(scriptId);
            if (!script) return 0;
            var translations = Loreline.extractTranslations(script);
            if (!translations) return 0;
            return _storeObj(translations);
        },

        releaseTranslations: function(translationsId) {
            _releaseObj(translationsId);
        },

        provideFunctionDone: function(callId) {
            var fn = _pendingFunctionDone[callId];
            if (fn) {
                delete _pendingFunctionDone[callId];
                fn();
            }
        },

        play: function(scriptId, beatName, optionsJson) {
            var script = _getObj(scriptId);
            if (!script) return 0;
            // Pre-allocate ID so callbacks use the correct interpId
            // (Loreline.play fires the first callback synchronously)
            var interpId = _nextId++;

            // Build options if provided
            var playOptions = null;
            if (optionsJson) {
                try {
                    var parsed = JSON.parse(optionsJson);
                    playOptions = {};
                    if (parsed.strictAccess) playOptions.strictAccess = true;
                    if (parsed.translationsId) {
                        playOptions.translations = _getObj(parsed.translationsId);
                    }
                    if (parsed.functions && parsed.functions.length > 0) {
                        if (!playOptions.functions) playOptions.functions = {};
                        for (var fi = 0; fi < parsed.functions.length; fi++) {
                            var fname = parsed.functions[fi];
                            playOptions.functions[fname] = (function(n, iid) {
                                return function(interpreter, args) {
                                    var argsArr = [];
                                    if (args) {
                                        for (var ai = 0; ai < args.length; ai++) {
                                            argsArr.push(args[ai]);
                                        }
                                    }
                                    var resultJson = Module.ccall(
                                        'loreline_call_host_function', 'string',
                                        ['number', 'string', 'string'],
                                        [iid, n, JSON.stringify(argsArr)]);
                                    return JSON.parse(resultJson);
                                };
                            })(fname, interpId);
                        }
                    }
                    if (parsed.asyncFunctions && parsed.asyncFunctions.length > 0) {
                        if (!playOptions.functions) playOptions.functions = {};
                        for (var fi = 0; fi < parsed.asyncFunctions.length; fi++) {
                            var fname = parsed.asyncFunctions[fi];
                            playOptions.functions[fname] = (function(n, iid) {
                                return function(interpreter, args) {
                                    return new loreline.Async(function(done) {
                                        var callId = _nextFileRequestId++;
                                        _pendingFunctionDone[callId] = done;
                                        var argsArr = [];
                                        if (args) {
                                            for (var ai = 0; ai < args.length; ai++) {
                                                argsArr.push(args[ai]);
                                            }
                                        }
                                        _eventQueue.push({
                                            type: "async_function_call",
                                            interpId: iid,
                                            callId: callId,
                                            name: n,
                                            args: argsArr
                                        });
                                    });
                                };
                            })(fname, interpId);
                        }
                    }
                } catch(e) {}
            }

            var interp = Loreline.play(
                script,
                function(interpreter, character, text, tags, advance) {
                    _pendingAdvance[interpId] = advance;
                    _pendingSelect[interpId] = null;
                    var tagsArr = [];
                    if (tags) {
                        for (var i = 0; i < tags.length; i++) {
                            tagsArr.push({
                                value: tags[i].value || "",
                                offset: tags[i].offset || 0,
                                closing: !!tags[i].closing
                            });
                        }
                    }
                    _eventQueue.push({
                        type: "dialogue",
                        interpId: interpId,
                        character: character || "",
                        text: text || "",
                        tags: tagsArr
                    });
                },
                function(interpreter, options, select) {
                    _pendingSelect[interpId] = select;
                    _pendingAdvance[interpId] = null;
                    var optsArr = [];
                    for (var i = 0; i < options.length; i++) {
                        var opt = options[i];
                        var optTags = [];
                        if (opt.tags) {
                            for (var j = 0; j < opt.tags.length; j++) {
                                optTags.push({
                                    value: opt.tags[j].value || "",
                                    offset: opt.tags[j].offset || 0,
                                    closing: !!opt.tags[j].closing
                                });
                            }
                        }
                        optsArr.push({
                            text: opt.text || "",
                            enabled: opt.enabled !== false,
                            tags: optTags
                        });
                    }
                    _eventQueue.push({
                        type: "choice",
                        interpId: interpId,
                        options: optsArr
                    });
                },
                function(interpreter) {
                    _pendingAdvance[interpId] = null;
                    _pendingSelect[interpId] = null;
                    _eventQueue.push({
                        type: "finished",
                        interpId: interpId
                    });
                },
                beatName || null,
                playOptions
            );

            if (!interp) {
                // Clean up pre-allocated ID
                delete _store[interpId];
                return 0;
            }
            _store[interpId] = interp;
            return interpId;
        },

        resume: function(scriptId, saveData, beatName, optionsJson) {
            var script = _getObj(scriptId);
            if (!script) return 0;
            // Pre-allocate ID so callbacks use the correct interpId
            var interpId = _nextId++;

            // Build options if provided
            var resumeOptions = null;
            if (optionsJson) {
                try {
                    var parsed = JSON.parse(optionsJson);
                    resumeOptions = {};
                    if (parsed.strictAccess) resumeOptions.strictAccess = true;
                    if (parsed.translationsId) {
                        resumeOptions.translations = _getObj(parsed.translationsId);
                    }
                    if (parsed.functions && parsed.functions.length > 0) {
                        if (!resumeOptions.functions) resumeOptions.functions = {};
                        for (var fi = 0; fi < parsed.functions.length; fi++) {
                            var fname = parsed.functions[fi];
                            resumeOptions.functions[fname] = (function(n, iid) {
                                return function(interpreter, args) {
                                    var argsArr = [];
                                    if (args) {
                                        for (var ai = 0; ai < args.length; ai++) {
                                            argsArr.push(args[ai]);
                                        }
                                    }
                                    var resultJson = Module.ccall(
                                        'loreline_call_host_function', 'string',
                                        ['number', 'string', 'string'],
                                        [iid, n, JSON.stringify(argsArr)]);
                                    return JSON.parse(resultJson);
                                };
                            })(fname, interpId);
                        }
                    }
                    if (parsed.asyncFunctions && parsed.asyncFunctions.length > 0) {
                        if (!resumeOptions.functions) resumeOptions.functions = {};
                        for (var fi = 0; fi < parsed.asyncFunctions.length; fi++) {
                            var fname = parsed.asyncFunctions[fi];
                            resumeOptions.functions[fname] = (function(n, iid) {
                                return function(interpreter, args) {
                                    return new loreline.Async(function(done) {
                                        var callId = _nextFileRequestId++;
                                        _pendingFunctionDone[callId] = done;
                                        var argsArr = [];
                                        if (args) {
                                            for (var ai = 0; ai < args.length; ai++) {
                                                argsArr.push(args[ai]);
                                            }
                                        }
                                        _eventQueue.push({
                                            type: "async_function_call",
                                            interpId: iid,
                                            callId: callId,
                                            name: n,
                                            args: argsArr
                                        });
                                    });
                                };
                            })(fname, interpId);
                        }
                    }
                } catch(e) {}
            }

            var interp = Loreline.resume(
                script,
                function(interpreter, character, text, tags, advance) {
                    _pendingAdvance[interpId] = advance;
                    _pendingSelect[interpId] = null;
                    var tagsArr = [];
                    if (tags) {
                        for (var i = 0; i < tags.length; i++) {
                            tagsArr.push({
                                value: tags[i].value || "",
                                offset: tags[i].offset || 0,
                                closing: !!tags[i].closing
                            });
                        }
                    }
                    _eventQueue.push({
                        type: "dialogue",
                        interpId: interpId,
                        character: character || "",
                        text: text || "",
                        tags: tagsArr
                    });
                },
                function(interpreter, options, select) {
                    _pendingSelect[interpId] = select;
                    _pendingAdvance[interpId] = null;
                    var optsArr = [];
                    for (var i = 0; i < options.length; i++) {
                        var opt = options[i];
                        var optTags = [];
                        if (opt.tags) {
                            for (var j = 0; j < opt.tags.length; j++) {
                                optTags.push({
                                    value: opt.tags[j].value || "",
                                    offset: opt.tags[j].offset || 0,
                                    closing: !!opt.tags[j].closing
                                });
                            }
                        }
                        optsArr.push({
                            text: opt.text || "",
                            enabled: opt.enabled !== false,
                            tags: optTags
                        });
                    }
                    _eventQueue.push({
                        type: "choice",
                        interpId: interpId,
                        options: optsArr
                    });
                },
                function(interpreter) {
                    _pendingAdvance[interpId] = null;
                    _pendingSelect[interpId] = null;
                    _eventQueue.push({
                        type: "finished",
                        interpId: interpId
                    });
                },
                saveData,
                beatName || null,
                resumeOptions
            );

            if (!interp) {
                delete _store[interpId];
                return 0;
            }
            _store[interpId] = interp;
            return interpId;
        },

        printScript: function(scriptId) {
            var script = _getObj(scriptId);
            if (!script) return "";
            return Loreline.print(script);
        },

        scriptToJson: function(scriptId, pretty) {
            var script = _getObj(scriptId);
            if (!script) return "";
            var json = script.toJson();
            return pretty ? JSON.stringify(json, null, 2) : JSON.stringify(json);
        },

        scriptFromJson: function(jsonStr) {
            try {
                var json = JSON.parse(jsonStr);
                var script = Script.fromJson(json);
                if (!script) return 0;
                return _storeObj(script);
            } catch (e) {
                console.error("Loreline fromJson error:", e);
                return 0;
            }
        },

        // --- Interpreter ---
        releaseInterpreter: function(interpId) {
            delete _pendingAdvance[interpId];
            delete _pendingSelect[interpId];
            _releaseObj(interpId);
        },

        advance: function(interpId) {
            var fn = _pendingAdvance[interpId];
            if (fn) {
                _pendingAdvance[interpId] = null;
                fn();
            }
        },

        select: function(interpId, index) {
            var fn = _pendingSelect[interpId];
            if (fn) {
                _pendingSelect[interpId] = null;
                fn(index);
            }
        },

        start: function(interpId, beatName) {
            var interp = _getObj(interpId);
            if (interp) {
                interp.start(beatName || null);
            }
        },

        save: function(interpId) {
            var interp = _getObj(interpId);
            if (!interp) return "";
            return JSON.stringify(interp.save());
        },

        restore: function(interpId, jsonStr) {
            var interp = _getObj(interpId);
            if (interp) {
                interp.restore(JSON.parse(jsonStr));
            }
        },

        getCharacterField: function(interpId, character, field) {
            var interp = _getObj(interpId);
            if (!interp) return null;
            return interp.getCharacterField(character, field);
        },

        setCharacterField: function(interpId, character, field, value) {
            var interp = _getObj(interpId);
            if (interp) {
                interp.setCharacterField(character, field, value);
            }
        },

        getStateField: function(interpId, field) {
            var interp = _getObj(interpId);
            if (!interp) return null;
            var scope = interp.get_currentScope ? interp.get_currentScope() : null;
            if (!scope || !scope.state) return null;
            return scope.state.getField(field);
        },

        setStateField: function(interpId, field, value) {
            var interp = _getObj(interpId);
            if (!interp) return;
            var scope = interp.get_currentScope ? interp.get_currentScope() : null;
            if (scope && scope.state) {
                scope.state.setField(field, value);
            }
        },

        getTopLevelStateField: function(interpId, field) {
            var interp = _getObj(interpId);
            if (!interp || !interp.topLevelState) return null;
            return interp.topLevelState.getField(field);
        },

        setTopLevelStateField: function(interpId, field, value) {
            var interp = _getObj(interpId);
            if (interp && interp.topLevelState) {
                interp.topLevelState.setField(field, value);
            }
        },

        currentNode: function(interpId) {
            var interp = _getObj(interpId);
            if (!interp) return null;
            var scope = interp.get_currentScope ? interp.get_currentScope() : null;
            if (!scope || !scope.node) return null;
            var node = scope.node;
            var pos = node.pos;
            return JSON.stringify({
                type: node.type ? node.type() : "",
                line: pos ? pos.line : 0,
                column: pos ? pos.column : 0,
                offset: pos ? pos.offset : 0,
                length: pos ? pos.length : 0
            });
        }
    };
})();
)LORELINE_BRIDGE";

#endif // LORELINE_USE_JS
