using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;

namespace Loreline
{
    /// <summary>
    /// Represents the root node of a Loreline script AST.
    /// </summary>
    public class Script : Node
    {
        /// <summary>
        /// The underlying runtime script instance.
        /// </summary>
        public readonly Runtime.Script RuntimeScript;

        /// <summary>
        /// Creates a new Script instance with the provided runtime script.
        /// </summary>
        /// <param name="runtimeScript">The parsed runtime script to wrap</param>
        public Script(Runtime.Script runtimeScript) : base(runtimeScript)
        {
            this.RuntimeScript = runtimeScript;
        }

        /// <summary>
        /// Reconstructs a Script from a JSON string.
        /// </summary>
        /// <param name="json">A JSON string (as returned by <see cref="Node.ToJson"/>)</param>
        /// <returns>The reconstructed Script</returns>
        public static new Script FromJson(string json)
        {
            object parsed = Runtime.Json.parse(json);
            Runtime.Script runtimeScript = Runtime.Script.fromJson(parsed);
            return new Script(runtimeScript);
        }
    }
}