/*
 * linc_Loreline.cpp — Bridge between Loreline.h (public C++ API) and Haxe/hxcpp
 *
 * Implements all Loreline_* functions declared in Loreline.h.
 * Compiled by hxcpp as part of the static library build.
 */

#ifndef BUILDING_LORELINE
#define BUILDING_LORELINE 1
#endif

#include <hxcpp.h>
#include <loreline/Script.h>
#include <loreline/Interpreter.h>
#include <loreline/Loreline.h>
#include <loreline/Json.h>
#include <loreline/InterpreterOptions.h>
#include <haxe/ds/StringMap.h>
#include "Loreline.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <thread>
#include <vector>

/* ── hxcpp runtime entry points ─────────────────────────────────────────── */

extern "C" void hxcpp_set_top_of_stack();
extern "C" const char* hxRunLibrary();

/* ── Loreline_StringData (ref-counted) ──────────────────────────────────── */

struct Loreline_StringData {
    std::atomic<int> refCount;
    size_t len;
    char data[1]; /* flexible array member */
};

static Loreline_StringData* linc_createStringData(const char* s, size_t len) {
    if (!s) return nullptr;
    Loreline_StringData* d = (Loreline_StringData*)malloc(
        sizeof(Loreline_StringData) + len);
    d->refCount.store(1, std::memory_order_relaxed);
    d->len = len;
    memcpy(d->data, s, len);
    d->data[len] = '\0';
    return d;
}

static void linc_retainStringData(Loreline_StringData* d) {
    if (d) d->refCount.fetch_add(1, std::memory_order_relaxed);
}

static void linc_releaseStringData(Loreline_StringData* d) {
    if (d && d->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        free(d);
    }
}

/* ── Loreline_String implementation ─────────────────────────────────────── */

LORELINE_PUBLIC Loreline_String::Loreline_String() : ptr(nullptr) {}

LORELINE_PUBLIC Loreline_String::Loreline_String(const char* s)
    : ptr(s ? linc_createStringData(s, strlen(s)) : nullptr) {}

LORELINE_PUBLIC Loreline_String::Loreline_String(const char* s, size_t len)
    : ptr(s ? linc_createStringData(s, len) : nullptr) {}

LORELINE_PUBLIC Loreline_String::Loreline_String(const Loreline_String& o) : ptr(o.ptr) {
    linc_retainStringData(ptr);
}

LORELINE_PUBLIC Loreline_String::Loreline_String(Loreline_String&& o) : ptr(o.ptr) {
    o.ptr = nullptr;
}

LORELINE_PUBLIC Loreline_String::~Loreline_String() {
    linc_releaseStringData(ptr);
}

LORELINE_PUBLIC Loreline_String& Loreline_String::operator=(const Loreline_String& o) {
    if (this != &o) {
        linc_retainStringData(o.ptr);
        linc_releaseStringData(ptr);
        ptr = o.ptr;
    }
    return *this;
}

LORELINE_PUBLIC Loreline_String& Loreline_String::operator=(Loreline_String&& o) {
    if (this != &o) {
        linc_releaseStringData(ptr);
        ptr = o.ptr;
        o.ptr = nullptr;
    }
    return *this;
}

LORELINE_PUBLIC const char* Loreline_String::c_str() const {
    return ptr ? ptr->data : nullptr;
}

LORELINE_PUBLIC size_t Loreline_String::length() const {
    return ptr ? ptr->len : 0;
}

LORELINE_PUBLIC bool Loreline_String::isNull() const {
    return ptr == nullptr;
}

LORELINE_PUBLIC Loreline_String::operator bool() const {
    return ptr != nullptr;
}

/* ── Loreline_Value convenience constructors ────────────────────────────── */

