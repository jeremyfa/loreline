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
        /// Gets a field of the story's metadata block, like its title, author or IFID.
        /// Values have the same types as state fields.
        /// </summary>
        /// <param name="name">The name of the field to get</param>
        /// <returns>The field value or null if the block doesn't give it</returns>
        public object GetMetadataField(string name)
        {
            return RuntimeScript.getMetadataField(name);
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