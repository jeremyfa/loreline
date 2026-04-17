/*
 * Loreline — Native C++ API
 *
 * Public header for the Loreline interactive fiction runtime.
 * Link against libLoreline.dylib / libLoreline.so / Loreline.dll.
 *
 * All Loreline_String values are ref-counted and auto-managed.
 * Only Script and Interpreter handles require explicit release.
 */

#ifndef LORELINE_H
#define LORELINE_H

#include <stddef.h>

/* ── Visibility ─────────────────────────────────────────────────────────── */

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef BUILDING_LORELINE
    #ifdef __GNUC__
      #define LORELINE_PUBLIC __attribute__((dllexport))
    #else
      #define LORELINE_PUBLIC __declspec(dllexport)
    #endif
  #else
    #ifdef __GNUC__
      #define LORELINE_PUBLIC __attribute__((dllimport))
    #else
      #define LORELINE_PUBLIC __declspec(dllimport)
    #endif
  #endif
  #define LORELINE_HIDDEN
#else
  #if __GNUC__ >= 4
    #define LORELINE_PUBLIC __attribute__((visibility("default")))
    #define LORELINE_HIDDEN __attribute__((visibility("hidden")))
  #else
    #define LORELINE_PUBLIC
    #define LORELINE_HIDDEN
  #endif
#endif

/* ── Loreline_String (ref-counted) ──────────────────────────────────────── */

struct Loreline_StringData;

class LORELINE_PUBLIC Loreline_String {
    Loreline_StringData* ptr;
public:
    Loreline_String();
    Loreline_String(const char* s);
    Loreline_String(const char* s, size_t len);
    Loreline_String(const Loreline_String& o);
    Loreline_String(Loreline_String&& o);
    ~Loreline_String();
    Loreline_String& operator=(const Loreline_String& o);
    Loreline_String& operator=(Loreline_String&& o);

    const char* c_str() const;
    size_t length() const;
    bool isNull() const;
    operator bool() const;
};

/* ── Opaque handle types ────────────────────────────────────────────────── */

typedef struct Loreline_Script Loreline_Script;
typedef struct Loreline_Interpreter Loreline_Interpreter;
typedef struct Loreline_Translations Loreline_Translations;
typedef struct Loreline_InterpreterOptions Loreline_InterpreterOptions;
typedef struct Loreline_AsyncResolve Loreline_AsyncResolve;

/* ── Value type (tagged union for character fields) ─────────────────────── */

enum Loreline_ValueType {
    Loreline_Null = 0,
    Loreline_Int,
    Loreline_Float,
    Loreline_Bool,
    Loreline_StringValue
};

struct LORELINE_PUBLIC Loreline_Value {
    Loreline_ValueType type;
    union {
        int intValue;
        double floatValue;
        bool boolValue;
    };
    Loreline_String stringValue;

    static Loreline_Value null_val();
    static Loreline_Value from_int(int v);
    static Loreline_Value from_float(double v);
    static Loreline_Value from_bool(bool v);
    static Loreline_Value from_string(Loreline_String v);
};

/* ── Node info ──────────────────────────────────────────────────────────── */

struct Loreline_Node {
    Loreline_String type;
    int line;
    int column;
    int offset;
    int length;
};

/* ── Data structs ───────────────────────────────────────────────────────── */

struct Loreline_TextTag {
    Loreline_String value;
    int offset;
    bool closing;
};

struct Loreline_ChoiceOption {
    Loreline_String text;
    const Loreline_TextTag* tags;
    int tagCount;
    bool enabled;
};

/* ── Callback typedefs ──────────────────────────────────────────────────── */

typedef void (*Loreline_DialogueHandler)(
    Loreline_Interpreter* interpreter,
    Loreline_String character,
    Loreline_String text,
    const Loreline_TextTag* tags,
    int tagCount,
    void (*advance)(void),
    void* userData
);

typedef void (*Loreline_ChoiceHandler)(
    Loreline_Interpreter* interpreter,
    const Loreline_ChoiceOption* options,
    int optionCount,
    void (*select)(int index),
    void* userData
);

typedef void (*Loreline_FinishHandler)(
    Loreline_Interpreter* interpreter,
    void* userData
);

typedef void (*Loreline_FileHandler)(
    Loreline_String path,
    void (*provide)(Loreline_String content),
    void* userData
);

/* Sync custom function: called on the host thread, must return immediately. */
typedef Loreline_Value (*Loreline_CustomFunction)(
    Loreline_Interpreter* interp,
    const Loreline_Value* args,
    int argCount,
    void* userData
);

/* Async custom function: called on the host thread, provides result later via resolve handle.
 * Only works in statement context (not expressions/interpolation). */
typedef void (*Loreline_AsyncCustomFunction)(
    Loreline_Interpreter* interp,
    const Loreline_Value* args,
    int argCount,
    Loreline_AsyncResolve* resolve,
    void* userData
);

/* Opaque host-provided retainer. The host decides what this points at; the
 * Loreline wrapper only passes it between retain and release calls. */
typedef struct Loreline_Retainer Loreline_Retainer;

/* Called BEFORE a custom-function invocation is queued onto the dispatch
 * queue. Host implementations typically bump a refcount on whatever object
 * backs `userData` and return a handle encoding how to release it. Return
 * NULL if no retention is needed; release will then also be called with NULL. */
typedef Loreline_Retainer *(*Loreline_UserDataRetain)(void *userData);

