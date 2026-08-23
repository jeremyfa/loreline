/*
 * linc_Loreline.cpp - Bridge between Loreline.h (public C++ API) and Haxe/hxcpp
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
#include <loreline/Error.h>
#include <loreline/Json.h>
#include <loreline/InterpreterOptions.h>
#include <loreline/Timer.h>
#include <loreline/Async.h>
#include <loreline/Arrays.h>
#include <loreline/Objects.h>
#include <loreline/RuntimeBeatRef.h>
#include <loreline/NBeatDecl.h>
#include <haxe/ds/StringMap.h>
#include <Reflect.h>
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

/* -- hxcpp runtime entry points ------------------------------------------- */

extern "C" void hxcpp_set_top_of_stack();
extern "C" const char* hxRunLibrary();

/* -- Loreline_StringData (ref-counted) ------------------------------------ */

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

/* -- Loreline_String implementation --------------------------------------- */

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

/* -- Loreline_Value convenience constructors ------------------------------ */

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

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_string(Loreline_String s) {
    Loreline_Value v;
    v.type = Loreline_StringValue;
    v.intValue = 0;
    v.stringValue = s;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_array(Loreline_Array a) {
    Loreline_Value v;
    v.type = Loreline_ArrayValue;
    v.intValue = 0;
    v.arrayValue = a;
    return v;
}

LORELINE_PUBLIC Loreline_Value Loreline_Value::from_object(Loreline_Object o) {
    Loreline_Value v;
    v.type = Loreline_ObjectValue;
    v.intValue = 0;
    v.objectValue = o;
    return v;
}

/* -- Loreline_ArrayData / Loreline_ObjectData (ref-counted) ---------------- */
/* Same lifetime model as Loreline_StringData, but allocated with new/delete
 * because the payloads hold RAII members. Values inside are fully owned
 * deep copies: no hxcpp GC pointers, safe to cross threads by value. */

struct Loreline_ArrayData {
    std::atomic<int> refCount;
    std::vector<Loreline_Value> items;
    Loreline_ArrayData() { refCount.store(1, std::memory_order_relaxed); }
};

static void linc_retainArrayData(Loreline_ArrayData* d) {
    if (d) d->refCount.fetch_add(1, std::memory_order_relaxed);
}

static void linc_releaseArrayData(Loreline_ArrayData* d) {
    if (d && d->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete d;
    }
}

struct Loreline_ObjectData {
    std::atomic<int> refCount;
    std::vector<std::pair<Loreline_String, Loreline_Value>> entries;
    Loreline_ObjectData() { refCount.store(1, std::memory_order_relaxed); }
};

static void linc_retainObjectData(Loreline_ObjectData* d) {
    if (d) d->refCount.fetch_add(1, std::memory_order_relaxed);
}

static void linc_releaseObjectData(Loreline_ObjectData* d) {
    if (d && d->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete d;
    }
}

/* -- Loreline_Array implementation ------------------------------------------ */

LORELINE_PUBLIC Loreline_Array::Loreline_Array() : ptr(nullptr) {}

LORELINE_PUBLIC Loreline_Array::Loreline_Array(const Loreline_Array& o) : ptr(o.ptr) {
    linc_retainArrayData(ptr);
}

LORELINE_PUBLIC Loreline_Array::Loreline_Array(Loreline_Array&& o) : ptr(o.ptr) {
    o.ptr = nullptr;
}

LORELINE_PUBLIC Loreline_Array::~Loreline_Array() {
    linc_releaseArrayData(ptr);
}

LORELINE_PUBLIC Loreline_Array& Loreline_Array::operator=(const Loreline_Array& o) {
    if (this != &o) {
        linc_retainArrayData(o.ptr);
        linc_releaseArrayData(ptr);
        ptr = o.ptr;
    }
    return *this;
}

LORELINE_PUBLIC Loreline_Array& Loreline_Array::operator=(Loreline_Array&& o) {
    if (this != &o) {
        linc_releaseArrayData(ptr);
        ptr = o.ptr;
        o.ptr = nullptr;
    }
    return *this;
}

LORELINE_PUBLIC Loreline_Array Loreline_Array::create() {
    Loreline_Array a;
    a.ptr = new Loreline_ArrayData();
    return a;
}

LORELINE_PUBLIC int Loreline_Array::length() const {
    return ptr ? (int)ptr->items.size() : 0;
}

LORELINE_PUBLIC Loreline_Value Loreline_Array::get(int index) const {
    if (ptr && index >= 0 && index < (int)ptr->items.size()) {
        return ptr->items[index];
    }
    return Loreline_Value::null_val();
}

LORELINE_PUBLIC void Loreline_Array::set(int index, Loreline_Value value) {
    if (ptr && index >= 0 && index < (int)ptr->items.size()) {
        ptr->items[index] = value;
    }
}

LORELINE_PUBLIC void Loreline_Array::push(Loreline_Value value) {
    if (ptr) {
        ptr->items.push_back(value);
    }
}

LORELINE_PUBLIC bool Loreline_Array::isNull() const {
    return ptr == nullptr;
}

LORELINE_PUBLIC Loreline_Array::operator bool() const {
    return ptr != nullptr;
}

/* -- Loreline_Object implementation ----------------------------------------- */

LORELINE_PUBLIC Loreline_Object::Loreline_Object() : ptr(nullptr) {}

LORELINE_PUBLIC Loreline_Object::Loreline_Object(const Loreline_Object& o) : ptr(o.ptr) {
    linc_retainObjectData(ptr);
}

LORELINE_PUBLIC Loreline_Object::Loreline_Object(Loreline_Object&& o) : ptr(o.ptr) {
    o.ptr = nullptr;
}

LORELINE_PUBLIC Loreline_Object::~Loreline_Object() {
    linc_releaseObjectData(ptr);
}

LORELINE_PUBLIC Loreline_Object& Loreline_Object::operator=(const Loreline_Object& o) {
    if (this != &o) {
        linc_retainObjectData(o.ptr);
        linc_releaseObjectData(ptr);
        ptr = o.ptr;
    }
    return *this;
}

LORELINE_PUBLIC Loreline_Object& Loreline_Object::operator=(Loreline_Object&& o) {
    if (this != &o) {
        linc_releaseObjectData(ptr);
        ptr = o.ptr;
        o.ptr = nullptr;
    }
    return *this;
}

LORELINE_PUBLIC Loreline_Object Loreline_Object::create() {
    Loreline_Object o;
    o.ptr = new Loreline_ObjectData();
    return o;
}

LORELINE_PUBLIC int Loreline_Object::count() const {
    return ptr ? (int)ptr->entries.size() : 0;
}

LORELINE_PUBLIC Loreline_String Loreline_Object::keyAt(int index) const {
    if (ptr && index >= 0 && index < (int)ptr->entries.size()) {
        return ptr->entries[index].first;
    }
    return Loreline_String();
}

LORELINE_PUBLIC Loreline_Value Loreline_Object::get(const char* key) const {
    if (ptr && key) {
        for (auto& entry : ptr->entries) {
            if (entry.first.c_str() && strcmp(entry.first.c_str(), key) == 0) {
                return entry.second;
            }
        }
    }
    return Loreline_Value::null_val();
}

LORELINE_PUBLIC void Loreline_Object::set(const char* key, Loreline_Value value) {
    if (!ptr || !key) return;
    for (auto& entry : ptr->entries) {
        if (entry.first.c_str() && strcmp(entry.first.c_str(), key) == 0) {
            entry.second = value;
            return;
        }
    }
    ptr->entries.push_back(std::make_pair(Loreline_String(key), value));
}

LORELINE_PUBLIC bool Loreline_Object::exists(const char* key) const {
    if (ptr && key) {
        for (auto& entry : ptr->entries) {
            if (entry.first.c_str() && strcmp(entry.first.c_str(), key) == 0) {
                return true;
            }
        }
    }
    return false;
}

LORELINE_PUBLIC void Loreline_Object::remove(const char* key) {
    if (!ptr || !key) return;
    for (auto it = ptr->entries.begin(); it != ptr->entries.end(); ++it) {
        if (it->first.c_str() && strcmp(it->first.c_str(), key) == 0) {
            ptr->entries.erase(it);
            return;
        }
    }
}

LORELINE_PUBLIC bool Loreline_Object::isNull() const {
    return ptr == nullptr;
}

LORELINE_PUBLIC Loreline_Object::operator bool() const {
    return ptr != nullptr;
}

/* -- Opaque handles ------------------------------------------------------- */

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
    Loreline_UserDataRetain retain;   /* may be NULL */
    Loreline_UserDataRelease release; /* may be NULL */
    /* Retainer held while playback is running toward the next host callback.
     * Taken synchronously on the host thread whenever the host hands control
     * back to Loreline (play/resume/start/advance/select/resolveAsync), while
     * the host's own reference is still known-alive. Released on the host
     * thread at the start of the next callback delivery, where the dispatch
     * site's own retainer takes over for the duration of the handler. This
     * closes the window where a callback has been queued (or is about to be
     * produced) but not delivered yet: without it, a host that drops its last
     * reference right after advance()/select() frees userData while the Haxe
     * side still owes it a callback. */
    Loreline_Retainer* inflight;

    Loreline_Interpreter() : obj(nullptr), pendingCb(nullptr), dialogueHandler(nullptr),
        choiceHandler(nullptr), finishHandler(nullptr), userData(nullptr),
        retain(nullptr), release(nullptr), inflight(nullptr) {}

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

struct Loreline_AsyncResolve {
    hx::Object* doneObj;
    /* Owning interpreter handle, so Loreline_resolveAsync can re-arm the
     * inflight retainer when the host resumes playback through this token.
     * Valid as long as the host follows the contract of not resolving after
     * releasing the interpreter. */
    Loreline_Interpreter* interp;

    Loreline_AsyncResolve() : doneObj(nullptr), interp(nullptr) {}

    void setDone(hx::Object* d) {
        doneObj = d;
        if (doneObj) hx::GCAddRoot(&doneObj);
    }

    ~Loreline_AsyncResolve() {
        if (doneObj) {
            hx::GCRemoveRoot(&doneObj);
            doneObj = nullptr;
        }
    }

private:
    Loreline_AsyncResolve(const Loreline_AsyncResolve&);
    Loreline_AsyncResolve& operator=(const Loreline_AsyncResolve&);
};

struct Loreline_InterpreterOptions {
    bool strictAccess;
    hx::Object* translationsObj; /* GC-rooted Haxe StringMap, or nullptr */

    struct FunctionEntry {
        std::string name;
        Loreline_CustomFunction syncFn;
        Loreline_AsyncCustomFunction asyncFn;
        void* userData;
    };
    std::vector<FunctionEntry> functions;

    Loreline_InterpreterOptions()
        : strictAccess(false), translationsObj(nullptr) {}

    void setTranslations(hx::Object* t) {
        if (translationsObj) hx::GCRemoveRoot(&translationsObj);
        translationsObj = t;
        if (translationsObj) hx::GCAddRoot(&translationsObj);
    }

    ~Loreline_InterpreterOptions() {
        if (translationsObj) {
            hx::GCRemoveRoot(&translationsObj);
            translationsObj = nullptr;
        }
    }

private:
    Loreline_InterpreterOptions(const Loreline_InterpreterOptions&);
    Loreline_InterpreterOptions& operator=(const Loreline_InterpreterOptions&);
};

/* -- Conversion helpers --------------------------------------------------- */

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

/* Bounds recursion when deep-copying containers and doubles as a cycle
 * guard: values nested deeper than this become null. */
static const int LINC_VALUE_MAX_DEPTH = 64;

static Loreline_Value linc_hxToValueDepth(::Dynamic val, int depth) {
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
            break;
    }

    if (depth >= LINC_VALUE_MAX_DEPTH) {
        return Loreline_Value::null_val();
    }

    /* Beat values and beat references cross the boundary as their beat
     * name string: the captured scope chain is not representable host-side,
     * but the name remains usable with the dynamic beat APIs. Must be
     * checked before isFields, whose unknown-object default is true. */
    {
        ::loreline::NBeatDecl beat = ::loreline::RuntimeBeatRef_obj::beatOf(val);
        if (hx::IsNotNull(beat)) {
            ::String name = beat->name;
            if (hx::IsNull(name)) return Loreline_Value::null_val();
            return Loreline_Value::from_string(Loreline_String(name.c_str()));
        }
    }

    if (::loreline::Arrays_obj::isArray(val)) {
        Loreline_Array arr = Loreline_Array::create();
        int len = ::loreline::Arrays_obj::arrayLength(val);
        for (int i = 0; i < len; i++) {
            arr.push(linc_hxToValueDepth(::loreline::Arrays_obj::arrayGet(val, i), depth + 1));
        }
        return Loreline_Value::from_array(arr);
    }

    if (::loreline::Objects_obj::isFields(val)) {
        Loreline_Object obj = Loreline_Object::create();
        ::Array< ::String > keys = ::loreline::Objects_obj::getFields(null(), val);
        int len = keys->length;
        for (int i = 0; i < len; i++) {
            ::String key = keys->__get(i);
            if (hx::IsNull(key)) continue;
            ::Dynamic fieldVal = ::loreline::Objects_obj::getField(null(), val, key);
            obj.set(key.c_str(), linc_hxToValueDepth(fieldVal, depth + 1));
        }
        return Loreline_Value::from_object(obj);
    }

    return Loreline_Value::null_val();
}