LORELINE_PUBLIC Loreline_Value Loreline_Value::null_val() {
    Loreline_Value v;
    v.type = Loreline_Null;
    v.intValue = 0;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_int(int i) {
    Loreline_Value v;
    v.type = Loreline_Int;
    v.intValue = i;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_float(double f) {
    Loreline_Value v;
    v.type = Loreline_Float;
    v.floatValue = f;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_bool(bool b) {
    Loreline_Value v;
    v.type = Loreline_Bool;
    v.boolValue = b;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_string(const char* s) {
    Loreline_Value v;
    v.type = Loreline_StringValue;
    v.intValue = 0;
    v.stringValue = Loreline_String(s);
    return v;
}

/* ── Opaque handles ─────────────────────────────────────────────────────── */

struct Loreline_Script {
    hx::Object* obj;

    Loreline_Script() : obj(nullptr) {}

    void set(hx::Object* o) {
        obj = o;
        if (obj) hx::GCAddRoot(&obj);
    }

    ~Loreline_Script() {
        if (obj) {
            hx::GCRemoveRoot(&obj);
            obj = nullptr;
        }
    }

private:
    Loreline_Script(const Loreline_Script&);
    Loreline_Script& operator=(const Loreline_Script&);
};

struct Loreline_Interpreter {
    hx::Object* obj;
    hx::Object* pendingCb; /* GC-rooted pending callback (advance/select) */
    Loreline_DialogueHandler dialogueHandler;
    Loreline_ChoiceHandler choiceHandler;
    Loreline_FinishHandler finishHandler;
    void* userData;

    Loreline_Interpreter() : obj(nullptr), pendingCb(nullptr), dialogueHandler(nullptr),
        choiceHandler(nullptr), finishHandler(nullptr), userData(nullptr) {}

    void set(hx::Object* o) {
        obj = o;
        if (obj) hx::GCAddRoot(&obj);
    }

    void setPendingCallback(hx::Object* cb) {
        if (pendingCb) { hx::GCRemoveRoot(&pendingCb); pendingCb = nullptr; }
        pendingCb = cb;
        if (pendingCb) hx::GCAddRoot(&pendingCb);
    }

    ~Loreline_Interpreter() {
        if (pendingCb) { hx::GCRemoveRoot(&pendingCb); pendingCb = nullptr; }
        if (obj) { hx::GCRemoveRoot(&obj); obj = nullptr; }
    }

private:
    Loreline_Interpreter(const Loreline_Interpreter&);
    Loreline_Interpreter& operator=(const Loreline_Interpreter&);
};

struct Loreline_Translations {
    hx::Object* obj;

    Loreline_Translations() : obj(nullptr) {}

    void set(hx::Object* o) {
        obj = o;
        if (obj) hx::GCAddRoot(&obj);
    }

    ~Loreline_Translations() {
        if (obj) {
            hx::GCRemoveRoot(&obj);
            obj = nullptr;
        }
    }

private:
    Loreline_Translations(const Loreline_Translations&);
    Loreline_Translations& operator=(const Loreline_Translations&);
};

/* ── Conversion helpers ─────────────────────────────────────────────────── */

static Loreline_String linc_hxToString(::String s) {
    if (s == null()) return Loreline_String();
    const char* cstr = s.c_str();
    return Loreline_String(cstr, strlen(cstr));
}

static ::String linc_toHxString(const char* s) {
    if (!s) return null();
    return ::String(s);
}

static ::String linc_toHxString(const Loreline_String& s) {
    if (s.isNull()) return null();
    return ::String(s.c_str());
}

static Loreline_Value linc_hxToValue(::Dynamic val) {
    if (hx::IsNull(val)) return Loreline_Value::null_val();
    int t = val->__GetType();
    switch (t) {
        case vtBool:
            return Loreline_Value::from_bool((bool)val);
        case vtInt:
            return Loreline_Value::from_int((int)val);
        case vtFloat:
            return Loreline_Value::from_float((double)(Float)val);
        case vtString:
            return Loreline_Value::from_string(((::String)val).c_str());
        default:
            return Loreline_Value::null_val();
    }
}

static ::Dynamic linc_valueToHx(Loreline_Value v) {
    switch (v.type) {
        case Loreline_Int:    return (int)v.intValue;
        case Loreline_Float:  return (Float)v.floatValue;
        case Loreline_Bool:   return (bool)v.boolValue;
        case Loreline_StringValue:
            return v.stringValue.isNull() ? (::Dynamic)null() : (::Dynamic)::String(v.stringValue.c_str());
        default:
            return null();
    }
}

/* ── Thread worker ──────────────────────────────────────────────────────── */

class Loreline_Thread {
public:
    Loreline_Thread() : stopFlag(false) {
        workerThread = std::thread(&Loreline_Thread::threadLoop, this);
    }

    ~Loreline_Thread() {
        {
            std::lock_guard<std::mutex> lock(mtx);
            stopFlag = true;
        }
        cv.notify_one();
        if (workerThread.joinable()) workerThread.join();
    }

    void schedule(std::function<void()> task) {
        {
            std::lock_guard<std::mutex> lock(mtx);
            taskQueue.push(std::move(task));
        }
        cv.notify_one();
    }

    void scheduleSync(std::function<void()> task) {
        auto syncMutex = std::make_shared<std::mutex>();
        auto syncCv = std::make_shared<std::condition_variable>();
        auto completed = std::make_shared<bool>(false);

        auto wrappedTask = [task, syncMutex, syncCv, completed]() {
            task();
            {
                std::lock_guard<std::mutex> lock(*syncMutex);
                *completed = true;
            }
            syncCv->notify_one();
        };

        {
            std::lock_guard<std::mutex> lock(mtx);
            taskQueue.push(std::move(wrappedTask));
        }
        cv.notify_one();

        std::unique_lock<std::mutex> lockSync(*syncMutex);
        syncCv->wait(lockSync, [completed]() { return *completed; });
    }

private:
    void threadLoop() {
        while (true) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lock(mtx);
                cv.wait(lock, [this]() {
                    return !taskQueue.empty() || stopFlag;
                });
                if (stopFlag && taskQueue.empty()) break;
                task = std::move(taskQueue.front());
                taskQueue.pop();
            }
            if (task) task();
        }
    }

    std::thread workerThread;
    std::mutex mtx;
    std::condition_variable cv;
    std::queue<std::function<void()>> taskQueue;
    bool stopFlag;
};

/* ── Dispatch-out queue ─────────────────────────────────────────────────── */

class Loreline_FunctionQueue {
public:
    void add(std::function<void()> func) {
        std::lock_guard<std::mutex> lock(queueMutex);
        functionQueue.push_back(std::move(func));
    }

    void flush() {
        if (functionQueue.empty()) return;
        std::vector<std::function<void()>> tempQueue;
        {
            std::lock_guard<std::mutex> lock(queueMutex);
            tempQueue.swap(functionQueue);
        }
        for (auto& func : tempQueue) {
            func();
        }
    }

private:
    std::mutex queueMutex;
    std::vector<std::function<void()>> functionQueue;
};

/* ── Static state ───────────────────────────────────────────────────────── */

static bool linc_Loreline_didCallHaxeMain = false;
static bool linc_Loreline_useInternalThread = false;
static std::thread::id linc_Loreline_haxeThreadId;
static Loreline_Thread* linc_Loreline_thread = nullptr;
static Loreline_FunctionQueue linc_Loreline_dispatchOutFunctions;
static double linc_Loreline_gcAccum = 0.0;

/* ── ensureHaxeThread ───────────────────────────────────────────────────── */

static void linc_Loreline_ensureHaxeThread() {
    std::thread::id currentThreadId = std::this_thread::get_id();

    if (!linc_Loreline_didCallHaxeMain) {
        linc_Loreline_didCallHaxeMain = true;
        linc_Loreline_haxeThreadId = currentThreadId;
        hxcpp_set_top_of_stack();
        hxRunLibrary();
    }

    if (linc_Loreline_haxeThreadId != currentThreadId) {
        throw std::runtime_error("Calling Loreline from the wrong thread!");
    }
}

/* ── schedule / scheduleSync / dispatchOut ───────────────────────────────── */

static void linc_Loreline_schedule(std::function<void()> task) {
    if (linc_Loreline_useInternalThread && linc_Loreline_thread) {
        linc_Loreline_thread->schedule(std::move(task));
    } else {
        task();
    }
}

static void linc_Loreline_scheduleSync(std::function<void()> task) {
    if (linc_Loreline_useInternalThread && linc_Loreline_thread) {
        linc_Loreline_thread->scheduleSync(std::move(task));
    } else {
        task();
    }
}

static void linc_Loreline_dispatchOut(std::function<void()> task) {
    if (linc_Loreline_useInternalThread) {
        linc_Loreline_dispatchOutFunctions.add(std::move(task));
    } else {
        task();
    }
}

/* ── Call macros ─────────────────────────────────────────────────────────── */

#if defined(_MSC_VER) && _MSC_VER < 1900

    #define LORELINE_BEGIN_CALL \
        linc_Loreline_ensureHaxeThread(); \
        int haxe_stack_ = 99; \
        hx::SetTopOfStack(&haxe_stack_, true);

    #define LORELINE_BEGIN_CALL_SYNC \
        linc_Loreline_ensureHaxeThread(); \
        int haxe_stack_ = 99; \
        hx::SetTopOfStack(&haxe_stack_, true);

    #define LORELINE_END_CALL \
        hx::SetTopOfStack((int*)0, true);

    #define LORELINE_BEGIN_DISPATCH_OUT
    #define LORELINE_END_DISPATCH_OUT

#else

    #define LORELINE_BEGIN_CALL \
        linc_Loreline_schedule([=]() mutable { \
        linc_Loreline_ensureHaxeThread(); \
        int haxe_stack_ = 99; \
        hx::SetTopOfStack(&haxe_stack_, true);

    #define LORELINE_BEGIN_CALL_SYNC \
        linc_Loreline_scheduleSync([&]() { \
        linc_Loreline_ensureHaxeThread(); \
        int haxe_stack_ = 99; \
        hx::SetTopOfStack(&haxe_stack_, true);

    #define LORELINE_END_CALL \
        hx::SetTopOfStack((int*)0, true); \
        });

    #define LORELINE_BEGIN_DISPATCH_OUT \
        linc_Loreline_dispatchOut([=]() {

    #define LORELINE_END_DISPATCH_OUT \
        });

#endif

/* ── API implementation ─────────────────────────────────────────────────── */

LORELINE_PUBLIC void Loreline_init(void) {
    LORELINE_BEGIN_CALL_SYNC
    /* ensureHaxeThread runs inside, initializing the runtime */
    LORELINE_END_CALL
}

LORELINE_PUBLIC void Loreline_dispose(void) {
    LORELINE_BEGIN_CALL
    /* Nothing specific to dispose for now; runtime stays alive */
    LORELINE_END_CALL

    if (linc_Loreline_thread) {
        delete linc_Loreline_thread;
        linc_Loreline_thread = nullptr;
        linc_Loreline_useInternalThread = false;
    }
}

LORELINE_PUBLIC void Loreline_gc(void) {
    LORELINE_BEGIN_CALL
    hx::InternalCollect(false, false);
    LORELINE_END_CALL
}

LORELINE_PUBLIC void Loreline_update(double delta) {
    /* Flush dispatch-out queue on the caller's thread */
    linc_Loreline_dispatchOutFunctions.flush();

    /* Periodic GC (~every 15 seconds) */
    linc_Loreline_gcAccum += delta;
    if (linc_Loreline_gcAccum >= 15.0) {
        linc_Loreline_gcAccum = 0.0;
        LORELINE_BEGIN_CALL
        hx::InternalCollect(false, false);
        LORELINE_END_CALL
    }
}

LORELINE_PUBLIC void Loreline_createThread(void) {
    if (linc_Loreline_useInternalThread) return;
    linc_Loreline_useInternalThread = true;
    linc_Loreline_thread = new Loreline_Thread();
}

/* ── Callback wrapper helpers ───────────────────────────────────────────── */

/* Build a Loreline_TextTag array from Haxe Array<TextTag>.
 * Caller must delete[] the returned array. */
static void linc_buildTextTags(::Dynamic hxTags, Loreline_TextTag** outTags, int* outCount) {
    if (hx::IsNull(hxTags)) {
        *outTags = nullptr;
        *outCount = 0;
        return;
    }

    ::cpp::VirtualArray arr = (::cpp::VirtualArray)hxTags;
    int count = arr->get_length();
    if (count == 0) {
        *outTags = nullptr;
        *outCount = 0;
        return;
    }

    Loreline_TextTag* tags = new Loreline_TextTag[count];
    for (int i = 0; i < count; i++) {
        ::Dynamic tag = arr->__get(i);
        tags[i].value = linc_hxToString(tag->__Field(HX_CSTRING("value"), hx::paccDynamic));
        tags[i].offset = (int)tag->__Field(HX_CSTRING("offset"), hx::paccDynamic);
        tags[i].closing = (bool)tag->__Field(HX_CSTRING("closing"), hx::paccDynamic);
    }
    *outTags = tags;
    *outCount = count;
}

/* Build a Loreline_ChoiceOption array from Haxe Array<ChoiceOption>.
 * Caller must delete[] each option's tags array and the options array itself. */
static void linc_buildChoiceOptions(::Dynamic hxOptions, Loreline_ChoiceOption** outOptions, int* outCount) {
    if (hx::IsNull(hxOptions)) {
        *outOptions = nullptr;
        *outCount = 0;
        return;
    }

    ::cpp::VirtualArray arr = (::cpp::VirtualArray)hxOptions;
    int count = arr->get_length();
    if (count == 0) {
        *outOptions = nullptr;
        *outCount = 0;
        return;
    }

    Loreline_ChoiceOption* options = new Loreline_ChoiceOption[count];
    for (int i = 0; i < count; i++) {
        ::Dynamic opt = arr->__get(i);
        options[i].text = linc_hxToString(opt->__Field(HX_CSTRING("text"), hx::paccDynamic));
        options[i].enabled = (bool)opt->__Field(HX_CSTRING("enabled"), hx::paccDynamic);

        ::Dynamic optTags = opt->__Field(HX_CSTRING("tags"), hx::paccDynamic);
        Loreline_TextTag* tags = nullptr;
        int tagCount = 0;
        linc_buildTextTags(optTags, &tags, &tagCount);
        options[i].tags = tags;
        options[i].tagCount = tagCount;
    }
    *outOptions = options;
    *outCount = count;
}

static void linc_freeChoiceOptions(Loreline_ChoiceOption* options, int count) {
    if (!options) return;
    for (int i = 0; i < count; i++) {
        delete[] options[i].tags;
    }
    delete[] options;
}

/* ── Callback dispatch helpers ─────────────────────────────────────────── */

static Loreline_Interpreter* s_dispatchInterp = nullptr;

static void linc_advance() {
    Loreline_Interpreter* h = s_dispatchInterp;
    if (!h || !h->pendingCb) return;
    ::Dynamic cb = ::Dynamic(h->pendingCb);
    h->setPendingCallback(nullptr);
    LORELINE_BEGIN_CALL
    cb->__run();
    LORELINE_END_CALL
}

static void linc_select(int index) {
    Loreline_Interpreter* h = s_dispatchInterp;
    if (!h || !h->pendingCb) return;
    ::Dynamic cb = ::Dynamic(h->pendingCb);
    h->setPendingCallback(nullptr);
    LORELINE_BEGIN_CALL
    cb->__run(index);
    LORELINE_END_CALL
}

/* ── File handler bridge ───────────────────────────────────────────────── */

static ::Dynamic s_pendingFileProvide;

static void linc_fileProvide(const char* content) {
    if (!hx::IsNull(s_pendingFileProvide)) {
        ::Dynamic cb = s_pendingFileProvide;
        s_pendingFileProvide = null();
        cb->__run(linc_toHxString(content));
    }
}

/* ── Haxe callback closures (using hxcpp local func macros) ────────────── */

/* Helper: lazily set the interpreter handle from the Haxe callback.
 * During play(), callbacks fire synchronously before play() returns,
 * so h->obj may still be null. We grab it from the Haxe callback arg. */
static void linc_ensureInterpHandle(Loreline_Interpreter* h, ::Dynamic hxInterp) {
    if (!h->obj && !hx::IsNull(hxInterp)) {
        h->set(hxInterp.GetPtr());
    }
}

/* Dialogue handler: 1 capture (Loreline_Interpreter*), 5 Haxe args */
HX_BEGIN_LOCAL_FUNC_S1(::hx::LocalFunc, _hx_Closure_dialogue,
    Loreline_Interpreter*, h) HXARGC(5)
void _hx_run(::Dynamic hxInterp, ::Dynamic hxChar, ::Dynamic hxText,
             ::Dynamic hxTags, ::Dynamic hxCallback) {
    linc_ensureInterpHandle(h, hxInterp);
    Loreline_String character = linc_hxToString((::String)hxChar);
    Loreline_String text = linc_hxToString((::String)hxText);
    Loreline_TextTag* tags = nullptr;
    int tagCount = 0;
    linc_buildTextTags(hxTags, &tags, &tagCount);
    h->setPendingCallback(hxCallback.GetPtr());
    LORELINE_BEGIN_DISPATCH_OUT
    s_dispatchInterp = h;
    if (h->dialogueHandler) {
        h->dialogueHandler(h, character, text, tags, tagCount, linc_advance, h->userData);
    }
    delete[] tags;
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC5((void))

/* Choice handler: 1 capture (Loreline_Interpreter*), 3 Haxe args */
HX_BEGIN_LOCAL_FUNC_S1(::hx::LocalFunc, _hx_Closure_choice,
    Loreline_Interpreter*, h) HXARGC(3)
void _hx_run(::Dynamic hxInterp, ::Dynamic hxOptions, ::Dynamic hxCallback) {
    linc_ensureInterpHandle(h, hxInterp);
    Loreline_ChoiceOption* options = nullptr;
    int optionCount = 0;
    linc_buildChoiceOptions(hxOptions, &options, &optionCount);
    h->setPendingCallback(hxCallback.GetPtr());
    LORELINE_BEGIN_DISPATCH_OUT
    s_dispatchInterp = h;
    if (h->choiceHandler) {
        h->choiceHandler(h, options, optionCount, linc_select, h->userData);
    }
    linc_freeChoiceOptions(options, optionCount);
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC3((void))

/* Finish handler: 1 capture (Loreline_Interpreter*), 1 Haxe arg */
HX_BEGIN_LOCAL_FUNC_S1(::hx::LocalFunc, _hx_Closure_finish,
    Loreline_Interpreter*, h) HXARGC(1)
void _hx_run(::Dynamic hxInterp) {
    linc_ensureInterpHandle(h, hxInterp);
    LORELINE_BEGIN_DISPATCH_OUT
    if (h->finishHandler) {
        h->finishHandler(h, h->userData);
    }
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC1((void))

/* File handler: 2 captures (Loreline_FileHandler, void*), 2 Haxe args */
HX_BEGIN_LOCAL_FUNC_S2(::hx::LocalFunc, _hx_Closure_fileHandler,
    Loreline_FileHandler, fh, void*, fhData) HXARGC(2)
void _hx_run(::Dynamic hxPath, ::Dynamic hxCallback) {
    s_pendingFileProvide = hxCallback;
    fh(((::String)hxPath).c_str(), linc_fileProvide, fhData);
    s_pendingFileProvide = null();
}
HX_END_LOCAL_FUNC2((void))

/* ── Parse ──────────────────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_Script* Loreline_parse(
    const char* input,
    const char* filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData
) {
    Loreline_Script* handle = nullptr;

    LORELINE_BEGIN_CALL_SYNC

    ::String hxInput = linc_toHxString(input);
    ::String hxFilePath = linc_toHxString(filePath);

    ::Dynamic hxFileHandler = null();
    if (fileHandler && filePath) {
        hxFileHandler = ::Dynamic(new _hx_Closure_fileHandler(fileHandler, fileHandlerData));
    }

    try {
        ::Dynamic hxScript = ::loreline::Loreline_obj::parse(hxInput, hxFilePath, hxFileHandler, null());

        if (!hx::IsNull(hxScript)) {
            handle = new Loreline_Script();
            handle->set(hxScript.GetPtr());
        }
    } catch (::Dynamic e) {
        /* Haxe parse error — return nullptr */
        fprintf(stderr, "Loreline_parse error: %s\n", ((::String)e).c_str());
    }

    LORELINE_END_CALL

    return handle;
}

/* ── Translations ───────────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_Translations* Loreline_extractTranslations(Loreline_Script* script) {
    if (!script) return nullptr;
    Loreline_Translations* handle = nullptr;

    LORELINE_BEGIN_CALL_SYNC

    ::haxe::ds::StringMap hxTranslations =
        ::loreline::Loreline_obj::extractTranslations((::loreline::Script)::Dynamic(script->obj));

    if (!hx::IsNull(hxTranslations)) {
        handle = new Loreline_Translations();
        handle->set(hxTranslations.GetPtr());
    }

    LORELINE_END_CALL

    return handle;
}

LORELINE_PUBLIC void Loreline_releaseTranslations(Loreline_Translations* translations) {
    if (!translations) return;
    LORELINE_BEGIN_CALL
    delete translations;
    LORELINE_END_CALL
}

/* ── Play ───────────────────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_Interpreter* Loreline_play(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    const char* beatName,
    Loreline_Translations* translations,
    void* userData
) {
    if (!script) return nullptr;

    Loreline_Interpreter* handle = new Loreline_Interpreter();
    handle->dialogueHandler = onDialogue;
    handle->choiceHandler = onChoice;
    handle->finishHandler = onFinish;
    handle->userData = userData;

    Loreline_Interpreter* h = handle;
    ::String hxBeatName = linc_toHxString(beatName);
    ::Dynamic hxScript = ::Dynamic(script->obj);
    hx::Object* translationsObj = translations ? translations->obj : nullptr;

    LORELINE_BEGIN_CALL

    ::Dynamic hxDialogueHandler = ::Dynamic(new _hx_Closure_dialogue(h));
    ::Dynamic hxChoiceHandler = ::Dynamic(new _hx_Closure_choice(h));
    ::Dynamic hxFinishHandler = ::Dynamic(new _hx_Closure_finish(h));

    ::Dynamic hxOptions = null();
    if (translationsObj) {
        ::haxe::ds::StringMap hxTranslations = (::haxe::ds::StringMap)::Dynamic(translationsObj);
        hxOptions = ::loreline::InterpreterOptions_obj::__new(null(), null(), null(), hxTranslations, null());
    }

    try {
        ::Dynamic hxInterp = ::loreline::Loreline_obj::play(
            hxScript, hxDialogueHandler, hxChoiceHandler, hxFinishHandler, hxBeatName, hxOptions
        );
        h->set(hxInterp.GetPtr());
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_play error: %s\n", ((::String)e).c_str());
    }

    LORELINE_END_CALL

    return handle;
}

/* ── Resume ─────────────────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_Interpreter* Loreline_resume(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    const char* saveData,
    const char* beatName,
    Loreline_Translations* translations,
    void* userData
) {
    if (!script || !saveData) return nullptr;

    Loreline_Interpreter* handle = new Loreline_Interpreter();
    handle->dialogueHandler = onDialogue;
    handle->choiceHandler = onChoice;
    handle->finishHandler = onFinish;
    handle->userData = userData;

    Loreline_Interpreter* h = handle;
    ::String hxBeatName = linc_toHxString(beatName);
    ::String hxSaveStr = linc_toHxString(saveData);
    ::Dynamic hxScript = ::Dynamic(script->obj);
    hx::Object* translationsObj = translations ? translations->obj : nullptr;

    LORELINE_BEGIN_CALL

    ::Dynamic hxSaveData = ::loreline::Json_obj::parse(hxSaveStr);

    ::Dynamic hxDialogueHandler = ::Dynamic(new _hx_Closure_dialogue(h));
    ::Dynamic hxChoiceHandler = ::Dynamic(new _hx_Closure_choice(h));
    ::Dynamic hxFinishHandler = ::Dynamic(new _hx_Closure_finish(h));

    ::Dynamic hxOptions = null();
    if (translationsObj) {
        ::haxe::ds::StringMap hxTranslations = (::haxe::ds::StringMap)::Dynamic(translationsObj);
        hxOptions = ::loreline::InterpreterOptions_obj::__new(null(), null(), null(), hxTranslations, null());
    }

    try {
        ::Dynamic hxInterp = ::loreline::Loreline_obj::resume(
            hxScript, hxDialogueHandler, hxChoiceHandler, hxFinishHandler,
            hxSaveData, hxBeatName, hxOptions
        );
        h->set(hxInterp.GetPtr());
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_resume error: %s\n", ((::String)e).c_str());
    }

    LORELINE_END_CALL

    return handle;
}

/* ── Interpreter methods ────────────────────────────────────────────────── */

LORELINE_PUBLIC void Loreline_start(Loreline_Interpreter* interp, const char* beatName) {
    if (!interp) return;
    ::String hxBeatName = linc_toHxString(beatName);

    LORELINE_BEGIN_CALL
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    hxInterp->start(hxBeatName);
    LORELINE_END_CALL
}

LORELINE_PUBLIC Loreline_String Loreline_save(Loreline_Interpreter* interp) {
    if (!interp) return Loreline_String();
    Loreline_String result;

    LORELINE_BEGIN_CALL_SYNC
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic saveData = hxInterp->save();
    ::String json = ::loreline::Json_obj::stringify(saveData, false);
    result = linc_hxToString(json);
    LORELINE_END_CALL

    return result;
}

LORELINE_PUBLIC void Loreline_restore(Loreline_Interpreter* interp, const char* saveData) {
    if (!interp || !saveData) return;
    ::String hxSaveStr = linc_toHxString(saveData);

    LORELINE_BEGIN_CALL
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxSaveData = ::loreline::Json_obj::parse(hxSaveStr);
    hxInterp->restore(hxSaveData);
    hxInterp->resume();
    LORELINE_END_CALL
}

/* ── Character access ───────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_Value Loreline_getCharacterField(
    Loreline_Interpreter* interp, const char* character, const char* field
) {
    if (!interp || !character || !field) return Loreline_Value::null_val();
    Loreline_Value result;

    LORELINE_BEGIN_CALL_SYNC
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic val = hxInterp->getCharacterField(::String(character), ::String(field));
    result = linc_hxToValue(val);
    LORELINE_END_CALL

    return result;
}

LORELINE_PUBLIC void Loreline_setCharacterField(
    Loreline_Interpreter* interp, const char* character, const char* field, Loreline_Value value
) {
    if (!interp || !character || !field) return;

    LORELINE_BEGIN_CALL
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxVal = linc_valueToHx(value);
    hxInterp->setCharacterField(::String(character), ::String(field), hxVal);
    LORELINE_END_CALL
}

/* ── Utility ────────────────────────────────────────────────────────────── */

LORELINE_PUBLIC Loreline_String Loreline_printScript(Loreline_Script* script) {
    if (!script) return Loreline_String();
    Loreline_String result;

    LORELINE_BEGIN_CALL_SYNC
    ::loreline::Script hxScript = (::loreline::Script)::Dynamic(script->obj);
    ::String printed = ::loreline::Loreline_obj::print(hxScript, null(), null());
    result = linc_hxToString(printed);
    LORELINE_END_CALL

    return result;
}

/* ── Resource release ───────────────────────────────────────────────────── */

LORELINE_PUBLIC void Loreline_releaseScript(Loreline_Script* script) {
    if (!script) return;
    LORELINE_BEGIN_CALL
    delete script;
    LORELINE_END_CALL
}

LORELINE_PUBLIC void Loreline_releaseInterpreter(Loreline_Interpreter* interp) {
    if (!interp) return;
    LORELINE_BEGIN_CALL
    delete interp;
    LORELINE_END_CALL
}
