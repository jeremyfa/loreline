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
    static Loreline_Value from_string(const char* v);
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
    const char* path,
    void (*provide)(const char* content),
    void* userData
);

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
    const char* input,
    const char* filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData
);

/* Translations — extract from a script for localized playback */
LORELINE_PUBLIC Loreline_Translations* Loreline_extractTranslations(Loreline_Script* script);
LORELINE_PUBLIC void Loreline_releaseTranslations(Loreline_Translations* translations);

/* Playback */
LORELINE_PUBLIC Loreline_Interpreter* Loreline_play(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    const char* beatName,
    Loreline_Translations* translations,
    void* userData
);

LORELINE_PUBLIC Loreline_Interpreter* Loreline_resume(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    const char* saveData,
    const char* beatName,
    Loreline_Translations* translations,
    void* userData
);

/* Interpreter methods */
LORELINE_PUBLIC void Loreline_start(Loreline_Interpreter* interp, const char* beatName);
LORELINE_PUBLIC Loreline_String Loreline_save(Loreline_Interpreter* interp);
LORELINE_PUBLIC void Loreline_restore(Loreline_Interpreter* interp, const char* saveData);

/* Character access */
LORELINE_PUBLIC Loreline_Value Loreline_getCharacterField(
    Loreline_Interpreter* interp, const char* character, const char* field);
LORELINE_PUBLIC void Loreline_setCharacterField(
    Loreline_Interpreter* interp, const char* character, const char* field, Loreline_Value value);

/* Utility */
LORELINE_PUBLIC Loreline_String Loreline_printScript(Loreline_Script* script);

/* Resource release — only needed for Script and Interpreter handles.
 * Strings and Values are auto-managed via ref counting. */
LORELINE_PUBLIC void Loreline_releaseScript(Loreline_Script* script);
LORELINE_PUBLIC void Loreline_releaseInterpreter(Loreline_Interpreter* interp);

#endif /* LORELINE_H */
