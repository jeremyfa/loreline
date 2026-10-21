using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;
using System.Collections.Generic;

namespace Loreline
{
    /// <summary>
    /// Main interpreter class for Loreline scripts.
    /// This class is responsible for executing a parsed Loreline script,
    /// managing the runtime state, and interacting with the host application
    /// through handler functions.
    /// </summary>
    public class Interpreter
    {
        /// <summary>
        /// Represents a tag in text content, which can be used for styling or other purposes.
        /// </summary>
        public struct TextTag
        {
            /// <summary>
            /// Whether this is a closing tag.
            /// </summary>
            public bool Closing;

            /// <summary>
            /// The value or name of the tag.
            /// </summary>
            public string Value;

            /// <summary>
            /// Where the tag appears in the text, in characters (Unicode code points)
            /// from its start, the same on every target. A C# string counts UTF-16
            /// units instead, where a character above U+FFFF, such as most emoji, is a
            /// surrogate pair: count each pair (<c>char.IsSurrogatePair</c>) as one
            /// character to find the index in the string.
            /// </summary>
            public int Offset;
        }

        /// <summary>
        /// Represents a choice option presented to the user.
        /// </summary>
        public struct ChoiceOption
        {
            /// <summary>
            /// The text of the choice option.
            /// </summary>
            public string Text;

            /// <summary>
            /// Any tags associated with the choice text.
            /// </summary>
            public TextTag[] Tags;

            /// <summary>
            /// Whether this choice option is currently enabled.
            /// </summary>
            public bool Enabled;
        }

        /// <summary>
        /// Delegate type for functions that can be called from the script.
        /// </summary>
        /// <param name="interpreter">The interpreter instance</param>
        /// <param name="args">Arguments passed to the function</param>
        /// <returns>The result of the function</returns>
        public delegate object Function(Interpreter interpreter, object[] args);

        /// <summary>
        /// Callback type for dialogue continuation.
        /// </summary>
        public delegate void DialogueCallback();

        /// <summary>
        /// Contains information about a dialogue to be displayed to the user.
        /// </summary>
        public struct Dialogue
        {
            /// <summary>
            /// The interpreter instance.
            /// </summary>
            public Interpreter Interpreter;

            /// <summary>
            /// The character speaking (null for narrator text).
            /// </summary>
            public string Character;

            /// <summary>
            /// The text content to display.
            /// </summary>
            public string Text;

            /// <summary>
            /// Any tags in the text.
            /// </summary>
            public TextTag[] Tags;

            /// <summary>
            /// Function to call when the text has been displayed.
            /// </summary>
            public DialogueCallback Callback;
        }

        /// <summary>
        /// Handler type for text output with callback.
        /// This is called when the script needs to display text to the user.
        /// </summary>
        /// <param name="dialogue">A Dialogue structure containing all necessary information</param>
        public delegate void DialogueHandler(Dialogue dialogue);

        /// <summary>
        /// Callback type for choice selection.
        /// </summary>
        /// <param name="index">The index of the selected choice</param>
        public delegate void ChoiceCallback(int index);

        /// <summary>
        /// Contains information about choices to be presented to the user.
        /// </summary>
        public struct Choice
        {
            /// <summary>
            /// The interpreter instance.
            /// </summary>
            public Interpreter Interpreter;

            /// <summary>
            /// The available choice options.
            /// </summary>
            public ChoiceOption[] Options;

            /// <summary>
            /// Function to call with the index of the selected choice.
            /// </summary>
            public ChoiceCallback Callback;
        }

        /// <summary>
        /// Handler type for choice presentation with callback.
        /// This is called when the script needs to present choices to the user.
        /// </summary>
        /// <param name="choice">A Choice structure containing all necessary information</param>
        public delegate void ChoiceHandler(Choice choice);

        /// <summary>
        /// A custom instanciator to create fields objects.
        /// </summary>
        /// <param name="interpreter">The interpreter related to this object creation</param>
        /// <param name="type">The expected type of the object, if there is any known</param>
        /// <param name="node">The associated node in the script, if any</param>
        /// <returns></returns>
        public delegate object CreateFields(Interpreter interpreter, string type, Node node);

        /// <summary>
        /// Contains information about the script execution completion.
        /// </summary>
        public struct Finish
        {
            /// <summary>
            /// The interpreter instance.
            /// </summary>
            public Interpreter Interpreter;
        }