static Loreline_Value linc_hxToValue(::Dynamic val) {
    return linc_hxToValueDepth(val, 0);
}

static ::Dynamic linc_valueToHx(Loreline_Value v) {
    switch (v.type) {
        case Loreline_Int:    return (int)v.intValue;
        case Loreline_Float:  return (Float)v.floatValue;
        case Loreline_Bool:   return (bool)v.boolValue;
        case Loreline_StringValue:
            return v.stringValue.isNull() ? (::Dynamic)null() : (::Dynamic)::String(v.stringValue.c_str());
        case Loreline_ArrayValue: {
            if (v.arrayValue.isNull()) return null();
            ::Dynamic arr = ::loreline::Arrays_obj::createArray();
            int len = v.arrayValue.length();
            for (int i = 0; i < len; i++) {
                ::loreline::Arrays_obj::arrayPush(arr, linc_valueToHx(v.arrayValue.get(i)));
            }
            return arr;
        }
        case Loreline_ObjectValue: {
            if (v.objectValue.isNull()) return null();
            ::Dynamic fields = ::loreline::Objects_obj::createFields(null(), null(), null());
            int len = v.objectValue.count();
            for (int i = 0; i < len; i++) {
                Loreline_String key = v.objectValue.keyAt(i);
                if (key.isNull()) continue;
                ::loreline::Objects_obj::setField(null(), fields, ::String(key.c_str()), linc_valueToHx(v.objectValue.get(key.c_str())));
            }
            return fields;
        }
        default:
            return null();
    }
}

/* -- Thread worker -------------------------------------------------------- */

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

/* -- Dispatch-out queue --------------------------------------------------- */

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

/* -- Static state --------------------------------------------------------- */

static bool linc_Loreline_didCallHaxeMain = false;
static bool linc_Loreline_useInternalThread = false;
static bool linc_Loreline_deferCallbacks = false;
static std::thread::id linc_Loreline_haxeThreadId;
static Loreline_Thread* linc_Loreline_thread = nullptr;
static Loreline_FunctionQueue linc_Loreline_dispatchOutFunctions;
static double linc_Loreline_gcAccum = 0.0;

