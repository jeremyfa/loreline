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

        loreline.runtime.InterpreterOptions runtimeOptions =
            new loreline.runtime.InterpreterOptions(
                createFieldsBridge,   // customCreateFields
                functionsMap,         // functions
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
            runtimeOptions
        );
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