        public struct InterpreterOptions
        {
            /// <summary>
            /// Retrieve default interpreter options
            /// </summary>
            public static InterpreterOptions Default()
            {
                return new InterpreterOptions
                {
                    Functions = null,
                    StrictAccess = false,
                    CustomCreateFields = null,
                    Translations = null,
                    PrepareCaches = false
                };
            }

            /// <summary>
            /// Optional map of additional functions to make available to the script
            /// </summary>
            public Dictionary<string, Function> Functions;

            /// <summary>
            /// Tells whether access is strict or not. If set to true,
            /// trying to read or write an undefined variable will throw an error.
            /// </summary>
            public bool StrictAccess;

            /// <summary>
            /// A custom instantiator to create fields objects.
            /// </summary>
            public CreateFields CustomCreateFields;

            /// <summary>
            /// Optional translations map for localization.
            /// Built from a parsed translation file using Engine.ExtractTranslations().
            /// </summary>
            public object Translations;

            /// <summary>
            /// If set to true, the interpreter prepares its caches when it is created,
            /// before the script starts, like Interpreter.PrepareCaches().
            /// </summary>
            public bool PrepareCaches;
        }

        /// <summary>
        /// Handler type to be called when the execution finishes.
        /// </summary>
        /// <param name="finish">A Finish structure containing the interpreter instance</param>
        public delegate void FinishHandler(Finish finish);

        /// <summary>
        /// The underlying runtime interpreter instance.
        /// </summary>
        public readonly Runtime.Interpreter RuntimeInterpreter;

        // Kept so that a spawned child can wrap the same handlers and functions,
        // bound to its own wrapper
        private readonly DialogueHandler handleDialogue;
        private readonly ChoiceHandler handleChoice;
        private readonly FinishHandler handleFinish;
        private readonly Dictionary<string, Function> functions;
        private readonly CreateFields customCreateFields;
        private readonly bool strictAccess;

        /// <summary>
        /// Creates a new Loreline script interpreter.
        /// </summary>
        /// <param name="script">The parsed script to execute</param>
        /// <param name="handleDialogue">Function to call when displaying dialogue text</param>
        /// <param name="handleChoice">Function to call when presenting choices</param>
        /// <param name="handleFinish">Function to call when execution finishes</param>
        public Interpreter(
            Script script,
            DialogueHandler handleDialogue,
            ChoiceHandler handleChoice,
            FinishHandler handleFinish
        )
        {
            InterpreterOptions options = new InterpreterOptions
            {
                Functions = null,
                StrictAccess = false,
                CustomCreateFields = null
            };

            this.handleDialogue = handleDialogue;
            this.handleChoice = handleChoice;
            this.handleFinish = handleFinish;
            this.functions = options.Functions;
            this.customCreateFields = options.CustomCreateFields;
            this.strictAccess = options.StrictAccess;

            DialogueHandlerWrap handleDialogueWrap = new DialogueHandlerWrap(this, handleDialogue);
            ChoiceHandlerWrap handleChoiceWrap = new ChoiceHandlerWrap(this, handleChoice);
            FinishHandlerWrap handleFinishWrap = new FinishHandlerWrap(this, handleFinish);
            Internal.Ds.StringMap functionsWrap = WrapFunctions(this, options.Functions);
            CreateFieldsWrap createFieldsWrap = WrapCreateFields(this, options.CustomCreateFields);

            RuntimeInterpreter = new Runtime.Interpreter(
                script.RuntimeScript,
                handleDialogueWrap,
                handleChoiceWrap,
                handleFinishWrap,
                new Runtime.InterpreterOptions(this, functionsWrap, options.StrictAccess, createFieldsWrap, null, null, options.PrepareCaches),
                null
            );
        }