/* -- ensureHaxeThread ----------------------------------------------------- */

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

/* -- schedule / scheduleSync / dispatchOut --------------------------------- */

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
    if (linc_Loreline_useInternalThread || linc_Loreline_deferCallbacks) {
        linc_Loreline_dispatchOutFunctions.add(std::move(task));
    } else {
        task();
    }
}

/* Reverse sync dispatch: hxcpp thread -> main thread, blocking.
 * Used by sync custom functions in threaded mode (Android). */
static void linc_Loreline_dispatchOutSync(std::function<void()> task) {
    if (!linc_Loreline_useInternalThread) {
        task();
        return;
    }
    auto syncMutex = std::make_shared<std::mutex>();
    auto syncCv = std::make_shared<std::condition_variable>();
    auto completed = std::make_shared<bool>(false);

    linc_Loreline_dispatchOutFunctions.add([task, syncMutex, syncCv, completed]() {
        task();
        {
            std::lock_guard<std::mutex> lock(*syncMutex);
            *completed = true;
        }
        syncCv->notify_one();
    });

    std::unique_lock<std::mutex> lock(*syncMutex);
    syncCv->wait(lock, [completed]() { return *completed; });
}

/* -- Call macros ----------------------------------------------------------- */

#if defined(_MSC_VER)
    #define LORELINE_NOINLINE __declspec(noinline)
#else
    #define LORELINE_NOINLINE __attribute__((noinline))
#endif

#define LORELINE_HX_BEGIN \
    linc_Loreline_ensureHaxeThread(); \
    int haxe_stack_ = 99; \
    hx::SetTopOfStack(&haxe_stack_, true);

#define LORELINE_HX_END \
    hx::SetTopOfStack((int*)0, true);