/* Called AFTER a custom-function invocation has run (or after an exception
 * escapes it). Host decrements whatever retain bumped. Safe with NULL. */
typedef void (*Loreline_UserDataRelease)(Loreline_Retainer *retainer);


/* ── Core functions ─────────────────────────────────────────────────────── */

/* Lifecycle */
LORELINE_PUBLIC void Loreline_init(void);
LORELINE_PUBLIC void Loreline_dispose(void);
LORELINE_PUBLIC void Loreline_gc(void);

/* Update — call from the host's main loop.
 * Flushes pending callbacks and runs periodic GC. */
LORELINE_PUBLIC void Loreline_update(double delta);

/* Threading — creates a dedicated internal thread for Loreline.
 * When active, incoming calls route to the internal thread;
 * callbacks are dispatched on the caller's thread via Loreline_update(). */
LORELINE_PUBLIC void Loreline_createThread(void);

/* Parsing */
LORELINE_PUBLIC Loreline_Script* Loreline_parse(
    Loreline_String input,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData
);

/* Translations — extract from a script for localized playback */
LORELINE_PUBLIC Loreline_Translations* Loreline_extractTranslations(Loreline_Script* script);
LORELINE_PUBLIC void Loreline_releaseTranslations(Loreline_Translations* translations);

/* Interpreter options — configure custom functions, strict access, translations */
LORELINE_PUBLIC Loreline_InterpreterOptions* Loreline_createOptions(void);
LORELINE_PUBLIC void Loreline_releaseOptions(Loreline_InterpreterOptions* options);
LORELINE_PUBLIC void Loreline_optionsSetStrictAccess(
    Loreline_InterpreterOptions* options, bool strict);
LORELINE_PUBLIC void Loreline_optionsSetTranslations(
    Loreline_InterpreterOptions* options, Loreline_Translations* translations);
LORELINE_PUBLIC void Loreline_optionsAddFunction(
    Loreline_InterpreterOptions* options,
    Loreline_String name,
    Loreline_CustomFunction fn,
    void* userData);
LORELINE_PUBLIC void Loreline_optionsAddAsyncFunction(
    Loreline_InterpreterOptions* options,
    Loreline_String name,
    Loreline_AsyncCustomFunction fn,
    void* userData);
/* Resolve an async custom function call. Can be called from any thread. */
LORELINE_PUBLIC void Loreline_resolveAsync(
    Loreline_AsyncResolve* resolve,
    Loreline_Value result);

/* Cancel an async custom function call without resuming the interpreter.
 * Releases the resolve handle and its internal GC root on the done closure,
 * but does not invoke the closure. Use when the host drops the resolve
 * handle without resolving (e.g. the GDScript Callable was released before
 * resolve.call() fired). The Haxe-side Async state is cleaned up naturally
 * when the interpreter itself is released. */
LORELINE_PUBLIC void Loreline_cancelAsync(
    Loreline_AsyncResolve* resolve);

/* Playback */
LORELINE_PUBLIC Loreline_Interpreter* Loreline_play(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    Loreline_String beatName,
    Loreline_InterpreterOptions* options,
    void* userData,
    Loreline_UserDataRetain retain,     /* may be NULL */
    Loreline_UserDataRelease release    /* may be NULL */
);

LORELINE_PUBLIC Loreline_Interpreter* Loreline_resume(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    Loreline_String saveData,
    Loreline_String beatName,
    Loreline_InterpreterOptions* options,
    void* userData,
    Loreline_UserDataRetain retain,     /* may be NULL */
    Loreline_UserDataRelease release    /* may be NULL */
);

/* Interpreter methods */
LORELINE_PUBLIC void Loreline_start(Loreline_Interpreter* interp, Loreline_String beatName);
LORELINE_PUBLIC Loreline_String Loreline_save(Loreline_Interpreter* interp);
LORELINE_PUBLIC void Loreline_restore(Loreline_Interpreter* interp, Loreline_String saveData);

/* Character access */
LORELINE_PUBLIC Loreline_Value Loreline_getCharacterField(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field);
LORELINE_PUBLIC void Loreline_setCharacterField(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field, Loreline_Value value);

/* State field access (scope-aware) */
LORELINE_PUBLIC Loreline_Value Loreline_getStateField(
    Loreline_Interpreter* interp, Loreline_String field);
LORELINE_PUBLIC void Loreline_setStateField(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value);

/* Top-level state field access */
LORELINE_PUBLIC Loreline_Value Loreline_getTopLevelStateField(
    Loreline_Interpreter* interp, Loreline_String field);
LORELINE_PUBLIC void Loreline_setTopLevelStateField(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value);

/* Current node — returns info about the node being executed.
 * Returns a Loreline_Node with type set to null if no node is current. */
LORELINE_PUBLIC Loreline_Node Loreline_currentNode(Loreline_Interpreter* interp);

/* Utility */
LORELINE_PUBLIC Loreline_String Loreline_printScript(Loreline_Script* script);
LORELINE_PUBLIC Loreline_String Loreline_scriptToJson(Loreline_Script* script, bool pretty);
LORELINE_PUBLIC Loreline_Script* Loreline_scriptFromJson(Loreline_String json);

/* Resource release — only needed for Script and Interpreter handles.
 * Strings and Values are auto-managed via ref counting. */
LORELINE_PUBLIC void Loreline_releaseScript(Loreline_Script* script);
LORELINE_PUBLIC void Loreline_releaseInterpreter(Loreline_Interpreter* interp);

#endif /* LORELINE_H */
