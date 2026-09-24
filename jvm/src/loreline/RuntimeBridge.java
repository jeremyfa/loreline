package loreline;

import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;

/**
 * Internal bridge for calling Haxe-generated runtime methods.
 * The Haxe JVM backend declares methods with "throws Object" which Java source
 * can't call directly. MethodHandles bypass this compiler constraint.
 */
final class RuntimeBridge {
    private static final MethodHandle START;
    private static final MethodHandle RESTORE;
    private static final MethodHandle PARSE;
    private static final MethodHandle LOAD_LOCALE;
    private static final MethodHandle SPAWN;
    private static final MethodHandle RESUME_SPAWN;
    private static final MethodHandle DISPOSE;

    static {
        try {
            MethodHandles.Lookup lookup = MethodHandles.lookup();

            START = lookup.findVirtual(
                loreline.runtime.Interpreter.class, "start",
                MethodType.methodType(void.class, String.class));

            RESTORE = lookup.findVirtual(
                loreline.runtime.Interpreter.class, "restore",
                MethodType.methodType(void.class, Object.class));

            PARSE = lookup.findStatic(
                loreline.runtime.Loreline.class, "parse",
                MethodType.methodType(loreline.runtime.Script.class,
                    String.class, String.class,
                    loreline.internal.jvm.Function.class,
                    loreline.internal.jvm.Function.class));

            LOAD_LOCALE = lookup.findStatic(
                loreline.runtime.Loreline.class, "loadLocale",
                MethodType.methodType(loreline.internal.ds.StringMap.class,
                    String.class, loreline.runtime.Script.class, String.class,
                    loreline.internal.jvm.Function.class,
                    loreline.internal.jvm.Function.class));

            MethodType spawnType = MethodType.methodType(loreline.runtime.Interpreter.class,
                String.class,
                loreline.internal.jvm.Function.class,
                loreline.internal.jvm.Function.class,
                loreline.internal.jvm.Function.class,
                Object.class);

            SPAWN = lookup.findVirtual(
                loreline.runtime.Interpreter.class, "spawn", spawnType);

            RESUME_SPAWN = lookup.findVirtual(
                loreline.runtime.Interpreter.class, "resumeSpawn", spawnType);

            DISPOSE = lookup.findVirtual(
                loreline.runtime.Interpreter.class, "dispose",
                MethodType.methodType(void.class));
        } catch (ReflectiveOperationException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    static loreline.runtime.Interpreter spawn(loreline.runtime.Interpreter parent, boolean resume, String key,
                                              loreline.internal.jvm.Function handleDialogue,
                                              loreline.internal.jvm.Function handleChoice,
                                              loreline.internal.jvm.Function handleFinish,
                                              loreline.runtime.InterpreterOptions options) {
        try {
            return (loreline.runtime.Interpreter) (resume ? RESUME_SPAWN : SPAWN).invoke(
                parent, key, handleDialogue, handleChoice, handleFinish, options);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    static void dispose(loreline.runtime.Interpreter interp) {
        try {
            DISPOSE.invoke(interp);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    static void start(loreline.runtime.Interpreter interp, String beatName) {
        try {
            START.invoke(interp, beatName);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    static void restore(loreline.runtime.Interpreter interp, Object saveData) {
        try {
            RESTORE.invoke(interp, saveData);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    static loreline.runtime.Script parse(String input, String filePath,
                                          loreline.internal.jvm.Function handleFile,
                                          loreline.internal.jvm.Function callback) {
        try {
            return (loreline.runtime.Script) PARSE.invoke(input, filePath, handleFile, callback);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    static Object loadLocale(String locale, loreline.runtime.Script script, String filePath,
                             loreline.internal.jvm.Function handleFile,
                             loreline.internal.jvm.Function callback) {
        try {
            return LOAD_LOCALE.invoke(locale, script, filePath, handleFile, callback);
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new RuntimeException(e);
        }
    }

    private RuntimeBridge() {}
}
