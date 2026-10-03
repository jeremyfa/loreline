package loreline;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Main interpreter class for Loreline scripts.
 * Wraps the Haxe-generated runtime interpreter with a Java-friendly API.
 */
public class Interpreter {
    private static final Object[] EMPTY_ARGS = new Object[0];
    private static final Object[] ARGS_1 = new Object[1];

    final loreline.runtime.Interpreter runtimeInterpreter;

    // Kept so that a spawned child can wrap the same handlers and functions,
    // bound to its own wrapper
    private final DialogueHandler handleDialogue;
    private final ChoiceHandler handleChoice;
    private final FinishHandler handleFinish;
    private final InterpreterOptions options;

    /**
     * Creates a new Loreline script interpreter.
     *
     * @param script the parsed script to execute
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     */
    public Interpreter(Script script, DialogueHandler handleDialogue,
                       ChoiceHandler handleChoice, FinishHandler handleFinish) {
        this(script, handleDialogue, handleChoice, handleFinish, null);
    }

    /**
     * Creates a new Loreline script interpreter with options.
     *
     * @param script the parsed script to execute
     * @param handleDialogue function to call when displaying dialogue text
     * @param handleChoice function to call when presenting choices
     * @param handleFinish function to call when execution finishes
     * @param options additional options
     */
    public Interpreter(Script script, DialogueHandler handleDialogue,
                       ChoiceHandler handleChoice, FinishHandler handleFinish,
                       InterpreterOptions options) {

        this.handleDialogue = handleDialogue;
        this.handleChoice = handleChoice;
        this.handleFinish = handleFinish;
        this.options = options;

        DialogueBridge dialogueBridge = new DialogueBridge(this, handleDialogue);
        ChoiceBridge choiceBridge = new ChoiceBridge(this, handleChoice);
        FinishBridge finishBridge = new FinishBridge(this, handleFinish);

        loreline.internal.ds.StringMap<Object> functionsMap = null;
        if (options != null && options.functions != null) {
            functionsMap = wrapFunctions(this, options.functions);
        }

        CreateFieldsBridge createFieldsBridge = null;
        if (options != null && options.customCreateFields != null) {
            createFieldsBridge = new CreateFieldsBridge(this, options.customCreateFields);
        }

        loreline.internal.ds.StringMap<Object> translationsMap = null;
        if (options != null && options.translations != null) {
            translationsMap = (loreline.internal.ds.StringMap<Object>) options.translations;
        }

        boolean strictAccess = options != null && options.strictAccess;
        boolean prepareCaches = options != null && options.prepareCaches;

        loreline.runtime.InterpreterOptions runtimeOptions =
            new loreline.runtime.InterpreterOptions(
                createFieldsBridge,   // customCreateFields
                functionsMap,         // functions
                prepareCaches,        // prepareCaches
                strictAccess,         // strictAccess
                null,                 // stringLiteralProcessors
                translationsMap,      // translations
                this                  // wrapper
            );

        this.runtimeInterpreter = new loreline.runtime.Interpreter(
            script.runtimeScript,
            dialogueBridge,
            choiceBridge,
            finishBridge,
            runtimeOptions,
            null
        );
    }

    /**
     * Creates the wrapper of a child interpreter, spawned from (or resumed through) a parent.
     * Handlers left null reuse the ones of the parent, wrapped again so that they receive the child.
     */
    private Interpreter(Interpreter parent, String key, DialogueHandler handleDialogue,
                        ChoiceHandler handleChoice, FinishHandler handleFinish, boolean resume) {

        this.handleDialogue = handleDialogue != null ? handleDialogue : parent.handleDialogue;
        this.handleChoice = handleChoice != null ? handleChoice : parent.handleChoice;
        this.handleFinish = handleFinish != null ? handleFinish : parent.handleFinish;
        this.options = parent.options;

        // Function adapters bound to this wrapper, so that host functions receive the child
        loreline.internal.ds.StringMap<Object> functionsMap = null;
        if (options != null && options.functions != null) {
            functionsMap = wrapFunctions(this, options.functions);
        }

        CreateFieldsBridge createFieldsBridge = null;
        if (options != null && options.customCreateFields != null) {
            createFieldsBridge = new CreateFieldsBridge(this, options.customCreateFields);
        }

        loreline.runtime.InterpreterOptions runtimeOptions =
            new loreline.runtime.InterpreterOptions(
                createFieldsBridge,
                functionsMap,
                false,
                options != null && options.strictAccess,
                null,
                null,
                this
            );

        this.runtimeInterpreter = RuntimeBridge.spawn(
            parent.runtimeInterpreter,
            resume,
            key,
            new DialogueBridge(this, this.handleDialogue),
            new ChoiceBridge(this, this.handleChoice),
            new FinishBridge(this, this.handleFinish),
            runtimeOptions
        );
    }

