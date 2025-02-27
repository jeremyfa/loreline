using System;
using Runtime = Loreline.Runtime;
using Internal = Loreline.Internal;

namespace Loreline
{
    /// <summary>
    /// Represents the root node of a Loreline script AST.
    /// </summary>
    class Script
    {
        /// <summary>
        /// The underlying runtime script instance.
        /// </summary>
        public readonly Runtime.Script runtimeScript;

        /// <summary>
        /// Creates a new Script instance with the provided runtime script.
        /// </summary>
        /// <param name="runtimeScript">The parsed runtime script to wrap</param>
        public Script(Runtime.Script runtimeScript)
        {
            this.runtimeScript = runtimeScript;
        }

        /// <summary>
        /// Converts the script to a JSON representation.
        /// This can be used for debugging or serialization purposes.
        /// </summary>
        /// <param name="pretty">Whether to format the JSON with indentation and line breaks</param>
        /// <returns>A JSON string representation of the script</returns>
        public string ToJson(bool pretty = false)
        {
            return Runtime.Json.stringify(runtimeScript.toJson(), pretty);
        }
    }
}