        /// <summary>
        /// Creates a new Loreline script interpreter.
        /// </summary>
        /// <param name="script">The parsed script to execute</param>
        /// <param name="handleDialogue">Function to call when displaying dialogue text</param>
        /// <param name="handleChoice">Function to call when presenting choices</param>
        /// <param name="handleFinish">Function to call when execution finishes</param>
        /// <param name="options">Additional options</param>
        public Interpreter(
            Script script,
            DialogueHandler handleDialogue,
            ChoiceHandler handleChoice,
            FinishHandler handleFinish,
            InterpreterOptions options
        )
        {
            this.handleDialogue = handleDialogue;
            this.handleChoice = handleChoice;
            this.handleFinish = handleFinish;
            this.functions = options.Functions;
            this.customCreateFields = options.CustomCreateFields;
            this.strictAccess = options.StrictAccess;

            DialogueHandlerWrap handleDialogueWrap = new DialogueHandlerWrap(this, handleDialogue);
            ChoiceHandlerWrap handleChoiceWrap = new ChoiceHandlerWrap(this, handleChoice);
            FinishHandlerWrap handleFinishWrap = new FinishHandlerWrap(this, handleFinish);
            Internal.Ds.StringMap functionsWrap = WrapFunctions(this, options.Functions);
            CreateFieldsWrap createFieldsWrap = WrapCreateFields(this, options.CustomCreateFields);
            Internal.Ds.StringMap translationsWrap = WrapTranslations(options.Translations);

            RuntimeInterpreter = new Runtime.Interpreter(
                script.RuntimeScript,
                handleDialogueWrap,
                handleChoiceWrap,
                handleFinishWrap,
                new Runtime.InterpreterOptions(this, functionsWrap, options.StrictAccess, createFieldsWrap, translationsWrap, null, options.PrepareCaches),
                null
            );
        }

        /// <summary>
        /// Creates the wrapper of a child interpreter, spawned from (or resumed through) a parent.
        /// Handlers left null reuse the ones of the parent, wrapped again so that they receive the child.
        /// </summary>
        private Interpreter(
            Interpreter parent,
            string key,
            DialogueHandler handleDialogue,
            ChoiceHandler handleChoice,
            FinishHandler handleFinish,
            bool resume
        )
        {
            this.handleDialogue = handleDialogue ?? parent.handleDialogue;
            this.handleChoice = handleChoice ?? parent.handleChoice;
            this.handleFinish = handleFinish ?? parent.handleFinish;
            this.functions = parent.functions;
            this.customCreateFields = parent.customCreateFields;
            this.strictAccess = parent.strictAccess;

            DialogueHandlerWrap handleDialogueWrap = new DialogueHandlerWrap(this, this.handleDialogue);
            ChoiceHandlerWrap handleChoiceWrap = new ChoiceHandlerWrap(this, this.handleChoice);
            FinishHandlerWrap handleFinishWrap = new FinishHandlerWrap(this, this.handleFinish);

            // Function adapters bound to this wrapper, so that host functions receive the child
            Runtime.InterpreterOptions childOptions = new Runtime.InterpreterOptions(
                this,
                WrapFunctions(this, functions),
                strictAccess,
                WrapCreateFields(this, customCreateFields),
                null,
                null,
                false
            );

            RuntimeInterpreter = resume
                ? parent.RuntimeInterpreter.resumeSpawn(key, handleDialogueWrap, handleChoiceWrap, handleFinishWrap, childOptions)
                : parent.RuntimeInterpreter.spawn(key, handleDialogueWrap, handleChoiceWrap, handleFinishWrap, childOptions);
        }

        /// <summary>
        /// Key of this interpreter when it was spawned from another one, null for a root interpreter.
        /// </summary>
        public string Key => RuntimeInterpreter.key;

        /// <summary>
        /// Whether this interpreter is a root interpreter (not spawned from another one).
        /// </summary>
        public bool IsRoot()
        {
            return RuntimeInterpreter.isRoot();
        }

        /// <summary>
        /// Spawns a child interpreter that shares everything with this one (script, state,
        /// characters, functions) except the playhead. The child is not started: call Start()
        /// on it. Any live child using the same key is disposed first, and a restored flow still
        /// pending for that key is discarded (use ResumeSpawn() to continue it instead).
        /// Calling Save() on any interpreter of the family saves the shared state and every playhead.
        /// </summary>
        /// <param name="key">Identifies the child, notably to resume it after a restore</param>
        /// <param name="handleDialogue">Dialogue handler of the child, or null to reuse the one of this interpreter</param>
        /// <param name="handleChoice">Choice handler of the child, or null to reuse the one of this interpreter</param>
        /// <param name="handleFinish">Finish handler of the child, or null to reuse the one of this interpreter</param>
        /// <returns>The child interpreter</returns>
        public Interpreter Spawn(string key, DialogueHandler handleDialogue = null, ChoiceHandler handleChoice = null, FinishHandler handleFinish = null)
        {
            return new Interpreter(this, key, handleDialogue, handleChoice, handleFinish, false);
        }