    /**
     * Key of this interpreter when it was spawned from another one.
     *
     * @return the key, or null for a root interpreter
     */
    public String getKey() {
        return runtimeInterpreter.key;
    }

    /**
     * Whether this interpreter is a root interpreter (not spawned from another one).
     *
     * @return true for a root interpreter
     */
    public boolean isRoot() {
        return runtimeInterpreter.isRoot();
    }

    /**
     * Spawns a child interpreter reusing the handlers of this interpreter.
     *
     * @param key identifies the child, notably to resume it after a restore
     * @return the child interpreter
     * @see #spawn(String, DialogueHandler, ChoiceHandler, FinishHandler)
     */
    public Interpreter spawn(String key) {
        return spawn(key, null, null, null);
    }

    /**
     * Spawns a child interpreter that shares everything with this one (script, state,
     * characters, functions) except the playhead. The child is not started: call start()
     * on it. Any live child using the same key is disposed first, and a restored flow still
     * pending for that key is discarded (use resumeSpawn() to continue it instead).
     * Calling save() on any interpreter of the family saves the shared state and every playhead.
     *
     * @param key identifies the child, notably to resume it after a restore
     * @param handleDialogue dialogue handler of the child, or null to reuse the one of this interpreter
     * @param handleChoice choice handler of the child, or null to reuse the one of this interpreter
     * @param handleFinish finish handler of the child, or null to reuse the one of this interpreter
     * @return the child interpreter
     */
    public Interpreter spawn(String key, DialogueHandler handleDialogue,
                             ChoiceHandler handleChoice, FinishHandler handleFinish) {
        return new Interpreter(this, key, handleDialogue, handleChoice, handleFinish, false);
    }

    /**
     * Rebuilds a child interpreter reusing the handlers of this interpreter.
     *
     * @param key the key the child had when it was saved
     * @return the restored child interpreter
     * @see #resumeSpawn(String, DialogueHandler, ChoiceHandler, FinishHandler)
     */
    public Interpreter resumeSpawn(String key) {
        return resumeSpawn(key, null, null, null);
    }

    /**
     * Rebuilds a child interpreter from the flow saved under the given key, after restore()
     * on the root interpreter (or Loreline.resume()). The child is not resumed yet: call
     * resume() on it.
     *
     * @param key the key the child had when it was saved (see resumableSpawnKeys())
     * @param handleDialogue dialogue handler of the child, or null to reuse the one of this interpreter
     * @param handleChoice choice handler of the child, or null to reuse the one of this interpreter
     * @param handleFinish finish handler of the child, or null to reuse the one of this interpreter
     * @return the restored child interpreter
     */
    public Interpreter resumeSpawn(String key, DialogueHandler handleDialogue,
                                   ChoiceHandler handleChoice, FinishHandler handleFinish) {
        return new Interpreter(this, key, handleDialogue, handleChoice, handleFinish, true);
    }

    /**
     * Keys of the saved children not resumed with resumeSpawn() (nor replaced with spawn()) yet.
     *
     * @return the pending keys
     */
    @SuppressWarnings("rawtypes")
    public List<String> resumableSpawnKeys() {
        loreline.internal.root.Array rawKeys = (loreline.internal.root.Array) runtimeInterpreter.resumableSpawnKeys();
        List<String> keys = new ArrayList<>(rawKeys.length);
        for (int i = 0; i < rawKeys.length; i++) {
            keys.add((String) rawKeys.__a[i]);
        }
        return keys;
    }

    /**
     * Reseeds the random generator shared by this interpreter, its root and every child,
     * with a seed taken from the clock. The generator is part of save data, so a restored
     * game draws the same random values as it would have without the save. Call this after
     * a restore to break that on purpose.
     */
    public void seedRandom() {
        runtimeInterpreter.seedRandom(null);
    }

