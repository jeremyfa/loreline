using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;
using System.Collections.Generic;

namespace Loreline
{
    /// <summary>
    /// The main public API for Loreline runtime.
    /// Provides easy access to the core functionality for parsing and running Loreline scripts.
    /// </summary>
    public static class Engine
    {
        public delegate void ImportsFileCallback(string data);

        public delegate void ImportsFileHandler(string path, ImportsFileCallback callback);

        public delegate void ParseCallback(Script script);

        /// <summary>
        /// Parses the given text input and creates an executable <see cref="Script"/> instance from it.
        /// </summary>
        /// <remarks>
        /// This is the first step in working with a Loreline script. The returned
        /// <see cref="Script"/> object can then be passed to methods Play() or Resume().
        /// </remarks>
        /// <param name="input">The Loreline script content as a string (.lor format)</param>
        /// <param name="filePath">(optional) The file path of the input being parsed. If provided, requires `handleFile` as well.</param>
        /// <param name="handleFile">(optional) A file handler to read imports. If that handler is asynchronous, then `parse()` method will return null and `callback` argument should be used to get the final script</param>
        /// <param name="callback">If provided, will be called with the resulting script as argument. Mostly useful when reading file imports asynchronously</param>
        /// <returns>The parsed script as an AST <see cref="Script"/> instance (if loaded synchronously)</returns>
        /// <exception cref="Runtime.Error">Thrown if the script contains syntax errors or other parsing issues</exception>
        public static Script Parse(string input, string filePath = null, ImportsFileHandler handleFile = null, ParseCallback callback = null)
        {
            Script result = null;

            ImportsFileHandlerWrap handleFileWrap = null;
            if (handleFile != null)
            {
                handleFileWrap = new ImportsFileHandlerWrap(handleFile);
            }
            ParseCallbackWrap callbackWrap = null;
            if (callback != null)
            {
                callbackWrap = new ParseCallbackWrap(script =>
                {
                    result = script;
                    callback(result);
                });
            }
            Runtime.Script runtimeScript = Runtime.Loreline.parse(
                input, filePath, handleFileWrap, callbackWrap
            );
            if (runtimeScript != null && callbackWrap == null && result == null)
            {
                result = new Script(runtimeScript);
            }
            return result;
        }

        /// <summary>
        /// Starts playing a Loreline script from the beginning or a specific beat.
        /// </summary>
        /// <remarks>
        /// This function takes care of initializing the interpreter and starting execution
        /// immediately. You'll need to provide handlers for dialogues, choices, and
        /// script completion.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="beatName">Name of a specific beat to start from (defaults to first beat)</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Play(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string beatName = null
        )
        {
            return Play(script, handleDialogue, handleChoice, handleFinish, beatName, Interpreter.InterpreterOptions.Default());
        }

        /// <summary>
        /// Starts playing a Loreline script from the beginning or a specific beat.
        /// </summary>
        /// <remarks>
        /// This function takes care of initializing the interpreter and starting execution
        /// immediately. You'll need to provide handlers for dialogues, choices, and
        /// script completion.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="options">Additional options</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Play(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            Interpreter.InterpreterOptions options
        )
        {
            return Play(script, handleDialogue, handleChoice, handleFinish, null, options);
        }

        /// <summary>
        /// Starts playing a Loreline script from the beginning or a specific beat.
        /// </summary>
        /// <remarks>
        /// This function takes care of initializing the interpreter and starting execution
        /// immediately. You'll need to provide handlers for dialogues, choices, and
        /// script completion.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="beatName">Name of a specific beat to start from (defaults to first beat)</param>
        /// <param name="options">Additional options</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Play(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string beatName,
            Interpreter.InterpreterOptions options
        )
        {
            Interpreter interpreter = new Interpreter(
                script,
                handleDialogue,
                handleChoice,
                handleFinish,
                options
            );

            interpreter.Start(beatName);

            return interpreter;
        }

        /// <summary>
        /// Resumes a previously saved Loreline script from its saved state.
        /// </summary>
        /// <remarks>
        /// This allows you to continue a story from the exact point where it was saved,
        /// restoring all state variables, choices, and player progress.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="saveData">The saved game data (typically from <see cref="Interpreter.Save"/>)</param>
        /// <param name="beatName">Optional beat name to override where to resume from</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Resume(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string saveData,
            string beatName = null
        )
        {
            return Resume(script, handleDialogue, handleChoice, handleFinish, saveData, beatName, Interpreter.InterpreterOptions.Default());
        }

        /// <summary>
        /// Resumes a previously saved Loreline script from its saved state.
        /// </summary>
        /// <remarks>
        /// This allows you to continue a story from the exact point where it was saved,
        /// restoring all state variables, choices, and player progress.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="saveData">The saved game data (typically from <see cref="Interpreter.Save"/>)</param>
        /// <param name="options">Additional options</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Resume(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string saveData,
            Interpreter.InterpreterOptions options
        )
        {
            return Resume(script, handleDialogue, handleChoice, handleFinish, saveData, null, options);
        }

        /// <summary>
        /// Resumes a previously saved Loreline script from its saved state.
        /// </summary>
        /// <remarks>
        /// This allows you to continue a story from the exact point where it was saved,
        /// restoring all state variables, choices, and player progress.
        /// </remarks>
        /// <param name="script">The parsed script (result from <see cref="Parse"/>)</param>
        /// <param name="handleDialogue">Function called when dialogue text should be displayed</param>
        /// <param name="handleChoice">Function called when player needs to make a choice</param>
        /// <param name="handleFinish">Function called when script execution completes</param>
        /// <param name="saveData">The saved game data (typically from <see cref="Interpreter.Save"/>)</param>
        /// <param name="beatName">Optional beat name to override where to resume from</param>
        /// <param name="options">Additional options</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Resume(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string saveData,
            string beatName,
            Interpreter.InterpreterOptions options
        )
        {
            Interpreter interpreter = new Interpreter(
                script,
                handleDialogue,
                handleChoice,
                handleFinish,
                options
            );

            interpreter.Restore(saveData);

            if (beatName != null)
            {
                interpreter.Start(beatName);
            }
            else
            {
                interpreter.Resume();
            }

            return interpreter;
        }

        private class ImportsFileHandlerWrap : Internal.Lang.Function
        {
            private ImportsFileHandler handler;
            public ImportsFileHandlerWrap(ImportsFileHandler handler) : base(2, 1)
            {
                this.handler = handler;
            }

            public override object __hx_invoke2_o(double __fn_float1, object __fn_dyn1, double __fn_float2, object __fn_dyn2)
            {
                handler((string)__fn_dyn1, (string data) =>
                {
                    ((Internal.Lang.Function)__fn_dyn2).__hx_invoke1_o((double)0, data);
                });
                return null;
            }
        }

        private class ParseCallbackWrap : Internal.Lang.Function
        {
            private ParseCallback callback;
            public ParseCallbackWrap(ParseCallback callback) : base(1, 1)
            {
                this.callback = callback;
            }

            public override object __hx_invoke1_o(double __fn_float1, object __fn_dyn1)
            {
                callback(new Script((Runtime.Script)__fn_dyn1));
                return null;
            }
        }
    }
}