        /// <summary>
        /// Rebuilds a child interpreter from the flow saved under the given key, after Restore()
        /// on the root interpreter (or Engine.Resume()). The child is not resumed yet: call Resume() on it.
        /// </summary>
        /// <param name="key">The key the child had when it was saved (see ResumableSpawnKeys())</param>
        /// <param name="handleDialogue">Dialogue handler of the child, or null to reuse the one of this interpreter</param>
        /// <param name="handleChoice">Choice handler of the child, or null to reuse the one of this interpreter</param>
        /// <param name="handleFinish">Finish handler of the child, or null to reuse the one of this interpreter</param>
        /// <returns>The restored child interpreter</returns>
        /// <exception cref="Runtime.RuntimeError">Thrown if no restored flow is pending for this key</exception>
        public Interpreter ResumeSpawn(string key, DialogueHandler handleDialogue = null, ChoiceHandler handleChoice = null, FinishHandler handleFinish = null)
        {
            return new Interpreter(this, key, handleDialogue, handleChoice, handleFinish, true);
        }

        /// <summary>
        /// Keys of the saved children not resumed with ResumeSpawn() (nor replaced with Spawn()) yet.
        /// </summary>
        public string[] ResumableSpawnKeys()
        {
            Internal.Root.Array rawKeys = (Internal.Root.Array)RuntimeInterpreter.resumableSpawnKeys();
            string[] keys = new string[rawKeys.length];
            for (int i = 0; i < rawKeys.length; i++)
            {
                keys[i] = (string)rawKeys.__a[i];
            }
            return keys;
        }

        /// <summary>
        /// Reseeds the random generator shared by this interpreter, its root and every child.
        /// The generator is part of save data, so a restored game draws the same random
        /// values as it would have without the save. Call this after a restore to break that on purpose.
        /// </summary>
        /// <param name="seed">The seed of the new sequence, or null for a seed taken from the clock</param>
        public void SeedRandom(double? seed = null)
        {
            RuntimeInterpreter.seedRandom(seed.HasValue ? (object)seed.Value : null);
        }

        /// <summary>
        /// Builds now what the interpreter would otherwise build the first time it needs it,
        /// so that the cost is paid at a chosen moment, like a loading screen, rather than
        /// during play: for now, what each when block needs to pick a rule, which takes a
        /// moment on blocks of thousands of rules. Optional, it never changes what the script
        /// plays, and a second call only builds what is missing. Interpreters spawned from
        /// this one share these caches. See also InterpreterOptions.PrepareCaches.
        /// </summary>
        public void PrepareCaches()
        {
            RuntimeInterpreter.prepareCaches();
        }

        /// <summary>
        /// Stops a child interpreter for good: its playhead is cleared, it is not part of
        /// saves anymore, and callbacks it handed out become no-ops.
        /// </summary>
        /// <exception cref="Runtime.RuntimeError">Thrown if called on a root interpreter</exception>
        public void Dispose()
        {
            RuntimeInterpreter.dispose();
        }

        /// <summary>
        /// Starts script execution from the beginning or a specific beat.
        /// </summary>
        /// <param name="beatName">Optional name of the beat to start from. If null, execution starts from
        /// the first beat or a beat named "_" if it exists.</param>
        /// <exception cref="Runtime.RuntimeError">Thrown if the specified beat doesn't exist or if no beats are found in the script</exception>
        public void Start(string beatName = null)
        {
            RuntimeInterpreter.start(beatName);
        }

        /// <summary>
        /// Saves the current state of the interpreter.
        /// This includes all state variables, character states, and execution stack,
        /// allowing execution to be resumed later from the exact same point.
        /// </summary>
        /// <returns>A JSON string containing the serialized state</returns>
        public string Save()
        {
            return Runtime.Json.stringify(RuntimeInterpreter.save(), false);
        }