#define LORELINE_BEGIN_CALL \
    linc_Loreline_schedule([=]() mutable {

#define LORELINE_BEGIN_CALL_SYNC \
    linc_Loreline_scheduleSync([&]() {

#define LORELINE_END_CALL \
    });

#define LORELINE_BEGIN_DISPATCH_OUT \
    linc_Loreline_dispatchOut([=]() {

#define LORELINE_END_DISPATCH_OUT \
    });

/* -- API implementation --------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_init_hx() {
    LORELINE_HX_BEGIN
    /* ensureHaxeThread runs inside, initializing the runtime */
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_init(void) {
    LORELINE_BEGIN_CALL_SYNC
    Loreline_init_hx();
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void Loreline_dispose_hx() {
    LORELINE_HX_BEGIN
    /* Nothing specific to dispose for now; runtime stays alive */
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_dispose(void) {
    LORELINE_BEGIN_CALL
    Loreline_dispose_hx();
    LORELINE_END_CALL
    // Thread is NOT destroyed, haxe must remain on its original thread.
    // The thread sleeps on cv.wait() when idle, consuming no CPU.
}

static LORELINE_NOINLINE void Loreline_gc_hx() {
    LORELINE_HX_BEGIN
    hx::InternalCollect(false, false);
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_gc(void) {
    LORELINE_BEGIN_CALL
    Loreline_gc_hx();
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void Loreline_update_hx(double delta) {
    LORELINE_HX_BEGIN
    ::loreline::Timer_obj::update(delta);
    linc_Loreline_gcAccum += delta;
    if (linc_Loreline_gcAccum >= 15.0) {
        linc_Loreline_gcAccum = 0.0;
        hx::InternalCollect(false, false);
    }
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_update(double delta) {
    /* After the first update() call, always defer callbacks through the dispatch
     * queue, even in single-threaded mode. This ensures game engines (Godot, Unity)
     * can connect signal handlers between play() and the first callback dispatch. */
    linc_Loreline_deferCallbacks = true;

    /* Flush dispatch-out queue on the caller's thread */
    linc_Loreline_dispatchOutFunctions.flush();

    /* Everything else on the interpreter's thread: timer ticking + periodic GC */
    LORELINE_BEGIN_CALL
    Loreline_update_hx(delta);
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void Loreline_createThread_hx() {
    LORELINE_HX_BEGIN
    ::loreline::Timer_obj::enableDeferredMode();
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_createThread(void) {
    if (linc_Loreline_useInternalThread) return;
    linc_Loreline_useInternalThread = true;
    linc_Loreline_thread = new Loreline_Thread();
    /* Enable deferred timer mode before any interpreter work starts */
    LORELINE_BEGIN_CALL_SYNC
    Loreline_createThread_hx();
    LORELINE_END_CALL
}

/* -- Callback wrapper helpers --------------------------------------------- */

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

/* -- Callback dispatch helpers ------------------------------------------- */

static Loreline_Interpreter* s_dispatchInterp = nullptr;

/* Arm the inflight retainer. Host thread only, and only from call sites where
 * the host demonstrably holds a live reference (we are inside a method call
 * on its object). No-op if already armed: an armed retainer already covers
 * the run up to the next delivery. */
static void linc_retainInflight(Loreline_Interpreter* h) {
    if (h && h->retain && !h->inflight) {
        h->inflight = h->retain(h->userData);
    }
}

/* Disarm and release the inflight retainer. Host thread only. Called at the
 * start of each callback delivery (the dispatch site's own retainer keeps
 * userData alive through the handler), and when the interpreter is
 * explicitly released mid-run. */
static void linc_releaseInflight(Loreline_Interpreter* h) {
    if (h && h->inflight) {
        Loreline_Retainer* r = h->inflight;
        h->inflight = nullptr;
        if (h->release) h->release(r);
    }
}

static LORELINE_NOINLINE void linc_advance_hx(Loreline_Interpreter* h, ::Dynamic cb) {
    LORELINE_HX_BEGIN
    try {
        cb->__run();
    } catch (::Dynamic e) {
        ::String msg = (::String)e;
        fprintf(stderr, "Loreline advance error: %s\n", msg.c_str());
        /* The run aborted: no delivery will come to disarm the inflight
         * retainer, so release it from the host thread. */
        linc_Loreline_dispatchOut([h]() { linc_releaseInflight(h); });
    }
    LORELINE_HX_END
}

static void linc_advance() {
    Loreline_Interpreter* h = s_dispatchInterp;
    if (!h || !h->pendingCb) return;
    ::Dynamic cb = ::Dynamic(h->pendingCb);
    h->setPendingCallback(nullptr);
    /* The host hands control back: keep userData alive until the next
     * callback delivery, even if the host drops its references now. */
    linc_retainInflight(h);
    LORELINE_BEGIN_CALL
    linc_advance_hx(h, cb);
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void linc_select_hx(Loreline_Interpreter* h, ::Dynamic cb, int index) {
    LORELINE_HX_BEGIN
    try {
        cb->__run(index);
    } catch (::Dynamic e) {
        ::String msg = (::String)e;
        fprintf(stderr, "Loreline select error: %s\n", msg.c_str());
        /* The run aborted: no delivery will come to disarm the inflight
         * retainer, so release it from the host thread. */
        linc_Loreline_dispatchOut([h]() { linc_releaseInflight(h); });
    }
    LORELINE_HX_END
}

static void linc_select(int index) {
    Loreline_Interpreter* h = s_dispatchInterp;
    if (!h || !h->pendingCb) return;
    ::Dynamic cb = ::Dynamic(h->pendingCb);
    h->setPendingCallback(nullptr);
    /* The host hands control back: keep userData alive until the next
     * callback delivery, even if the host drops its references now. */
    linc_retainInflight(h);
    LORELINE_BEGIN_CALL
    linc_select_hx(h, cb, index);
    LORELINE_END_CALL
}

/* -- File request token -------------------------------------------------- */

/* Per-call retainer for an in-flight file load. Holds a GC root on the Haxe
 * callback so it survives across the host's fh() return and any deferred
 * provide invocation. Mirrors Loreline_Interpreter::pendingCb pattern. */
struct Loreline_FileRequest {
    hx::Object* cb;

    Loreline_FileRequest() : cb(nullptr) {}

    void setCallback(hx::Object* c) {
        if (cb) { hx::GCRemoveRoot(&cb); cb = nullptr; }
        cb = c;
        if (cb) hx::GCAddRoot(&cb);
    }

    ~Loreline_FileRequest() {
        if (cb) { hx::GCRemoveRoot(&cb); cb = nullptr; }
    }

private:
    Loreline_FileRequest(const Loreline_FileRequest&);
    Loreline_FileRequest& operator=(const Loreline_FileRequest&);
};

static LORELINE_NOINLINE void Loreline_provideFile_hx(Loreline_FileRequest* req, Loreline_String content) {
    LORELINE_HX_BEGIN
    hx::Object* cbPtr = req->cb;
    if (cbPtr) {
        hx::GCRemoveRoot(&req->cb);
        req->cb = nullptr;
        ::Dynamic cb(cbPtr);
        try {
            cb->__run(linc_toHxString(content));
        } catch (::Dynamic e) {
            fprintf(stderr, "Loreline file provide error: %s\n", ((::String)e).c_str());
        }
    }
    delete req;
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_provideFile(Loreline_FileRequest* request, Loreline_String content) {
    if (!request) return;
    LORELINE_BEGIN_CALL
    Loreline_provideFile_hx(request, content);
    LORELINE_END_CALL
}

/* -- Haxe callback closures (using hxcpp local func macros) -------------- */

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

    // Retain the host's userData before queueing so the queued lambda can't
    // fire into a freed interpreter. This retainer is taken while the inflight
    // retainer (armed when the host resumed playback) still guarantees
    // userData is alive.
    Loreline_Retainer *r = h->retain ? h->retain(h->userData) : nullptr;

    LORELINE_BEGIN_DISPATCH_OUT
    s_dispatchInterp = h;
    // Delivery reached the host thread: disarm the inflight retainer. `r`
    // keeps userData alive through the handler, and the handler hands out
    // its own references (advance callable) before returning. Disarming
    // before the handler also lets a handler that re-enters synchronously
    // (advance/resolve from inside the callback) re-arm a fresh inflight.
    linc_releaseInflight(h);
    try {
        if (h->dialogueHandler) {
            h->dialogueHandler(h, character, text, tags, tagCount, linc_advance, h->userData);
        }
    } catch (...) {
        delete[] tags;
        if (h->release) h->release(r);
        throw;
    }
    delete[] tags;
    if (h->release) h->release(r);
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

    Loreline_Retainer *r = h->retain ? h->retain(h->userData) : nullptr;

    LORELINE_BEGIN_DISPATCH_OUT
    s_dispatchInterp = h;
    // Delivery reached the host thread: disarm the inflight retainer (see
    // dialogue dispatch above). `r` covers the handler.
    linc_releaseInflight(h);
    try {
        if (h->choiceHandler) {
            h->choiceHandler(h, options, optionCount, linc_select, h->userData);
        }
    } catch (...) {
        linc_freeChoiceOptions(options, optionCount);
        if (h->release) h->release(r);
        throw;
    }
    linc_freeChoiceOptions(options, optionCount);
    if (h->release) h->release(r);
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC3((void))

/* Finish handler: 1 capture (Loreline_Interpreter*), 1 Haxe arg */
HX_BEGIN_LOCAL_FUNC_S1(::hx::LocalFunc, _hx_Closure_finish,
    Loreline_Interpreter*, h) HXARGC(1)
void _hx_run(::Dynamic hxInterp) {
    linc_ensureInterpHandle(h, hxInterp);

    Loreline_Retainer *r = h->retain ? h->retain(h->userData) : nullptr;

    LORELINE_BEGIN_DISPATCH_OUT
    // Final delivery: disarm the inflight retainer so an interpreter the
    // host no longer references is freed naturally after this callback.
    linc_releaseInflight(h);
    try {
        if (h->finishHandler) {
            h->finishHandler(h, h->userData);
        }
    } catch (...) {
        if (h->release) h->release(r);
        throw;
    }
    if (h->release) h->release(r);
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC1((void))

/* File handler: 2 captures (Loreline_FileHandler, void*), 2 Haxe args.
 * Allocates a per-call Loreline_FileRequest that GC-roots the Haxe callback,
 * hands the token to the host. Host MUST eventually call Loreline_provideFile
 * (sync or async). That consumes the token and unroots/invokes the callback. */
HX_BEGIN_LOCAL_FUNC_S2(::hx::LocalFunc, _hx_Closure_fileHandler,
    Loreline_FileHandler, fh, void*, fhData) HXARGC(2)
void _hx_run(::Dynamic hxPath, ::Dynamic hxCallback) {
    Loreline_FileRequest* req = new Loreline_FileRequest();
    req->setCallback(hxCallback.GetPtr());
    fh(linc_hxToString((::String)hxPath), req, fhData);
    /* return immediately, req is now owned by the host until provideFile consumes it */
}
HX_END_LOCAL_FUNC2((void))

/* -- Custom function closures -------------------------------------------- */

/* Sync custom function: dispatches to host thread (blocks in threaded mode).
 * Invoked via Reflect.makeVarArgs wrapper, so hxArgs is an Array<Any> of all
 * positional script arguments. */
HX_BEGIN_LOCAL_FUNC_S3(::hx::LocalFunc, _hx_Closure_customFunction,
    Loreline_CustomFunction, fn, void*, fnUserData,
    Loreline_Interpreter*, h) HXARGC(1)
::Dynamic _hx_run(::Dynamic hxArgs) {
    ::cpp::VirtualArray arr = (::cpp::VirtualArray)hxArgs;
    int argCount = arr.mPtr ? arr->get_length() : 0;
    std::vector<Loreline_Value> cArgs(argCount);
    for (int i = 0; i < argCount; i++) {
        cArgs[i] = linc_hxToValue(arr->__get(i));
    }

    Loreline_Value result;
    linc_Loreline_dispatchOutSync([&]() {
        result = fn(h, cArgs.data(), argCount, fnUserData);
    });

    return linc_valueToHx(result);
}
HX_END_LOCAL_FUNC1(return)

/* Async custom function body: receives done callback, dispatches to host.
 * Interpreter-level retain/release (set on `h` at Loreline_play time) keeps
 * userData-dependent host objects alive across the queue-to-flush gap. */
HX_BEGIN_LOCAL_FUNC_S4(::hx::LocalFunc, _hx_Closure_asyncFuncBody,
    Loreline_AsyncCustomFunction, fn, void*, fnUserData,
    Loreline_Interpreter*, h,
    std::shared_ptr<std::vector<Loreline_Value> >, capturedArgs) HXARGC(1)
void _hx_run(::Dynamic hxDone) {
    auto resolve = new Loreline_AsyncResolve();
    resolve->setDone(hxDone.GetPtr());
    resolve->interp = h;

    auto args = capturedArgs;
    auto cFn = fn;
    auto cUserData = fnUserData;
    auto cH = h;
    auto cRetain = h->retain;
    auto cRelease = h->release;
    void *cInterpUserData = h->userData;

    Loreline_Retainer *retainer = cRetain ? cRetain(cInterpUserData) : nullptr;

    LORELINE_BEGIN_DISPATCH_OUT
    // Delivery of the function call to the host: disarm the inflight
    // retainer. From here the host owns the resolve token; resolving it
    // re-arms the inflight retainer, dropping it releases the interpreter.
    linc_releaseInflight(cH);
    try {
        cFn(cH, args->data(), (int)args->size(), resolve, cUserData);
    } catch (...) {
        if (cRelease) cRelease(retainer);
        throw;
    }
    if (cRelease) cRelease(retainer);
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC1((void))

/* Async custom function: returns loreline.Async to pause interpreter.
 * Invoked via Reflect.makeVarArgs wrapper, so hxArgs is an Array<Any> of all
 * positional script arguments. */
HX_BEGIN_LOCAL_FUNC_S3(::hx::LocalFunc, _hx_Closure_asyncCustomFunction,
    Loreline_AsyncCustomFunction, fn, void*, fnUserData,
    Loreline_Interpreter*, h) HXARGC(1)
::Dynamic _hx_run(::Dynamic hxArgs) {
    ::cpp::VirtualArray arr = (::cpp::VirtualArray)hxArgs;
    int argCount = arr.mPtr ? arr->get_length() : 0;
    auto cArgs = std::make_shared<std::vector<Loreline_Value> >(argCount);
    for (int i = 0; i < argCount; i++) {
        (*cArgs)[i] = linc_hxToValue(arr->__get(i));
    }

    ::Dynamic asyncFunc = ::Dynamic(
        new _hx_Closure_asyncFuncBody(fn, fnUserData, h, cArgs));
    return ::loreline::Async_obj::__new(asyncFunc);
}
HX_END_LOCAL_FUNC1(return)

/* -- Parse ---------------------------------------------------------------- */

/* Parse completion closure: 2 captures (C completion fn, userData), 1 Haxe arg
 * (the resulting Script, may be null on parse failure). Wraps into Loreline_Script*
 * and dispatches the C completion via DISPATCH_OUT (host's update tick). */
HX_BEGIN_LOCAL_FUNC_S2(::hx::LocalFunc, _hx_Closure_parseCompletion,
    Loreline_ParseCompletionCallback, completion, void*, completionData) HXARGC(1)
void _hx_run(::Dynamic hxScript) {
    Loreline_Script* script = nullptr;
    if (!hx::IsNull(hxScript)) {
        script = new Loreline_Script();
        script->set(hxScript.GetPtr());
    }
    LORELINE_BEGIN_DISPATCH_OUT
    if (completion) {
        completion(script, completionData);
    } else if (script) {
        /* No callback to take ownership, release to avoid leak */
        delete script;
    }
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC1((void))

static LORELINE_NOINLINE void Loreline_parseAsync_hx(
    Loreline_String input, Loreline_String filePath,
    Loreline_FileHandler fileHandler, void* fileHandlerData,
    Loreline_ParseCompletionCallback completionHandler, void* completionHandlerData
) {
    LORELINE_HX_BEGIN

    ::String hxInput = linc_toHxString(input);
    ::String hxFilePath = linc_toHxString(filePath);

    ::Dynamic hxFileHandler = null();
    if (fileHandler && !filePath.isNull()) {
        hxFileHandler = ::Dynamic(new _hx_Closure_fileHandler(fileHandler, fileHandlerData));
    }

    ::Dynamic hxCompletion = ::Dynamic(new _hx_Closure_parseCompletion(
        completionHandler, completionHandlerData));

    try {
        ::loreline::Loreline_obj::parse(hxInput, hxFilePath, hxFileHandler, hxCompletion);
        /* Result delivered via hxCompletion, sync (fires inline) or async (fires later) */
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_parseAsync error: %s\n", ((::String)e).c_str());
        /* Best-effort: notify completion with null on error */
        if (completionHandler) {
            LORELINE_BEGIN_DISPATCH_OUT
            completionHandler(nullptr, completionHandlerData);
            LORELINE_END_DISPATCH_OUT
        }
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_parseAsync(
    Loreline_String input,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData,
    Loreline_ParseCompletionCallback completionHandler,
    void* completionHandlerData
) {
    LORELINE_BEGIN_CALL
    Loreline_parseAsync_hx(input, filePath, fileHandler, fileHandlerData,
                           completionHandler, completionHandlerData);
    LORELINE_END_CALL
}

/* Sync wrapper: condvar-backed wait around Loreline_parseAsync. */
struct Loreline_ParseSyncSlot {
    std::mutex mtx;
    std::condition_variable cv;
    Loreline_Script* result = nullptr;
    bool done = false;
};

static void Loreline_parseSync_completion(Loreline_Script* script, void* userData) {
    auto* slot = static_cast<Loreline_ParseSyncSlot*>(userData);
    std::lock_guard<std::mutex> lock(slot->mtx);
    slot->result = script;
    slot->done = true;
    slot->cv.notify_one();
}

LORELINE_PUBLIC Loreline_Script* Loreline_parse(
    Loreline_String input,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData
) {
    Loreline_ParseSyncSlot slot;
    Loreline_parseAsync(input, filePath, fileHandler, fileHandlerData,
                        Loreline_parseSync_completion, &slot);
    std::unique_lock<std::mutex> lock(slot.mtx);
    slot.cv.wait(lock, [&]() { return slot.done; });
    return slot.result;
}

/* -- Translations --------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_extractTranslations_hx(
    Loreline_Script* script, Loreline_Translations** outHandle
) {
    LORELINE_HX_BEGIN

    ::haxe::ds::StringMap hxTranslations =
        ::loreline::Loreline_obj::extractTranslations((::loreline::Script)::Dynamic(script->obj));

    if (!hx::IsNull(hxTranslations)) {
        *outHandle = new Loreline_Translations();
        (*outHandle)->set(hxTranslations.GetPtr());
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Translations* Loreline_extractTranslations(Loreline_Script* script) {
    if (!script) return nullptr;
    Loreline_Translations* handle = nullptr;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_extractTranslations_hx(script, &handle);
    LORELINE_END_CALL

    return handle;
}

static LORELINE_NOINLINE void Loreline_releaseTranslations_hx(Loreline_Translations* translations) {
    LORELINE_HX_BEGIN
    delete translations;
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_releaseTranslations(Loreline_Translations* translations) {
    if (!translations) return;
    LORELINE_BEGIN_CALL
    Loreline_releaseTranslations_hx(translations);
    LORELINE_END_CALL
}

/* LoadLocale completion closure: 2 captures (C completion fn, userData), 1 Haxe arg
 * (the resulting StringMap, may be null). Wraps into Loreline_Translations* and
 * dispatches the C completion via DISPATCH_OUT. */
HX_BEGIN_LOCAL_FUNC_S2(::hx::LocalFunc, _hx_Closure_loadLocaleCompletion,
    Loreline_LoadLocaleCallback, completion, void*, completionData) HXARGC(1)
void _hx_run(::Dynamic hxTranslations) {
    Loreline_Translations* translations = nullptr;
    if (!hx::IsNull(hxTranslations)) {
        translations = new Loreline_Translations();
        translations->set(hxTranslations.GetPtr());
    }
    LORELINE_BEGIN_DISPATCH_OUT
    if (completion) {
        completion(translations, completionData);
    } else if (translations) {
        delete translations;
    }
    LORELINE_END_DISPATCH_OUT
}
HX_END_LOCAL_FUNC1((void))

static LORELINE_NOINLINE void Loreline_loadLocaleAsync_hx(
    Loreline_String locale, Loreline_Script* script,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler, void* fileHandlerData,
    Loreline_LoadLocaleCallback completionHandler, void* completionHandlerData
) {
    LORELINE_HX_BEGIN

    ::String hxLocale = linc_toHxString(locale);
    ::String hxFilePath = linc_toHxString(filePath);

    ::Dynamic hxFileHandler = null();
    if (fileHandler) {
        hxFileHandler = ::Dynamic(new _hx_Closure_fileHandler(fileHandler, fileHandlerData));
    }

    ::Dynamic hxCompletion = ::Dynamic(new _hx_Closure_loadLocaleCompletion(
        completionHandler, completionHandlerData));

    try {
        ::loreline::Loreline_obj::loadLocale(
            hxLocale,
            (::loreline::Script)::Dynamic(script->obj),
            hxFilePath,
            hxFileHandler,
            hxCompletion
        );
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_loadLocaleAsync error: %s\n", ((::String)e).c_str());
        if (completionHandler) {
            LORELINE_BEGIN_DISPATCH_OUT
            completionHandler(nullptr, completionHandlerData);
            LORELINE_END_DISPATCH_OUT
        }
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_loadLocaleAsync(
    Loreline_String locale,
    Loreline_Script* script,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData,
    Loreline_LoadLocaleCallback completionHandler,
    void* completionHandlerData
) {
    if (!script) {
        if (completionHandler) completionHandler(nullptr, completionHandlerData);
        return;
    }
    LORELINE_BEGIN_CALL
    Loreline_loadLocaleAsync_hx(locale, script, filePath, fileHandler, fileHandlerData,
                                completionHandler, completionHandlerData);
    LORELINE_END_CALL
}

/* Sync wrapper: condvar-backed wait around Loreline_loadLocaleAsync. */
struct Loreline_LoadLocaleSyncSlot {
    std::mutex mtx;
    std::condition_variable cv;
    Loreline_Translations* result = nullptr;
    bool done = false;
};

static void Loreline_loadLocaleSync_completion(Loreline_Translations* translations, void* userData) {
    auto* slot = static_cast<Loreline_LoadLocaleSyncSlot*>(userData);
    std::lock_guard<std::mutex> lock(slot->mtx);
    slot->result = translations;
    slot->done = true;
    slot->cv.notify_one();
}

LORELINE_PUBLIC Loreline_Translations* Loreline_loadLocale(
    Loreline_String locale,
    Loreline_Script* script,
    Loreline_String filePath,
    Loreline_FileHandler fileHandler,
    void* fileHandlerData
) {
    if (!script) return nullptr;
    Loreline_LoadLocaleSyncSlot slot;
    Loreline_loadLocaleAsync(locale, script, filePath, fileHandler, fileHandlerData,
                             Loreline_loadLocaleSync_completion, &slot);
    std::unique_lock<std::mutex> lock(slot.mtx);
    slot.cv.wait(lock, [&]() { return slot.done; });
    return slot.result;
}

/* -- Translation formats -------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_translationFormat_hx(
    Loreline_String name,
    bool enabled
) {
    LORELINE_HX_BEGIN
    ::String hxName = linc_toHxString(name);
    ::loreline::Loreline_obj::translationFormat(hxName, enabled);
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_translationFormat(
    Loreline_String name,
    bool enabled
) {
    LORELINE_BEGIN_CALL
    Loreline_translationFormat_hx(name, enabled);
    LORELINE_END_CALL
}

/* -- Last error ----------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_lastError_hx(Loreline_String* out) {
    LORELINE_HX_BEGIN
    ::loreline::Error err = ::loreline::Loreline_obj::lastError();
    if (err != null() && err->message != null()) {
        *out = linc_hxToString(err->message);
    }
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_String Loreline_lastError(void) {
    Loreline_String out;
    LORELINE_BEGIN_CALL_SYNC
    Loreline_lastError_hx(&out);
    LORELINE_END_CALL
    return out;
}

/* -- Play ----------------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_play_hx(
    Loreline_Interpreter* h, ::Dynamic hxScript,
    Loreline_String beatName, Loreline_InterpreterOptions* opts
) {
    LORELINE_HX_BEGIN

    ::String hxBeatName = linc_toHxString(beatName);
    ::Dynamic hxDialogueHandler = ::Dynamic(new _hx_Closure_dialogue(h));
    ::Dynamic hxChoiceHandler = ::Dynamic(new _hx_Closure_choice(h));
    ::Dynamic hxFinishHandler = ::Dynamic(new _hx_Closure_finish(h));

    ::Dynamic hxOptions = null();
    if (opts) {
        /* Build Haxe functions StringMap from C entries */
        ::Dynamic hxFunctions = null();
        if (!opts->functions.empty()) {
            ::haxe::ds::StringMap map = ::haxe::ds::StringMap_obj::__new();
            for (size_t i = 0; i < opts->functions.size(); i++) {
                const auto& entry = opts->functions[i];
                ::Dynamic hxFunc;
                if (entry.syncFn) {
                    hxFunc = ::Dynamic(
                        new _hx_Closure_customFunction(
                            entry.syncFn, entry.userData, h));
                } else {
                    hxFunc = ::Dynamic(
                        new _hx_Closure_asyncCustomFunction(
                            entry.asyncFn, entry.userData, h));
                }
                // Wrap with Reflect.makeVarArgs so the Interpreter can invoke
                // via positional Reflect.callMethod; our closures expect a single
                // Array<Any> argument containing all script-level positional args.
                hxFunc = ::Reflect_obj::makeVarArgs(hxFunc);
                map->set(::String(entry.name.c_str()), hxFunc);
            }
            hxFunctions = map;
        }

        ::Dynamic hxTranslations = opts->translationsObj
            ? ::Dynamic(opts->translationsObj) : null();

        /* customCreateFields is not meaningfully bridgeable through the C API
         * since it returns Haxe-internal field objects. Passing null causes
         * the interpreter to use its default field creation, which is correct. */

        hxOptions = ::loreline::InterpreterOptions_obj::__new(
            hxFunctions,
            opts->strictAccess,
            null(), /* customCreateFields, not exposed through C API */
            hxTranslations,
            null()  /* stringLiteralProcessors, not exposed */
        );
    }

    try {
        ::Dynamic hxInterp = ::loreline::Loreline_obj::play(
            hxScript, hxDialogueHandler, hxChoiceHandler, hxFinishHandler, hxBeatName, hxOptions
        );
        h->set(hxInterp.GetPtr());
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_play error: %s\n", ((::String)e).c_str());
        /* The run aborted: no delivery will come to disarm the inflight
         * retainer, so release it from the host thread. */
        linc_Loreline_dispatchOut([h]() { linc_releaseInflight(h); });
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Interpreter* Loreline_play(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    Loreline_String beatName,
    Loreline_InterpreterOptions* options,
    void* userData,
    Loreline_UserDataRetain retain,
    Loreline_UserDataRelease release
) {
    if (!script) return nullptr;

    Loreline_Interpreter* handle = new Loreline_Interpreter();
    handle->dialogueHandler = onDialogue;
    handle->choiceHandler = onChoice;
    handle->finishHandler = onFinish;
    handle->userData = userData;
    handle->retain = retain;
    handle->release = release;

    Loreline_Interpreter* h = handle;
    ::Dynamic hxScript = ::Dynamic(script->obj);

    /* Playback starts running toward the first callback: keep userData alive
     * until that delivery, even if the host drops its references before it. */
    linc_retainInflight(handle);

    LORELINE_BEGIN_CALL
    Loreline_play_hx(h, hxScript, beatName, options);
    LORELINE_END_CALL

    return handle;
}

/* -- Resume --------------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_resume_hx(
    Loreline_Interpreter* h, ::Dynamic hxScript,
    Loreline_String saveData, Loreline_String beatName,
    Loreline_InterpreterOptions* opts
) {
    LORELINE_HX_BEGIN

    ::String hxBeatName = linc_toHxString(beatName);
    ::String hxSaveStr = linc_toHxString(saveData);
    ::Dynamic hxSaveData = ::loreline::Json_obj::parse(hxSaveStr);

    ::Dynamic hxDialogueHandler = ::Dynamic(new _hx_Closure_dialogue(h));
    ::Dynamic hxChoiceHandler = ::Dynamic(new _hx_Closure_choice(h));
    ::Dynamic hxFinishHandler = ::Dynamic(new _hx_Closure_finish(h));

    ::Dynamic hxOptions = null();
    if (opts) {
        ::Dynamic hxFunctions = null();
        if (!opts->functions.empty()) {
            ::haxe::ds::StringMap map = ::haxe::ds::StringMap_obj::__new();
            for (size_t i = 0; i < opts->functions.size(); i++) {
                const auto& entry = opts->functions[i];
                ::Dynamic hxFunc;
                if (entry.syncFn) {
                    hxFunc = ::Dynamic(
                        new _hx_Closure_customFunction(
                            entry.syncFn, entry.userData, h));
                } else {
                    hxFunc = ::Dynamic(
                        new _hx_Closure_asyncCustomFunction(
                            entry.asyncFn, entry.userData, h));
                }
                // Wrap with Reflect.makeVarArgs so the Interpreter can invoke
                // via positional Reflect.callMethod; our closures expect a single
                // Array<Any> argument containing all script-level positional args.
                hxFunc = ::Reflect_obj::makeVarArgs(hxFunc);
                map->set(::String(entry.name.c_str()), hxFunc);
            }
            hxFunctions = map;
        }

        ::Dynamic hxTranslations = opts->translationsObj
            ? ::Dynamic(opts->translationsObj) : null();

        hxOptions = ::loreline::InterpreterOptions_obj::__new(
            hxFunctions,
            opts->strictAccess,
            null(),
            hxTranslations,
            null()
        );
    }

    try {
        ::Dynamic hxInterp = ::loreline::Loreline_obj::resume(
            hxScript, hxDialogueHandler, hxChoiceHandler, hxFinishHandler,
            hxSaveData, hxBeatName, hxOptions
        );
        h->set(hxInterp.GetPtr());
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_resume error: %s\n", ((::String)e).c_str());
        /* The run aborted: no delivery will come to disarm the inflight
         * retainer, so release it from the host thread. */
        linc_Loreline_dispatchOut([h]() { linc_releaseInflight(h); });
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Interpreter* Loreline_resume(
    Loreline_Script* script,
    Loreline_DialogueHandler onDialogue,
    Loreline_ChoiceHandler onChoice,
    Loreline_FinishHandler onFinish,
    Loreline_String saveData,
    Loreline_String beatName,
    Loreline_InterpreterOptions* options,
    void* userData,
    Loreline_UserDataRetain retain,
    Loreline_UserDataRelease release
) {
    if (!script || saveData.isNull()) return nullptr;

    Loreline_Interpreter* handle = new Loreline_Interpreter();
    handle->dialogueHandler = onDialogue;
    handle->choiceHandler = onChoice;
    handle->finishHandler = onFinish;
    handle->userData = userData;
    handle->retain = retain;
    handle->release = release;

    Loreline_Interpreter* h = handle;
    ::Dynamic hxScript = ::Dynamic(script->obj);

    /* Playback starts running toward the first callback: keep userData alive
     * until that delivery, even if the host drops its references before it. */
    linc_retainInflight(handle);

    LORELINE_BEGIN_CALL
    Loreline_resume_hx(h, hxScript, saveData, beatName, options);
    LORELINE_END_CALL

    return handle;
}

/* -- Interpreter methods -------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_start_hx(Loreline_Interpreter* interp, Loreline_String beatName) {
    LORELINE_HX_BEGIN
    ::String hxBeatName = linc_toHxString(beatName);
    try {
        ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
        hxInterp->start(hxBeatName);
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_start error: %s\n", ((::String)e).c_str());
        /* The run aborted: no delivery will come to disarm the inflight
         * retainer, so release it from the host thread. */
        Loreline_Interpreter* h = interp;
        linc_Loreline_dispatchOut([h]() { linc_releaseInflight(h); });
    }
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_start(Loreline_Interpreter* interp, Loreline_String beatName) {
    if (!interp) return;

    /* The host hands control back: keep userData alive until the next
     * callback delivery, even if the host drops its references now. */
    linc_retainInflight(interp);

    LORELINE_BEGIN_CALL
    Loreline_start_hx(interp, beatName);
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void Loreline_save_hx(Loreline_Interpreter* interp, Loreline_String* outResult) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic saveData = hxInterp->save();
    ::String json = ::loreline::Json_obj::stringify(saveData, false);
    *outResult = linc_hxToString(json);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_String Loreline_save(Loreline_Interpreter* interp) {
    if (!interp) return Loreline_String();
    Loreline_String result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_save_hx(interp, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_restore_hx(Loreline_Interpreter* interp, Loreline_String saveData) {
    LORELINE_HX_BEGIN
    ::String hxSaveStr = linc_toHxString(saveData);
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxSaveData = ::loreline::Json_obj::parse(hxSaveStr);
    hxInterp->restore(hxSaveData);
    hxInterp->resume();
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_restore(Loreline_Interpreter* interp, Loreline_String saveData) {
    if (!interp || saveData.isNull()) return;

    LORELINE_BEGIN_CALL
    Loreline_restore_hx(interp, saveData);
    LORELINE_END_CALL
}

/* -- Character access ----------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_getCharacterField_hx(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field,
    Loreline_Value* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic val = hxInterp->getCharacterField(linc_toHxString(character), linc_toHxString(field));
    *outResult = linc_hxToValue(val);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Value Loreline_getCharacterField(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field
) {
    if (!interp || character.isNull() || field.isNull()) return Loreline_Value::null_val();
    Loreline_Value result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_getCharacterField_hx(interp, character, field, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_setCharacterField_hx(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field, Loreline_Value value
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxVal = linc_valueToHx(value);
    hxInterp->setCharacterField(linc_toHxString(character), linc_toHxString(field), hxVal);
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_setCharacterField(
    Loreline_Interpreter* interp, Loreline_String character, Loreline_String field, Loreline_Value value
) {
    if (!interp || character.isNull() || field.isNull()) return;

    LORELINE_BEGIN_CALL
    Loreline_setCharacterField_hx(interp, character, field, value);
    LORELINE_END_CALL
}

/* -- State field access --------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_getStateField_hx(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic val = hxInterp->getStateField(linc_toHxString(field));
    *outResult = linc_hxToValue(val);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Value Loreline_getStateField(
    Loreline_Interpreter* interp, Loreline_String field
) {
    if (!interp || field.isNull()) return Loreline_Value::null_val();
    Loreline_Value result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_getStateField_hx(interp, field, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_setStateField_hx(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxVal = linc_valueToHx(value);
    hxInterp->setStateField(linc_toHxString(field), hxVal);
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_setStateField(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value
) {
    if (!interp || field.isNull()) return;

    LORELINE_BEGIN_CALL
    Loreline_setStateField_hx(interp, field, value);
    LORELINE_END_CALL
}

/* -- Top-level state field access ---------------------------------------- */

static LORELINE_NOINLINE void Loreline_getTopLevelStateField_hx(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic val = hxInterp->getTopLevelStateField(linc_toHxString(field));
    *outResult = linc_hxToValue(val);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Value Loreline_getTopLevelStateField(
    Loreline_Interpreter* interp, Loreline_String field
) {
    if (!interp || field.isNull()) return Loreline_Value::null_val();
    Loreline_Value result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_getTopLevelStateField_hx(interp, field, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_setTopLevelStateField_hx(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic hxVal = linc_valueToHx(value);
    hxInterp->setTopLevelStateField(linc_toHxString(field), hxVal);
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_setTopLevelStateField(
    Loreline_Interpreter* interp, Loreline_String field, Loreline_Value value
) {
    if (!interp || field.isNull()) return;

    LORELINE_BEGIN_CALL
    Loreline_setTopLevelStateField_hx(interp, field, value);
    LORELINE_END_CALL
}

/* -- Current node -------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_currentNode_hx(
    Loreline_Interpreter* interp, Loreline_Node* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Interpreter hxInterp = (::loreline::Interpreter)::Dynamic(interp->obj);
    ::Dynamic node = hxInterp->currentNode();
    if (!hx::IsNull(node)) {
        ::Dynamic hxType = node->__Field(HX_CSTRING("type"), hx::paccDynamic);
        if (!hx::IsNull(hxType)) {
            outResult->type = linc_hxToString((::String)hxType->__run());
        }
        ::Dynamic pos = node->__Field(HX_CSTRING("pos"), hx::paccDynamic);
        if (!hx::IsNull(pos)) {
            outResult->line = (int)pos->__Field(HX_CSTRING("line"), hx::paccDynamic);
            outResult->column = (int)pos->__Field(HX_CSTRING("column"), hx::paccDynamic);
            outResult->offset = (int)pos->__Field(HX_CSTRING("offset"), hx::paccDynamic);
            outResult->length = (int)pos->__Field(HX_CSTRING("length"), hx::paccDynamic);
        }
    }
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Node Loreline_currentNode(Loreline_Interpreter* interp) {
    Loreline_Node result;
    result.type = Loreline_String();
    result.line = 0;
    result.column = 0;
    result.offset = 0;
    result.length = 0;

    if (!interp) return result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_currentNode_hx(interp, &result);
    LORELINE_END_CALL

    return result;
}

/* -- Utility -------------------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_printScript_hx(
    Loreline_Script* script, Loreline_String* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Script hxScript = (::loreline::Script)::Dynamic(script->obj);
    ::String printed = ::loreline::Loreline_obj::print(hxScript, null(), null());
    *outResult = linc_hxToString(printed);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_String Loreline_printScript(Loreline_Script* script) {
    if (!script) return Loreline_String();
    Loreline_String result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_printScript_hx(script, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_scriptToJson_hx(
    Loreline_Script* script, bool pretty, Loreline_String* outResult
) {
    LORELINE_HX_BEGIN
    ::loreline::Script hxScript = (::loreline::Script)::Dynamic(script->obj);
    ::Dynamic jsonObj = hxScript->toJson();
    ::String jsonStr = ::loreline::Json_obj::stringify(jsonObj, pretty);
    *outResult = linc_hxToString(jsonStr);
    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_String Loreline_scriptToJson(Loreline_Script* script, bool pretty) {
    if (!script) return Loreline_String();
    Loreline_String result;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_scriptToJson_hx(script, pretty, &result);
    LORELINE_END_CALL

    return result;
}

static LORELINE_NOINLINE void Loreline_scriptFromJson_hx(
    Loreline_String json, Loreline_Script** outHandle
) {
    LORELINE_HX_BEGIN

    try {
        ::String hxJson = linc_toHxString(json);
        ::Dynamic jsonObj = ::loreline::Json_obj::parse(hxJson);
        ::Dynamic hxScript = ::loreline::Script_obj::fromJson(jsonObj);

        if (!hx::IsNull(hxScript)) {
            *outHandle = new Loreline_Script();
            (*outHandle)->set(hxScript.GetPtr());
        }
    } catch (::Dynamic e) {
        fprintf(stderr, "Loreline_scriptFromJson error: %s\n", ((::String)e).c_str());
    }

    LORELINE_HX_END
}

LORELINE_PUBLIC Loreline_Script* Loreline_scriptFromJson(Loreline_String json) {
    if (json.isNull()) return nullptr;
    Loreline_Script* handle = nullptr;

    LORELINE_BEGIN_CALL_SYNC
    Loreline_scriptFromJson_hx(json, &handle);
    LORELINE_END_CALL

    return handle;
}

/* -- Interpreter options -------------------------------------------------- */

LORELINE_PUBLIC Loreline_InterpreterOptions* Loreline_createOptions(void) {
    return new Loreline_InterpreterOptions();
}

static LORELINE_NOINLINE void Loreline_releaseOptions_hx(Loreline_InterpreterOptions* options) {
    LORELINE_HX_BEGIN
    delete options;
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_releaseOptions(Loreline_InterpreterOptions* options) {
    if (!options) return;
    LORELINE_BEGIN_CALL
    Loreline_releaseOptions_hx(options);
    LORELINE_END_CALL
}

LORELINE_PUBLIC void Loreline_optionsSetStrictAccess(
    Loreline_InterpreterOptions* options, bool strict
) {
    if (options) options->strictAccess = strict;
}

LORELINE_PUBLIC void Loreline_optionsSetTranslations(
    Loreline_InterpreterOptions* options, Loreline_Translations* translations
) {
    if (options) options->setTranslations(translations ? translations->obj : nullptr);
}

LORELINE_PUBLIC void Loreline_optionsAddFunction(
    Loreline_InterpreterOptions* options, Loreline_String name,
    Loreline_CustomFunction fn, void* userData
) {
    if (options && fn && !name.isNull()) {
        Loreline_InterpreterOptions::FunctionEntry entry;
        entry.name = std::string(name.c_str());
        entry.syncFn = fn;
        entry.asyncFn = nullptr;
        entry.userData = userData;
        options->functions.push_back(entry);
    }
}

LORELINE_PUBLIC void Loreline_optionsAddAsyncFunction(
    Loreline_InterpreterOptions* options, Loreline_String name,
    Loreline_AsyncCustomFunction fn, void* userData
) {
    if (options && fn && !name.isNull()) {
        Loreline_InterpreterOptions::FunctionEntry entry;
        entry.name = std::string(name.c_str());
        entry.syncFn = nullptr;
        entry.asyncFn = fn;
        entry.userData = userData;
        options->functions.push_back(entry);
    }
}

LORELINE_PUBLIC void Loreline_resolveAsync(
    Loreline_AsyncResolve* resolve, Loreline_Value result
) {
    if (!resolve || !resolve->doneObj) return;
    // Keep the doneObj pointer accessible after we run it, but DO NOT clear
    // resolve->doneObj here, the ~Loreline_AsyncResolve destructor uses that
    // field to decide whether to call hx::GCRemoveRoot on the registered
    // root address `&resolve->doneObj`. Removing the registration on a local
    // copy of the pointer (different address) leaks the real root and the
    // GC then walks freed memory on the next collect.
    hx::Object* doneObj = resolve->doneObj;

    /* The host hands control back through this token: keep the interpreter's
     * userData alive until the next callback delivery, even if the host
     * drops the token and all other references now. */
    linc_retainInflight(resolve->interp);

    LORELINE_BEGIN_CALL
    LORELINE_HX_BEGIN
    ::Dynamic(doneObj)->__run();
    LORELINE_HX_END
    LORELINE_END_CALL

    delete resolve;
}

LORELINE_PUBLIC void Loreline_cancelAsync(
    Loreline_AsyncResolve* resolve
) {
    if (!resolve) return;
    if (!resolve->doneObj) {
        delete resolve;
        return;
    }

    // Release the GC root on the done closure without invoking it. The Haxe
    // side's Async state stays paused until the interpreter itself is
    // released, at which point the closure becomes collectible.
    // ~Loreline_AsyncResolve removes the root on the correct address
    // (`&resolve->doneObj`); don't clear the field early or call GCRemoveRoot
    // on a local copy here, that would leak the real registration.
    delete resolve;
}

/* -- Resource release ----------------------------------------------------- */

static LORELINE_NOINLINE void Loreline_releaseScript_hx(Loreline_Script* script) {
    LORELINE_HX_BEGIN
    delete script;
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_releaseScript(Loreline_Script* script) {
    if (!script) return;
    LORELINE_BEGIN_CALL
    Loreline_releaseScript_hx(script);
    LORELINE_END_CALL
}

static LORELINE_NOINLINE void Loreline_releaseInterpreter_hx(Loreline_Interpreter* interp) {
    LORELINE_HX_BEGIN
    delete interp;
    LORELINE_HX_END
}

LORELINE_PUBLIC void Loreline_releaseInterpreter(Loreline_Interpreter* interp) {
    if (!interp) return;
    /* Explicit release while a run may be in flight: disarm the inflight
     * retainer. No-op on the natural-destruction path, where the retainer is
     * necessarily already disarmed (it held a host reference). */
    linc_releaseInflight(interp);
    LORELINE_BEGIN_CALL
    Loreline_releaseInterpreter_hx(interp);
    LORELINE_END_CALL
}
