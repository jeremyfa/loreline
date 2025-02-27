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
    static class Loreline
    {
        /// <summary>
        /// Parses the given text input and creates an executable <see cref="Script"/> instance from it.
        /// </summary>
        /// <remarks>
        /// This is the first step in working with a Loreline script. The returned
        /// <see cref="Script"/> object can then be passed to methods <see cref="Play"/> or <see cref="Resume"/>.
        /// </remarks>
        /// <param name="input">The Loreline script content as a string (.lor format)</param>
        /// <returns>The parsed script as an AST <see cref="Script"/> instance</returns>
        /// <exception cref="Runtime.Error">Thrown if the script contains syntax errors or other parsing issues</exception>
        public static Script Parse(string input)
        {
            Runtime.Script script = Runtime.Loreline.parse(input);
            if (script != null)
            {
                return new Script(script);
            }
            return null;
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
        /// <param name="beatName">Optional name of a specific beat to start from (defaults to first beat)</param>
        /// <param name="functions">Optional dictionary of custom functions to make available in the script</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Play(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string beatName = null,
            Dictionary<string, Interpreter.Function> functions = null
        )
        {
            Interpreter interpreter = new Interpreter(
                script,
                handleDialogue,
                handleChoice,
                handleFinish,
                functions
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
        /// <param name="functions">Optional dictionary of custom functions to make available in the script</param>
        /// <returns>The interpreter instance that is running the script</returns>
        public static Interpreter Resume(
            Script script,
            Interpreter.DialogueHandler handleDialogue,
            Interpreter.ChoiceHandler handleChoice,
            Interpreter.FinishHandler handleFinish,
            string saveData,
            string beatName = null,
            Dictionary<string, Interpreter.Function> functions = null
        )
        {
            Interpreter interpreter = new Interpreter(
                script,
                handleDialogue,
                handleChoice,
                handleFinish,
                functions
            );

            interpreter.Restore(saveData);
            interpreter.Resume();

            return interpreter;
        }
    }
}