        /// <summary>
        /// Restores the interpreter state from a previously saved state.
        /// This allows resuming execution from a previously saved state.
        /// </summary>
        /// <param name="savedData">The JSON string containing the serialized state</param>
        /// <exception cref="Runtime.RuntimeError">Thrown if the save data version is incompatible</exception>
        public void Restore(string savedData)
        {
            RuntimeInterpreter.restore(Runtime.Json.parse(savedData));
        }

        /// <summary>
        /// Resumes execution after restoring state.
        /// This should be called after Restore() to continue execution.
        /// </summary>
        public void Resume()
        {
            RuntimeInterpreter.resume();
        }

        /// <summary>
        /// Gets a character by name.
        /// </summary>
        /// <param name="name">The name of the character to get</param>
        /// <returns>The character's fields or null if the character doesn't exist</returns>
        public object GetCharacter(string name)
        {
            return RuntimeInterpreter.getCharacter(name);
        }

        /// <summary>
        /// Gets a specific field of a character.
        /// </summary>
        /// <param name="character">The name of the character</param>
        /// <param name="name">The name of the field to get</param>
        /// <returns>The field value or null if the character or field doesn't exist</returns>
        public object GetCharacterField(string character, string name)
        {
            return RuntimeInterpreter.getCharacterField(character, name);
        }

        /// <summary>
        /// Sets a specific field of a character.
        /// </summary>
        /// <param name="character">The name of the character</param>
        /// <param name="name">The name of the field to set</param>
        /// <param name="value">The value to set</param>
        public void SetCharacterField(string character, string name, object value)
        {
            RuntimeInterpreter.setCharacterField(character, name, value);
        }

        /// <summary>
        /// Gets a state field by name, resolving from the current scope outward.
        /// </summary>
        /// <param name="name">The name of the field to get</param>
        /// <returns>The field value or null if not found</returns>
        public object GetStateField(string name)
        {
            return RuntimeInterpreter.getStateField(name);
        }

        /// <summary>
        /// Sets a state field by name, resolving from the current scope outward.
        /// </summary>
        /// <param name="name">The name of the field to set</param>
        /// <param name="value">The value to set</param>
        public void SetStateField(string name, object value)
        {
            RuntimeInterpreter.setStateField(name, value);
        }

        /// <summary>
        /// Gets a field from the top-level state directly.
        /// </summary>
        /// <param name="name">The name of the field to get</param>
        /// <returns>The field value or null if not found</returns>
        public object GetTopLevelStateField(string name)
        {
            return RuntimeInterpreter.getTopLevelStateField(name);
        }

        /// <summary>
        /// Sets a field on the top-level state directly.
        /// </summary>
        /// <param name="name">The name of the field to set</param>
        /// <param name="value">The value to set</param>
        public void SetTopLevelStateField(string name, object value)
        {
            RuntimeInterpreter.setTopLevelStateField(name, value);
        }

        /// <summary>
        /// Returns the current node being executed.
        /// During a dialogue callback, this returns the dialogue statement node.
        /// During a choice callback, this returns the choice statement node.
        /// </summary>
        /// <returns>The current node or null if no node is being executed</returns>
        public Node CurrentNode()
        {
            Runtime.Node node = (Runtime.Node)RuntimeInterpreter.currentNode();
            return node != null ? new Node(node) : null;
        }

        private static TextTag[] WrapTags(Internal.Root.Array rawTags)
        {
            TextTag[] tags = new TextTag[rawTags.length];
            for (int i = 0; i < rawTags.length; i++)
            {
                Runtime.TextTag rawTag = (Runtime.TextTag)rawTags.__a[i];
                tags[i] = new TextTag
                {
                    Closing = rawTag.closing,
                    Offset = rawTag.offset,
                    Value = rawTag.value
                };
            }
            return tags;
        }

        private static ChoiceOption[] WrapChoiceOptions(Internal.Root.Array rawOptions)
        {
            ChoiceOption[] options = new ChoiceOption[rawOptions.length];
            for (int i = 0; i < rawOptions.length; i++)
            {
                Runtime.ChoiceOption rawOption = (Runtime.ChoiceOption)rawOptions.__a[i];
                options[i] = new ChoiceOption
                {
                    Text = rawOption.text,
                    Tags = WrapTags(rawOption.tags),
                    Enabled = rawOption.enabled
                };
            }
            return options;
        }