    /**
     * Reseeds the random generator shared by this interpreter, its root and every child.
     * The same seed always gives the same sequence.
     *
     * @param seed the seed of the new sequence
     */
    public void seedRandom(double seed) {
        runtimeInterpreter.seedRandom(Double.valueOf(seed));
    }

    /**
     * Builds now what the interpreter would otherwise build the first time it needs it,
     * so that the cost is paid at a chosen moment, like a loading screen, rather than
     * during play: for now, what each {@code when} block needs to pick a rule, which takes
     * a moment on blocks of thousands of rules. Optional, it never changes what the script
     * plays, and a second call only builds what is missing. Interpreters spawned from this
     * one share these caches. See also {@link InterpreterOptions#prepareCaches}.
     */
    public void prepareCaches() {
        runtimeInterpreter.prepareCaches();
    }

    /**
     * Stops a child interpreter for good: its playhead is cleared, it is not part of
     * saves anymore, and callbacks it handed out become no-ops. Throws on a root interpreter.
     */
    public void dispose() {
        RuntimeBridge.dispose(runtimeInterpreter);
    }

    /**
     * Starts script execution from the beginning or a specific beat.
     *
     * @param beatName optional name of the beat to start from (null for default)
     */
    public void start(String beatName) {
        RuntimeBridge.start(runtimeInterpreter, beatName);
    }

    /**
     * Saves the current state of the interpreter.
     *
     * @return a JSON string containing the serialized state
     */
    public String save() {
        return loreline.runtime.Json.stringify(runtimeInterpreter.save(), false);
    }

    /**
     * Restores the interpreter state from a previously saved state.
     *
     * @param savedData the JSON string containing the serialized state
     */
    public void restore(String savedData) {
        RuntimeBridge.restore(runtimeInterpreter, loreline.runtime.Json.parse(savedData));
    }

    /**
     * Resumes execution after restoring state.
     */
    public void resume() {
        runtimeInterpreter.resume();
    }

    /**
     * Gets a character's fields by name.
     *
     * @param name the name of the character
     * @return the character's fields or null
     */
    public Object getCharacter(String name) {
        return runtimeInterpreter.getCharacter(name);
    }

    /**
     * Gets a specific field of a character.
     *
     * @param character the name of the character
     * @param field the name of the field
     * @return the field value or null
     */
    public Object getCharacterField(String character, String field) {
        return runtimeInterpreter.getCharacterField(character, field);
    }

    /**
     * Sets a specific field of a character.
     *
     * @param character the name of the character
     * @param field the name of the field
     * @param value the value to set
     */
    public void setCharacterField(String character, String field, Object value) {
        runtimeInterpreter.setCharacterField(character, field, value);
    }

    /**
     * Gets a state field by name, resolving from the current scope outward.
     *
     * @param name the name of the field
     * @return the field value or null
     */
    public Object getStateField(String name) {
        return runtimeInterpreter.getStateField(name);
    }

    /**
     * Sets a state field by name, resolving from the current scope outward.
     *
     * @param name the name of the field
     * @param value the value to set
     */
    public void setStateField(String name, Object value) {
        runtimeInterpreter.setStateField(name, value);
    }

    /**
     * Gets a field from the top-level state directly.
     *
     * @param name the name of the field
     * @return the field value or null
     */
    public Object getTopLevelStateField(String name) {
        return runtimeInterpreter.getTopLevelStateField(name);
    }

    /**
     * Sets a field on the top-level state directly.
     *
     * @param name the name of the field
     * @param value the value to set
     */
    public void setTopLevelStateField(String name, Object value) {
        runtimeInterpreter.setTopLevelStateField(name, value);
    }

    /**
     * Returns the current node being executed.
     * During a dialogue callback, this returns the dialogue statement node.
     * During a choice callback, this returns the choice statement node.
     *
     * @return the current node or null if no node is being executed
     */
    public Node currentNode() {
        loreline.runtime.Node node = (loreline.runtime.Node) runtimeInterpreter.currentNode();
        return node != null ? new Node(node) : null;
    }

    // --- Helper methods ---

    @SuppressWarnings("rawtypes")
    static List<TextTag> wrapTags(Object rawTagsObj) {
        loreline.internal.root.Array rawTags = (loreline.internal.root.Array) rawTagsObj;
        List<TextTag> tags = new ArrayList<>(rawTags.length);
        for (int i = 0; i < rawTags.length; i++) {
            loreline.runtime.TextTag raw = (loreline.runtime.TextTag) rawTags.__a[i];
            tags.add(new TextTag(raw.closing, raw.value, raw.offset));
        }
        return tags;
    }

    @SuppressWarnings("rawtypes")
    static List<ChoiceOption> wrapChoiceOptions(Object rawOptionsObj) {
        loreline.internal.root.Array rawOptions = (loreline.internal.root.Array) rawOptionsObj;
        List<ChoiceOption> options = new ArrayList<>(rawOptions.length);
        for (int i = 0; i < rawOptions.length; i++) {
            loreline.runtime.ChoiceOption raw = (loreline.runtime.ChoiceOption) rawOptions.__a[i];
            options.add(new ChoiceOption(raw.text, wrapTags(raw.tags), raw.enabled));
        }
        return options;
    }

    private static loreline.internal.ds.StringMap<Object> wrapFunctions(
            Interpreter interpreter, Map<String, LorelineFunction> functions) {
        loreline.internal.ds.StringMap<Object> result = new loreline.internal.ds.StringMap<>();
        for (Map.Entry<String, LorelineFunction> entry : functions.entrySet()) {
            result.set(entry.getKey(), new FunctionBridge(interpreter, entry.getValue()));
        }
        return result;
    }

    // --- Bridge classes ---

    private static class DialogueBridge extends loreline.internal.jvm.Function {
        private final Interpreter interpreter;
        private final DialogueHandler handler;

        DialogueBridge(Interpreter interpreter, DialogueHandler handler) {
            this.interpreter = interpreter;
            this.handler = handler;
        }

        @Override
        public void invoke(Object arg1, Object arg2, Object arg3, Object arg4, Object arg5) {
            // args: interpreterOrWrapper, character, text, tags, callback
            String character = (String) arg2;
            String text = (String) arg3;
            loreline.internal.jvm.Function callback = (loreline.internal.jvm.Function) arg5;

            handler.handle(interpreter, character, text, wrapTags(arg4), () -> {
                callback.invokeDynamic(EMPTY_ARGS);
            });
        }
    }

    private static class ChoiceBridge extends loreline.internal.jvm.Function {
        private final Interpreter interpreter;
        private final ChoiceHandler handler;

        ChoiceBridge(Interpreter interpreter, ChoiceHandler handler) {
            this.interpreter = interpreter;
            this.handler = handler;
        }

        @Override
        public void invoke(Object arg1, Object arg2, Object arg3) {
            // args: interpreterOrWrapper, options, callback
            loreline.internal.jvm.Function callback = (loreline.internal.jvm.Function) arg3;

            handler.handle(interpreter, wrapChoiceOptions(arg2), (int index) -> {
                ARGS_1[0] = (double) index;
                callback.invokeDynamic(ARGS_1);
            });
        }
    }

    private static class FinishBridge extends loreline.internal.jvm.Function {
        private final Interpreter interpreter;
        private final FinishHandler handler;

        FinishBridge(Interpreter interpreter, FinishHandler handler) {
            this.interpreter = interpreter;
            this.handler = handler;
        }

        @Override
        public void invoke(Object arg1) {
            // args: interpreterOrWrapper
            handler.handle(interpreter);
        }
    }

    private static class FunctionBridge extends loreline.internal.jvm.Function {
        private final Interpreter interpreter;
        private final LorelineFunction func;

        FunctionBridge(Interpreter interpreter, LorelineFunction func) {
            this.interpreter = interpreter;
            this.func = func;
        }

        @Override
        public Object invokeDynamic(Object[] args) {
            return func.call(interpreter, args);
        }
    }

    private static class CreateFieldsBridge extends loreline.internal.jvm.Function {
        private final Interpreter interpreter;
        private final InterpreterOptions.CreateFieldsHandler handler;

        CreateFieldsBridge(Interpreter interpreter, InterpreterOptions.CreateFieldsHandler handler) {
            this.interpreter = interpreter;
            this.handler = handler;
        }

        @Override
        public Object invoke(Object arg1, Object arg2, Object arg3) {
            // args: interpreter, type, node
            return handler.create(interpreter, (String) arg2);
        }
    }
}