        private static Internal.Ds.StringMap WrapFunctions(Interpreter interpreter, Dictionary<string, Function> functions)
        {
            if (functions == null) return null;

            Internal.Ds.StringMap result = new Internal.Ds.StringMap();

            foreach (KeyValuePair<string, Function> pair in functions)
            {
                result.set(pair.Key, new FunctionWrap(interpreter, pair.Value));
            }

            return result;
        }

        private static CreateFieldsWrap WrapCreateFields(Interpreter interpreter, CreateFields createFields)
        {
            if (createFields == null) return null;

            return new CreateFieldsWrap(interpreter, createFields);
        }

        private static Internal.Ds.StringMap WrapTranslations(object translations)
        {
            if (translations == null) return null;

            // Translations is an opaque object returned by Engine.ExtractTranslations(),
            // which is already a StringMap internally.
            return (Internal.Ds.StringMap)translations;
        }

        private class FunctionWrap : Internal.Lang.Function
        {
            private Interpreter interpreter;
            private Function func;
            public FunctionWrap(Interpreter interpreter, Function func) : base(-1, 1)
            {
                this.interpreter = interpreter;
                this.func = func;
            }

            public override object __hx_invokeDynamic(object[] __fn_dynargs)
            {
                return func(interpreter, __fn_dynargs);
            }
        }

        private class CreateFieldsWrap : Internal.Lang.Function
        {
            private Interpreter interpreter;
            private CreateFields createFields;
            public CreateFieldsWrap(Interpreter interpreter, CreateFields createFields) : base(3, 1)
            {
                this.interpreter = interpreter;
                this.createFields = createFields;
            }

            public override object __hx_invoke3_o(double __fn_float1, object __fn_dyn1, double __fn_float2, object __fn_dyn2, double __fn_float3, object __fn_dyn3)
            {
                return createFields(
                    interpreter,
                    (string)__fn_dyn2,
                    __fn_dyn3 != null ? new Node((Runtime.Node)__fn_dyn3) : null
                );
            }
        }

        private class DialogueHandlerWrap : Internal.Lang.Function
        {
            private Interpreter interpreter;
            private DialogueHandler handler;
            public DialogueHandlerWrap(Interpreter interpreter, DialogueHandler handler) : base(5, 1)
            {
                this.interpreter = interpreter;
                this.handler = handler;
            }
            public override object __hx_invoke5_o(double __fn_float1, object __fn_dyn1, double __fn_float2, object __fn_dyn2, double __fn_float3, object __fn_dyn3, double __fn_float4, object __fn_dyn4, double __fn_float5, object __fn_dyn5)
            {
                handler(new Dialogue
                {
                    Interpreter = interpreter,
                    Character = (string)__fn_dyn2,
                    Text = (string)__fn_dyn3,
                    Tags = WrapTags((Internal.Root.Array)__fn_dyn4),
                    Callback = () =>
                    {
                        ((Internal.Lang.Function)__fn_dyn5).__hx_invoke0_o();
                    }
                });

                return null;
            }
        }

        private class ChoiceHandlerWrap : Internal.Lang.Function
        {
            private Interpreter interpreter;
            private ChoiceHandler handler;
            public ChoiceHandlerWrap(Interpreter interpreter, ChoiceHandler handler) : base(3, 1)
            {
                this.interpreter = interpreter;
                this.handler = handler;
            }
            public override object __hx_invoke3_o(double __fn_float1, object __fn_dyn1, double __fn_float2, object __fn_dyn2, double __fn_float3, object __fn_dyn3)
            {
                handler(new Choice
                {
                    Interpreter = interpreter,
                    Options = WrapChoiceOptions((Internal.Root.Array)__fn_dyn2),
                    Callback = (int index) =>
                    {
                        ((Internal.Lang.Function)__fn_dyn3).__hx_invoke1_o((double)index, Internal.Lang.Runtime.undefined);
                    }
                });

                return null;
            }
        }

        private class FinishHandlerWrap : Internal.Lang.Function
        {
            private Interpreter interpreter;
            private FinishHandler handler;
            public FinishHandlerWrap(Interpreter interpreter, FinishHandler handler) : base(5, 1)
            {
                this.interpreter = interpreter;
                this.handler = handler;
            }
            public override object __hx_invoke1_o(double __fn_float1, object __fn_dyn1)
            {
                handler(new Finish
                {
                    Interpreter = interpreter
                });
                return null;
            }
        }
    }
}